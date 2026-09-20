import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../core/platform.dart';
import '../../core/providers.dart';
import '../../core/word_providers.dart';
import '../../data/progress/progress_repository.dart';
import '../../domain/models.dart';
import '../review/review_controller.dart';
import '../review/widgets/word_card.dart';

final wordHistoryProvider = FutureProvider.family<List<LogEntry>, int>((ref, id) {
  ref.watch(progressVersionProvider);
  return ref.watch(progressRepositoryProvider).history(id);
});

class WordDetailScreen extends ConsumerWidget {
  const WordDetailScreen({super.key, required this.wordId});
  final int wordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final word = ref.watch(dictionaryProvider).byId(wordId);
    if (word == null) {
      const unknown = Center(child: Text('Unknown word'));
      return isCupertino ? const CupertinoPageScaffold(child: unknown) : const Scaffold(body: unknown);
    }
    final progress = ref.watch(wordProgressProvider(wordId)).value;
    final history = ref.watch(wordHistoryProvider(wordId)).value ?? const [];

    Future<void> toggle() async {
      final retired = progress?.isRetired ?? false;
      await ref.read(progressRepositoryProvider).setRetired(word, !retired, DateTime.now());
      ref.read(progressVersionProvider.notifier).bump();
      await ref.read(reviewControllerProvider.notifier).refresh();
    }

    final retired = progress?.isRetired == true;
    final toggleLabel = retired ? 'Un-retire (learn again)' : 'Retire (I know this)';
    final dueLine = progress?.dueAt == null ? null : 'Due ${_fmt(progress!.dueAt!)} · interval ${_dur(progress.interval)}';
    final card = SizedBox(height: 420, child: WordCard(word: word, initiallyFlipped: true));

    if (isCupertino) {
      return CupertinoPageScaffold(
        backgroundColor: adaptiveBackground(context, grouped: true),
        navigationBar: CupertinoNavigationBar(middle: Text(word.lemma)),
        child: SafeArea(
          bottom: false,
          child: ListView(
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 18), child: card),
              CupertinoGroup(children: [
                CupertinoRow(
                  icon: CupertinoIcons.flag,
                  title: _status(progress),
                  subtitle: dueLine,
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(onPressed: toggle, child: Text(toggleLabel)),
                ),
              ),
              if (history.isNotEmpty) ...[
                const CupertinoGroupHeader('History'),
                CupertinoGroup(children: [
                  for (final h in history)
                    CupertinoRow(
                      icon: _cupertinoGradeIcon(h.grade),
                      title: h.grade.replaceAll('_', ' '),
                      trailing: Text(
                        _fmt(h.at),
                        style: TextStyle(fontSize: 15, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                      ),
                    ),
                ]),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(word.lemma)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          card,
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.flag_rounded),
            title: Text(_status(progress)),
            subtitle: dueLine == null ? null : Text(dueLine),
          ),
          FilledButton.tonalIcon(
            onPressed: toggle,
            icon: Icon(retired ? Icons.replay_rounded : Icons.check_rounded),
            label: Text(toggleLabel),
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('History', style: Theme.of(context).textTheme.titleMedium),
            for (final h in history)
              ListTile(
                dense: true,
                leading: Icon(_gradeIcon(h.grade)),
                title: Text(h.grade.replaceAll('_', ' ')),
                trailing: Text(_fmt(h.at), style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }

  String _status(Progress? p) {
    if (p == null) return 'New — not seen yet';
    if (p.isRetired) return 'Retired (${p.retiredBy?.name ?? 'swipe'})';
    if (p.isSkipped) return 'Skipped ahead — comes back once you start missing words';
    return 'Learning · seen ${p.seenCount}× · missed ${p.lapseCount}×';
  }

  static IconData _gradeIcon(String g) => switch (g) {
        'know' => Icons.check_rounded,
        'issues' => Icons.replay_rounded,
        'unknown' => Icons.close_rounded,
        'retire' => Icons.check_circle_outline_rounded,
        'unretire' => Icons.undo_rounded,
        'skip' => Icons.fast_forward_rounded,
        _ => Icons.layers_rounded,
      };

  static IconData _cupertinoGradeIcon(String g) => switch (g) {
        'know' => CupertinoIcons.check_mark,
        'issues' => CupertinoIcons.arrow_counterclockwise,
        'unknown' => CupertinoIcons.xmark,
        'retire' => CupertinoIcons.check_mark_circled,
        'unretire' => CupertinoIcons.arrow_uturn_left,
        'skip' => CupertinoIcons.forward,
        _ => CupertinoIcons.square_stack_3d_up,
      };

  static String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _dur(Duration d) => d.inDays >= 1 ? '${d.inDays} d' : '${d.inMinutes} min';
}
