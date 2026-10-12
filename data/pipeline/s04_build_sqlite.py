"""Step 4: assemble build/words.sqlite from lemmas + lexicon + CMUdict."""
import datetime as dt
import json
import os
import re
import sqlite3
import tempfile
from pathlib import Path
from collections import defaultdict
from importlib.metadata import version

from common import CMUDICT, LEMMAS_TSV, LEXICON_JSONL, WORDS_SQLITE

SCHEMA_VERSION = "1"
MAX_SENSES = 3
# ARPAbet → IPA (General American). Stress digits handled separately.
ARPA = {
    "AA": "ɑ", "AE": "æ", "AH": "ʌ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ", "EH": "ɛ",
    "ER": "ɝ", "EY": "eɪ", "IH": "ɪ", "IY": "i", "OW": "oʊ", "OY": "ɔɪ", "UH": "ʊ",
    "UW": "u", "B": "b", "CH": "tʃ", "D": "d", "DH": "ð", "F": "f", "G": "ɡ",
    "HH": "h", "JH": "dʒ", "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ",
    "P": "p", "R": "ɹ", "S": "s", "SH": "ʃ", "T": "t", "TH": "θ", "V": "v",
    "W": "w", "Y": "j", "Z": "z", "ZH": "ʒ",
}
VOWELS = {"AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW"}


def arpa_to_ipa(phones: list[str]) -> str:
    out = []
    for p in phones:
        m = re.match(r"^([A-Z]+)([012])?$", p)
        if not m:
            continue
        ph, stress = m.group(1), m.group(2)
        if ph in VOWELS:
            if stress == "1":
                out.append("ˈ")
            elif stress == "2":
                out.append("ˌ")
            if ph == "AH" and stress == "0":
                out.append("ə")
                continue
            if ph == "ER" and stress == "0":
                out.append("ɚ")
                continue
        out.append(ARPA.get(ph, ""))
    s = "".join(out)
    if sum(1 for p in phones if re.sub(r"\d", "", p) in VOWELS) == 1:
        s = s.replace("ˈ", "").replace("ˌ", "")  # no stress mark on monosyllables
    # move stress mark before a preceding consonant cluster (approximate syllabification)
    s = re.sub(r"([^ˈˌaɪʊeoəɚɝæɛɑɔu]+)ˈ", r"ˈ\1", s)
    s = re.sub(r"([^ˈˌaɪʊeoəɚɝæɛɑɔu]+)ˌ", r"ˌ\1", s)
    return f"/{s}/"


def load_cmudict() -> dict:
    d = {}
    with CMUDICT.open(encoding="latin-1") as fh:
        for line in fh:
            if line.startswith(";;;"):
                continue
            parts = line.split("#")[0].split()
            if not parts:
                continue
            w = parts[0]
            if "(" in w:  # alternate pronunciation
                continue
            d[w.lower()] = arpa_to_ipa(parts[1:])
    return d


def pick_ipa(entries, cmu_ipa):
    """General American IPA. Wiktionary's *primary* entry (first non-proper-
    noun entry with sounds) wins only when its best transcription is tagged
    GA and is neither weak, regional nor vowel-reduced; otherwise CMUdict,
    which is uniformly GA; otherwise whatever Wiktionary has."""
    primary = next((e for e in sorted(entries, key=lambda e: e["pos"] == "name") if e["ipa"]), None)
    if primary is not None and not any(primary["ipa_flags"]):
        return primary["ipa"][0].replace("[", "/").replace("]", "/"), "wiktionary"
    if cmu_ipa:
        return cmu_ipa, "cmudict"
    if primary is not None:
        return primary["ipa"][0].replace("[", "/").replace("]", "/"), "wiktionary"
    return None, None


def order_entries(entries):
    """Wiktionary page order (primary meaning first), proper nouns last."""
    return sorted(entries, key=lambda e: e["pos"] == "name")


def pick_senses(entries):
    """Up to MAX_SENSES senses across entries: untagged first, entry order."""
    entries = order_entries(entries)
    good, bad = [], []
    for e in entries:
        for s in e["senses"]:
            (bad if s["tags"] else good).append((e["pos"], s))
    picked = (good + bad)[:MAX_SENSES]
    # ensure POS diversity: if the lemma has ≥2 POS, keep at least one sense of the 2nd POS
    pos_seen = {p for p, _ in picked}
    all_pos = [e["pos"] for e in entries if e["senses"]]
    if len(picked) == MAX_SENSES and len(set(all_pos)) > len(pos_seen):
        for p, s in good + bad:
            if p not in pos_seen:
                picked[-1] = (p, s)
                break
    return picked


def main() -> None:
    lexicon = {}
    with LEXICON_JSONL.open() as fh:
        for line in fh:
            o = json.loads(line)
            lexicon[o["lemma"]] = o["entries"]
    cmu = load_cmudict()

    with tempfile.TemporaryDirectory(prefix=".words-build-", dir=WORDS_SQLITE.parent) as staging_dir:
        staged_db = Path(staging_dir) / WORDS_SQLITE.name
        db = sqlite3.connect(staged_db)
        try:
            db.executescript("""
            CREATE TABLE word (
              id INTEGER PRIMARY KEY, lemma TEXT NOT NULL UNIQUE, rank INTEGER NOT NULL,
              band INTEGER NOT NULL, zipf REAL NOT NULL, ipa TEXT, ipa_source TEXT,
              is_proper INTEGER NOT NULL DEFAULT 0, is_abbrev INTEGER NOT NULL DEFAULT 0,
              pos TEXT NOT NULL);
            CREATE TABLE sense (
              id INTEGER PRIMARY KEY, word_id INTEGER NOT NULL REFERENCES word(id),
              ord INTEGER NOT NULL, pos TEXT NOT NULL, gloss TEXT NOT NULL, example TEXT);
            CREATE TABLE form (word_id INTEGER NOT NULL REFERENCES word(id), form TEXT NOT NULL,
              PRIMARY KEY (word_id, form));
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
            CREATE INDEX sense_word ON sense(word_id);
            CREATE INDEX form_form ON form(form);
            """)
            stats = defaultdict(int)
            with LEMMAS_TSV.open() as fh:
                next(fh)
                for line in fh:
                    rank, lemma, lex_key, zipf, _f, is_proper, is_abbrev, forms, _top = line.rstrip("\n").split("\t")
                    rank = int(rank)
                    entries = lexicon[lex_key]
                    pos_list = []
                    for e in order_entries(entries):
                        if e["pos"] not in pos_list and e["senses"]:
                            pos_list.append(e["pos"])
                    is_proper, abbrev = int(is_proper), int(is_abbrev)
                    ipa, src = pick_ipa(entries, cmu.get(lemma))
                    stats[f"ipa_{src}"] += 1
                    stats["proper"] += is_proper
                    stats["abbrev"] += abbrev
                    db.execute("INSERT INTO word VALUES (?,?,?,?,?,?,?,?,?,?)",
                               (rank, lemma, rank, (rank - 1) // 1000 + 1, float(zipf), ipa, src, is_proper, abbrev, ",".join(pos_list)))
                    senses = pick_senses(entries)
                    stats["no_sense"] += not senses
                    for i, (pos, s) in enumerate(senses, start=1):
                        db.execute("INSERT INTO sense (word_id, ord, pos, gloss, example) VALUES (?,?,?,?,?)",
                                   (rank, i, pos, s["gloss"], s["example"]))
                        stats["examples"] += bool(s["example"])
                    for f in filter(None, forms.split(",")):
                        db.execute("INSERT OR IGNORE INTO form VALUES (?,?)", (rank, f))
            meta = {
                "schema_version": SCHEMA_VERSION,
                "built": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
                "wordfreq_version": version("wordfreq"),
                "sources": "wordfreq (CC-BY-SA 4.0); Wiktionary via kaikki.org (CC-BY-SA 3.0 / GFDL); CMUdict (BSD-2)",
            }
            db.executemany("INSERT INTO meta VALUES (?,?)", meta.items())
            db.commit()
            db.execute("VACUUM")
        finally:
            db.close()
        os.replace(staged_db, WORDS_SQLITE)
    print(dict(stats), "size MB:", round(WORDS_SQLITE.stat().st_size / 1e6, 1))


if __name__ == "__main__":
    main()
