import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/adaptive.dart';
import '../../../core/platform.dart';
import '../../../core/providers.dart';
import '../../../core/settings.dart';
import '../../../core/word_providers.dart';
import '../../../domain/models.dart';

/// The flashcard. Front: the word only. Tap flips to the back with IPA,
/// speaker, senses, forms and rank. The back scrolls; the front never does.
class WordCard extends ConsumerStatefulWidget {
  const WordCard({super.key, required this.word, this.interactive = true, this.initiallyFlipped = false, this.onLongPress, this.tag});

  final Word word;

  /// Small label on the front, e.g. "review" or "skipped earlier".
  final String? tag;
  final bool interactive;
  final bool initiallyFlipped;
  final VoidCallback? onLongPress;

  @override
  ConsumerState<WordCard> createState() => _WordCardState();
}

class _WordCardState extends ConsumerState<WordCard> with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.initiallyFlipped ? 1 : 0,
  );

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!widget.interactive) return;
    if (_flip.isAnimating) return;
    HapticFeedback.selectionClick();
    _flip.value < 0.5 ? _flip.forward() : _flip.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final t = reduceMotion ? (_flip.value < 0.5 ? 0.0 : 1.0) : _flip.value;
          final angle = t * math.pi;
          final showBack = t > 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            child: showBack
                ? Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateY(math.pi), child: _Back(word: widget.word))
                : _Front(word: widget.word, tag: widget.tag),
          );
        },
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child, required this.semantics});
  final Widget child;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    // A plain decorated box rather than Material(), so the card renders the
    // same under CupertinoApp, where there is no Material ancestor to inherit.
    return Semantics(
      label: semantics,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: adaptiveSurface(context),
          borderRadius: BorderRadius.circular(24),
          border: isCupertino ? Border.all(color: adaptiveSeparator(context), width: 0.5) : null,
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: child,
      ),
    );
  }
}

class _Front extends StatelessWidget {
  const _Front({required this.word, this.tag});
  final Word word;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return _Shell(
      semantics: 'Word ${word.lemma}. Tap to reveal meaning.',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                _Chip(text: 'Band ${word.band}'),
                const SizedBox(width: 8),
                if (word.isProper) const _Chip(text: 'name'),
                if (word.isAbbrev) const _Chip(text: 'abbreviation'),
                const Spacer(),
                if (tag != null) _Chip(text: tag!),
              ],
            ),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    word.lemma,
                    style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            Text('tap to reveal', style: TextStyle(fontSize: 12, color: adaptiveSecondaryLabel(context))),
          ],
        ),
      ),
    );
  }
}

class _Back extends ConsumerWidget {
  const _Back({required this.word});
  final Word word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(wordDetailProvider(word.id));
    final showIpa = ref.watch(settingsProvider).value?.showIpa ?? true;
    final tts = ref.watch(ttsProvider);
    final secondary = adaptiveSecondaryLabel(context);
    final footnote = TextStyle(fontSize: 12, color: secondary);
    return _Shell(
      semantics: 'Meaning of ${word.lemma}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(word.lemma, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600))),
                _SpeakerButton(onPressed: () => tts.speak(word.lemma)),
              ],
            ),
            if (showIpa && word.ipa != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tts.speak(word.lemma),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(word.ipa!, style: TextStyle(fontSize: 16, color: adaptiveAccent(context))),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(height: 0.5, color: adaptiveSeparator(context)),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final s in detail.senses) _SenseTile(sense: s),
                  if (detail.forms.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Forms: ${detail.forms.join(', ')}', style: footnote),
                  ],
                ],
              ),
            ),
            Row(
              children: [
                Text('#${word.rank}', style: footnote),
                const Spacer(),
                Text(word.pos.join(' · '), style: footnote),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeakerButton extends StatelessWidget {
  const _SpeakerButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!isCupertino) {
      return IconButton.filledTonal(
        tooltip: 'Pronounce',
        onPressed: onPressed,
        icon: const Icon(Icons.volume_up_rounded),
      );
    }
    return Semantics(
      button: true,
      label: 'Pronounce',
      child: CupertinoButton(
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(0, 0),
        borderRadius: BorderRadius.circular(20),
        color: adaptiveChipBackground(context),
        onPressed: onPressed,
        child: Icon(CupertinoIcons.speaker_2_fill, size: 20, color: adaptiveAccent(context)),
      ),
    );
  }
}

class _SenseTile extends StatelessWidget {
  const _SenseTile({required this.sense});
  final Sense sense;

  @override
  Widget build(BuildContext context) {
    final body = DefaultTextStyle.of(context).style.copyWith(fontSize: 16);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${posLabel(sense.pos)} ',
                  style: TextStyle(color: adaptiveAccent(context), fontStyle: FontStyle.italic),
                ),
                TextSpan(text: sense.gloss),
              ],
            ),
            style: body,
          ),
          if (sense.example != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '“${sense.example}”',
                style: body.copyWith(fontSize: 14, fontStyle: FontStyle.italic, color: adaptiveSecondaryLabel(context)),
              ),
            ),
        ],
      ),
    );
  }
}

String posLabel(String pos) => switch (pos) {
      'noun' => 'n.',
      'verb' => 'v.',
      'adj' => 'adj.',
      'adv' => 'adv.',
      'name' => 'name',
      'pron' => 'pron.',
      'prep' => 'prep.',
      'conj' => 'conj.',
      'det' => 'det.',
      'num' => 'num.',
      'intj' => 'interj.',
      _ => pos,
    };

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: adaptiveChipBackground(context), borderRadius: BorderRadius.circular(12)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: isCupertino ? CupertinoColors.label.resolveFrom(context) : Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
