import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adaptive.dart';
import '../../core/grade_style.dart';
import '../../core/platform.dart';
import '../../domain/models.dart';
import '../../domain/queue_policy.dart';
import 'review_controller.dart';
import 'widgets/swipe_stack.dart';
import 'widgets/word_card.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final SwipeStackKey _stack = SwipeStackKey();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewControllerProvider);
    final ctrl = ref.read(reviewControllerProvider.notifier);

    ref.listen(reviewControllerProvider, (prev, next) {
      final skip = next.value?.lastSkip;
      if (skip != null && skip != prev?.value?.lastSkip) {
        showAdaptiveToast(
          context,
          '10 in a row — skipped ${skip.$1} words ahead to #${skip.$2}. They come back later if needed.',
          duration: const Duration(seconds: 4),
        );
      }
    });

    final canUndo = state.value?.canUndo == true;
    final body = state.when(
      loading: () => Center(
        child: isCupertino ? const CupertinoActivityIndicator() : const CircularProgressIndicator(),
      ),
      error: (e, _) => Center(child: Text('Something went wrong:\n$e', textAlign: TextAlign.center)),
      data: (s) => _Body(state: s, stack: _stack, onContinue: ctrl.continuePastCap, onSwipe: ctrl.swipe),
    );

    if (!isCupertino) {
      return Scaffold(
        backgroundColor: adaptiveBackground(context, grouped: true),
        appBar: AppBar(
          title: const Text('Wordwise'),
          actions: [
            IconButton(tooltip: 'Undo last swipe', onPressed: canUndo ? ctrl.undo : null, icon: const Icon(Icons.undo_rounded)),
            IconButton(tooltip: 'Words', onPressed: () => context.push('/words'), icon: const Icon(Icons.list_alt_rounded)),
            IconButton(tooltip: 'Stats', onPressed: () => context.push('/stats'), icon: const Icon(Icons.insights_rounded)),
            IconButton(tooltip: 'Settings', onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_rounded)),
          ],
        ),
        body: body,
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: adaptiveBackground(context, grouped: true),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Wordwise'),
        // Same four actions, same order, same place — Cupertino paint only.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BarButton(icon: CupertinoIcons.arrow_uturn_left, semantics: 'Undo last swipe', onPressed: canUndo ? ctrl.undo : null),
            _BarButton(icon: CupertinoIcons.list_bullet, semantics: 'Words', onPressed: () => context.push('/words')),
            _BarButton(icon: CupertinoIcons.chart_bar, semantics: 'Stats', onPressed: () => context.push('/stats')),
            _BarButton(icon: CupertinoIcons.gear, semantics: 'Settings', onPressed: () => context.push('/settings')),
          ],
        ),
      ),
      child: SafeArea(bottom: false, child: body),
    );
  }
}

/// A compact icon button for the Cupertino nav bar.
class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.semantics, required this.onPressed});
  final IconData icon;
  final String semantics;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 0),
      onPressed: onPressed,
      child: Semantics(button: true, label: semantics, child: Icon(icon, size: 22)),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.stack, required this.onContinue, required this.onSwipe});
  final ReviewState state;
  final SwipeStackKey stack;
  final Future<void> Function() onContinue;
  final Future<void> Function(Grade grade) onSwipe;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(state: state),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: state.current == null
                ? _Empty(state: state, onContinue: onContinue)
                : SwipeStack(
                    key: stack,
                    itemKey: state.current!.word.id,
                    current: WordCard(
                      key: ValueKey('card-${state.current!.word.id}'),
                      word: state.current!.word,
                      tag: _tag(state.current!),
                      onLongPress: () => context.push('/words/${state.current!.word.id}'),
                    ),
                    next: state.next == null
                        ? null
                        : WordCard(key: ValueKey('card-${state.next!.word.id}'), word: state.next!.word, tag: _tag(state.next!), interactive: false),
                    onSwipe: (grade) async {
                      HapticFeedback.mediumImpact();
                      await onSwipe(grade);
                    },
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                for (final g in [Grade.unknown, Grade.issues, Grade.know]) ...[
                  Expanded(
                    child: _GradeButton(
                      grade: g,
                      enabled: state.current != null,
                      onPressed: () => stack.commit(g),
                    ),
                  ),
                  if (g != Grade.know) const SizedBox(width: 12),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String? _tag(QueueItem item) {
  final p = item.progress;
  if (p == null) return null;
  if (p.isSkipped) return 'skipped earlier';
  return 'review';
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final ReviewState state;

  @override
  Widget build(BuildContext context) {
    final secondary = adaptiveSecondaryLabel(context);
    final numberStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: isCupertino ? CupertinoColors.label.resolveFrom(context) : Theme.of(context).colorScheme.onSurface,
    );
    final labelStyle = TextStyle(fontSize: 11, color: secondary);

    Widget stat(String label, int n, {Color? color}) => Column(
          children: [
            Text('$n', style: color == null ? numberStyle : numberStyle.copyWith(color: color)),
            Text(label, style: labelStyle),
          ],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          stat('today', state.doneToday),
          stat('new today', state.newToday),
          stat('due', state.dueNow),
          Column(
            children: [
              Text(
                '${state.streak.clamp(0, 10)}/10',
                style: state.streak > 0 ? numberStyle.copyWith(color: Grade.know.color) : numberStyle,
              ),
              Text('streak', style: labelStyle),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({required this.grade, required this.enabled, required this.onPressed});
  final Grade grade;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(grade.icon, color: enabled ? grade.color : adaptiveSecondaryLabel(context), size: 22),
        const SizedBox(height: 2),
        Text(
          grade.label,
          style: TextStyle(fontSize: 12, color: enabled ? grade.color : adaptiveSecondaryLabel(context)),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: '${grade.label}: ${grade.hint}',
      child: isCupertino
          ? CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 12),
              borderRadius: BorderRadius.circular(14),
              color: grade.color.withValues(alpha: 0.14),
              disabledColor: CupertinoColors.quaternarySystemFill.resolveFrom(context),
              onPressed: enabled ? onPressed : null,
              child: label,
            )
          : FilledButton.tonal(
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(foregroundColor: grade.color, padding: const EdgeInsets.symmetric(vertical: 12)),
              child: label,
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state, required this.onContinue});
  final ReviewState state;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) {
    final (title, body, action) = state.exhausted
        ? ('All 40,000 words seen', 'Every word is either retired or scheduled. Come back when reviews are due.', null)
        : state.newCapReached
            ? ('Daily goal reached', "You've met today's new-word goal and nothing is due. Keep going anyway?", 'Keep going')
            : ('Nothing to review', 'Come back later for due words.', null);

    final accent = adaptiveAccent(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isCupertino ? CupertinoIcons.sparkles : Icons.celebration_rounded, size: 56, color: accent),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              body,
              style: TextStyle(fontSize: 14, color: adaptiveSecondaryLabel(context)),
              textAlign: TextAlign.center,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 20),
            isCupertino
                ? CupertinoButton.filled(onPressed: onContinue, child: Text(action))
                : FilledButton(onPressed: onContinue, child: Text(action)),
          ],
        ],
      ),
    );
  }
}
