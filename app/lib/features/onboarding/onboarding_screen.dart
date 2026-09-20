import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adaptive.dart';
import '../../core/grade_style.dart';
import '../../core/platform.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/word_providers.dart';
import '../../domain/models.dart';
import '../review/review_controller.dart';
import '../review/widgets/swipe_stack.dart';
import '../review/widgets/word_card.dart';

const _bands = 5;
const _perBand = 8;

/// First launch: explain the three swipes, then calibrate (MVP §2.3).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0; // 0 intro, 1 calibrate, 2 summary
  late final List<Word> _samples;
  int _index = 0;
  final Map<int, int> _knownPerBand = {};
  final SwipeStackKey _stack = SwipeStackKey();

  @override
  void initState() {
    super.initState();
    final dict = ref.read(dictionaryProvider);
    _samples = [for (var b = 1; b <= _bands; b++) ...dict.sampleBand(b, _perBand)];
  }

  /// Highest band such that every band up to it was fully known.
  int get _fullyKnownUpTo {
    var upTo = 0;
    for (var b = 1; b <= _bands; b++) {
      if ((_knownPerBand[b] ?? 0) == _perBand) {
        upTo = b;
      } else {
        break;
      }
    }
    return upTo;
  }

  Future<void> _grade(Grade g) async {
    HapticFeedback.mediumImpact();
    final w = _samples[_index];
    if (g == Grade.know) _knownPerBand[w.band] = (_knownPerBand[w.band] ?? 0) + 1;
    setState(() {
      _index++;
      if (_index >= _samples.length) _step = 2;
    });
  }

  Future<void> _finish({required bool bulk}) async {
    if (bulk && _fullyKnownUpTo > 0) {
      final dict = ref.read(dictionaryProvider);
      final words = dict.page(offset: 0, limit: _fullyKnownUpTo * 1000);
      await ref.read(progressRepositoryProvider).bulkRetire(words, DateTime.now());
      ref.read(progressVersionProvider.notifier).bump();
    }
    await ref.read(settingsProvider.notifier).setOnboarded();
    await ref.read(reviewControllerProvider.notifier).refresh();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: switch (_step) {
        0 => _Intro(onNext: () => setState(() => _step = 1), onSkip: () => _finish(bulk: false)),
        1 => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text('Quick check', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${_index + 1} of ${_samples.length} · be honest, this only sets your starting point',
                          style: TextStyle(fontSize: 12, color: adaptiveSecondaryLabel(context)), textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      AdaptiveProgressBar(value: _index / _samples.length),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SwipeStack(
                      key: _stack,
                      itemKey: _samples[_index].id,
                      current: WordCard(key: ValueKey(_samples[_index].id), word: _samples[_index]),
                      next: _index + 1 < _samples.length ? WordCard(key: ValueKey(_samples[_index + 1].id), word: _samples[_index + 1], interactive: false) : null,
                      onSwipe: _grade,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      for (final g in [Grade.unknown, Grade.issues, Grade.know]) ...[
                        Expanded(
                          child: isCupertino
                              ? CupertinoButton(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  borderRadius: BorderRadius.circular(14),
                                  color: g.color.withValues(alpha: 0.14),
                                  onPressed: () => _stack.commit(g),
                                  child: Text(g.label, style: TextStyle(color: g.color, fontSize: 15)),
                                )
                              : FilledButton.tonal(
                                  onPressed: () => _stack.commit(g),
                                  style: FilledButton.styleFrom(foregroundColor: g.color),
                                  child: Text(g.label),
                                ),
                        ),
                        if (g != Grade.know) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
        _ => _Summary(upTo: _fullyKnownUpTo, onFinish: _finish),
      },
    );

    return isCupertino
        ? CupertinoPageScaffold(backgroundColor: adaptiveBackground(context), child: body)
        : Scaffold(body: body);
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onNext, required this.onSkip});
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final secondary = adaptiveSecondaryLabel(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          const Text('Wordwise', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'The 40,000 words a fluent reader knows — meaning and pronunciation — one card at a time, most common first.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 28),
          for (final g in [Grade.know, Grade.issues, Grade.unknown])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: g.color.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(g.icon, color: g.color, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_dir(g)} — ${g.label}', style: const TextStyle(fontSize: 16)),
                        Text(g.hint, style: TextStyle(fontSize: 13, color: secondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Tap a card to see its meaning and hear it. You grade yourself; nobody is checking.',
            style: TextStyle(fontSize: 14, color: secondary),
          ),
          const Spacer(),
          Row(
            children: [
              adaptiveTextButton(onPressed: onSkip, child: const Text('Skip check')),
              const Spacer(),
              adaptiveFilledButton(onPressed: onNext, child: const Text('Start quick check')),
            ],
          ),
        ],
      ),
    );
  }

  static String _dir(Grade g) => switch (g) { Grade.know => 'Swipe right', Grade.issues => 'Swipe down', Grade.unknown => 'Swipe left' };
}

class _Summary extends StatelessWidget {
  const _Summary({required this.upTo, required this.onFinish});
  final int upTo;
  final Future<void> Function({required bool bulk}) onFinish;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(isCupertino ? CupertinoIcons.sparkles : Icons.auto_awesome_rounded, size: 56, color: adaptiveAccent(context)),
          const SizedBox(height: 16),
          Text(
            upTo == 0 ? 'Starting from the top' : 'You knew all of bands 1–$upTo',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            upTo == 0
                ? 'You will start at word #1. Swiping "Easy" is fast — the first few hundred will fly by.'
                : 'Retire words 1–${upTo * 1000} now and start at #${upTo * 1000 + 1}? You can undo this in Settings, and any word can be un-retired from the list.',
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          if (upTo > 0) ...[
            adaptiveFilledButton(onPressed: () => onFinish(bulk: true), child: Text('Retire words 1–${upTo * 1000}')),
            const SizedBox(height: 8),
            adaptiveSecondaryButton(onPressed: () => onFinish(bulk: false), child: const Text('No, start from #1')),
          ] else
            adaptiveFilledButton(onPressed: () => onFinish(bulk: false), child: const Text('Start')),
        ],
      ),
    );
  }
}
