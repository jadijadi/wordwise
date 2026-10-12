"""Regression tests for atomic replacement of the built word database."""

from contextlib import closing
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

PIPELINE_DIR = Path(__file__).resolve().parents[1] / "pipeline"
sys.path.insert(0, str(PIPELINE_DIR))

import s04_build_sqlite as builder


def run_builder_and_close_connections():
    original_connect = sqlite3.connect
    connections = []

    def tracked_connect(*args, **kwargs):
        connection = original_connect(*args, **kwargs)
        connections.append(connection)
        return connection

    with patch.object(builder.sqlite3, "connect", side_effect=tracked_connect):
        try:
            builder.main()
        finally:
            for connection in connections:
                connection.close()


class SQLiteBuildTests(unittest.TestCase):
    @staticmethod
    def make_old_database(path: Path) -> bytes:
        with closing(sqlite3.connect(path)) as conn:
            with conn:
                conn.execute("CREATE TABLE sentinel (value TEXT NOT NULL)")
                conn.execute("INSERT INTO sentinel VALUES ('original')")
        return path.read_bytes()

    @staticmethod
    def write_lexicon(path: Path) -> None:
        sample = {
            "lemma": "hello",
            "entries": [{
                "word": "hello", "pos": "intj",
                "senses": [{"gloss": "a greeting", "tags": [], "example": None}],
                "ipa": [], "ipa_flags": None,
            }],
        }
        path.write_text(json.dumps(sample) + "\n", encoding="utf-8")

    @staticmethod
    def write_lemmas(path: Path, *, bad_second_row: bool = False) -> None:
        contents = (
            "rank\tlemma\tlex_key\tzipf\tfreq_per_billion\t"
            "is_proper\tis_abbrev\tforms\ttop_token\n"
            "1\thello\thello\t4.0\t10000\t0\t0\t\thello\n"
        )
        if bad_second_row:
            contents += "2\tmissing\tmissing\t3.0\t1000\t0\t0\t\tmissing\n"
        path.write_text(contents, encoding="utf-8")

    def test_missing_input_preserves_existing_database(self):
        with tempfile.TemporaryDirectory(prefix="wordwise-test-") as directory:
            root = Path(directory)
            database = root / "words.sqlite"
            original = self.make_old_database(database)
            lexicon = root / "lexicon.jsonl"
            lexicon.write_text("", encoding="utf-8")
            missing_lemmas = root / "missing.tsv"
            with (
                patch.object(builder, "WORDS_SQLITE", database),
                patch.object(builder, "LEXICON_JSONL", lexicon),
                patch.object(builder, "LEMMAS_TSV", missing_lemmas),
                patch.object(builder, "load_cmudict", return_value={}),
            ):
                with self.assertRaises(FileNotFoundError):
                    run_builder_and_close_connections()
            self.assertEqual(database.read_bytes(), original)
            self.assertEqual({p.name for p in root.iterdir()},
                             {"words.sqlite", "lexicon.jsonl"},
                             "Failed builds should not leave staged files behind")

    def test_mid_build_error_preserves_existing_database(self):
        with tempfile.TemporaryDirectory(prefix="wordwise-test-") as directory:
            root = Path(directory)
            database = root / "words.sqlite"
            original = self.make_old_database(database)
            lexicon = root / "lexicon.jsonl"
            lemmas = root / "lemmas.tsv"
            self.write_lexicon(lexicon)
            self.write_lemmas(lemmas, bad_second_row=True)
            with (
                patch.object(builder, "WORDS_SQLITE", database),
                patch.object(builder, "LEXICON_JSONL", lexicon),
                patch.object(builder, "LEMMAS_TSV", lemmas),
                patch.object(builder, "load_cmudict", return_value={}),
            ):
                with self.assertRaises(KeyError):
                    run_builder_and_close_connections()
            self.assertEqual(database.read_bytes(), original)
            self.assertEqual({p.name for p in root.iterdir()},
                             {"words.sqlite", "lexicon.jsonl", "lemmas.tsv"})

    def test_successful_build_replaces_database(self):
        with tempfile.TemporaryDirectory(prefix="wordwise-test-") as directory:
            root = Path(directory)
            database = root / "words.sqlite"
            original = self.make_old_database(database)
            lexicon = root / "lexicon.jsonl"
            lemmas = root / "lemmas.tsv"
            self.write_lexicon(lexicon)
            self.write_lemmas(lemmas)
            with (
                patch.object(builder, "WORDS_SQLITE", database),
                patch.object(builder, "LEXICON_JSONL", lexicon),
                patch.object(builder, "LEMMAS_TSV", lemmas),
                patch.object(builder, "load_cmudict", return_value={}),
            ):
                run_builder_and_close_connections()
            self.assertNotEqual(database.read_bytes(), original)
            with closing(sqlite3.connect(database)) as conn:
                self.assertEqual(conn.execute("SELECT lemma FROM word").fetchall(),
                                 [("hello",)])
                self.assertEqual(conn.execute(
                    "SELECT COUNT(*) FROM sqlite_master WHERE name = 'sentinel'"
                ).fetchone()[0], 0)
            self.assertEqual({p.name for p in root.iterdir()},
                             {"words.sqlite", "lexicon.jsonl", "lemmas.tsv"})


if __name__ == "__main__":
    unittest.main()
