import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adaptive.dart';
import '../../core/grade_style.dart';
import '../../core/platform.dart';
import '../../core/providers.dart';
import '../../core/word_providers.dart';
import '../../domain/models.dart';

enum WordFilter { all, learning, retired, skipped }

const _pageSize = 100;

/// A page of the word list under the active filter, joined with progress.
final wordPageProvider = FutureProvider.family<List<(Word, Progress?)>, (WordFilter, int)>((ref, arg) async {
  ref.watch(progressVersionProvider);
  final (filter, page) = arg;
  final dict = ref.watch(dictionaryProvider);
  final repo = ref.watch(progressRepositoryProvider);
  final List<Word> words;
  switch (filter) {
    case WordFilter.all:
      words = dict.page(offset: page * _pageSize, limit: _pageSize);
    case WordFilter.learning:
      words = dict.byIds(await repo.idsByState(ProgressState.learning, offset: page * _pageSize, limit: _pageSize));
    case WordFilter.retired:
      words = dict.byIds(await repo.idsByState(ProgressState.retired, offset: page * _pageSize, limit: _pageSize));
    case WordFilter.skipped:
      words = dict.byIds(await repo.idsByState(ProgressState.skipped, offset: page * _pageSize, limit: _pageSize));
  }
  final progress = await repo.getMany(words.map((w) => w.id));
  return [for (final w in words) (w, progress[w.id])];
});

final wordCountProvider = FutureProvider.family<int, WordFilter>((ref, filter) async {
  ref.watch(progressVersionProvider);
  return switch (filter) {
    WordFilter.all => ref.watch(dictionaryProvider).count,
    WordFilter.learning => ref.watch(progressRepositoryProvider).countByState(ProgressState.learning),
    WordFilter.retired => ref.watch(progressRepositoryProvider).countByState(ProgressState.retired),
    WordFilter.skipped => ref.watch(progressRepositoryProvider).countByState(ProgressState.skipped),
  };
});

final wordSearchProvider = FutureProvider.family<List<(Word, Progress?)>, String>((ref, q) async {
  ref.watch(progressVersionProvider);
  final words = ref.watch(dictionaryProvider).search(q);
  final progress = await ref.watch(progressRepositoryProvider).getMany(words.map((w) => w.id));
  return [for (final w in words) (w, progress[w.id])];
});

class WordsScreen extends ConsumerStatefulWidget {
  const WordsScreen({super.key});

  @override
  ConsumerState<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends ConsumerState<WordsScreen> {
  WordFilter _filter = WordFilter.all;
  String _query = '';

  void _setQuery(String v) => setState(() => _query = v.trim());

  Widget _count(BuildContext context) => Consumer(builder: (context, ref, _) {
        final n = ref.watch(wordCountProvider(_filter)).value;
        return Text(
          n == null ? '' : '$n words',
          style: TextStyle(fontSize: 13, color: adaptiveSecondaryLabel(context)),
        );
      });

  Widget get _list => _query.isEmpty ? _PagedList(filter: _filter) : _SearchList(query: _query);

  @override
  Widget build(BuildContext context) {
    if (isCupertino) {
      return CupertinoPageScaffold(
        backgroundColor: adaptiveBackground(context, grouped: true),
        navigationBar: const CupertinoNavigationBar(middle: Text('Words')),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: CupertinoSearchTextField(
                  placeholder: 'Search words and forms',
                  onChanged: _setQuery,
                ),
              ),
              if (_query.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<WordFilter>(
                      groupValue: _filter,
                      onValueChanged: (f) => f == null ? null : setState(() => _filter = f),
                      children: {
                        for (final f in WordFilter.values)
                          f: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(f.name)),
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Align(alignment: Alignment.centerRight, child: _count(context)),
                ),
              ],
              Expanded(child: _list),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: const InputDecoration(hintText: 'Search words and forms', border: InputBorder.none),
          textInputAction: TextInputAction.search,
          onChanged: _setQuery,
        ),
      ),
      body: Column(
        children: [
          if (_query.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final f in WordFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(f.name), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                    ),
                  const Spacer(),
                  _count(context),
                ],
              ),
            ),
          Expanded(child: _list),
        ],
      ),
    );
  }
}

class _PagedList extends ConsumerWidget {
  const _PagedList({required this.filter});
  final WordFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(wordCountProvider(filter)).value ?? 0;
    if (count == 0) return const Center(child: Text('Nothing here yet'));
    return ListView.builder(
      itemCount: count,
      itemExtent: 56,
      itemBuilder: (context, i) {
        final page = ref.watch(wordPageProvider((filter, i ~/ _pageSize)));
        final row = page.value?.elementAtOrNull(i % _pageSize);
        if (row == null) return const SizedBox.shrink();
        return WordRow(word: row.$1, progress: row.$2);
      },
    );
  }
}

class _SearchList extends ConsumerWidget {
  const _SearchList({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(wordSearchProvider(query)).value ?? const [];
    if (rows.isEmpty) return const Center(child: Text('No matches'));
    return ListView.builder(
      itemCount: rows.length,
      itemExtent: 56,
      itemBuilder: (context, i) => WordRow(word: rows[i].$1, progress: rows[i].$2),
    );
  }
}

class WordRow extends StatelessWidget {
  const WordRow({super.key, required this.word, required this.progress});
  final Word word;
  final Progress? progress;

  @override
  Widget build(BuildContext context) {
    final subtitle = '#${word.rank} · band ${word.band}${word.isProper ? ' · name' : ''}';
    final ipaStyle = TextStyle(fontSize: 13, color: adaptiveSecondaryLabel(context));

    if (isCupertino) {
      return CupertinoListTile.notched(
        leading: ProgressIcon(progress: progress),
        title: Text(word.lemma),
        subtitle: Text(subtitle),
        additionalInfo: word.ipa == null ? null : Text(word.ipa!, style: ipaStyle),
        trailing: const CupertinoListTileChevron(),
        onTap: () => context.push('/words/${word.id}'),
      );
    }

    return ListTile(
      leading: ProgressIcon(progress: progress),
      title: Text(word.lemma),
      subtitle: Text(subtitle),
      trailing: word.ipa == null ? null : Text(word.ipa!, style: ipaStyle),
      onTap: () => context.push('/words/${word.id}'),
    );
  }
}

class ProgressIcon extends StatelessWidget {
  const ProgressIcon({super.key, required this.progress});
  final Progress? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final (IconData glyph, Color color) = switch (p) {
      null => (isCupertino ? CupertinoIcons.circle : Icons.circle_outlined, adaptiveSeparator(context)),
      _ when p.isRetired => (isCupertino ? CupertinoIcons.check_mark_circled_solid : Icons.check_circle_rounded, GradeColors.know),
      _ when p.isSkipped => (isCupertino ? CupertinoIcons.forward : Icons.fast_forward_rounded, adaptiveSecondaryLabel(context)),
      _ when p.isDue(DateTime.now()) => (isCupertino ? CupertinoIcons.clock_fill : Icons.schedule_rounded, GradeColors.unknown),
      _ => (isCupertino ? CupertinoIcons.time : Icons.timelapse_rounded, adaptiveAccent(context)),
    };
    return Icon(glyph, color: color);
  }
}
