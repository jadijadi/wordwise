import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../core/grade_style.dart';
import '../../core/platform.dart';
import '../../core/providers.dart';
import '../../core/word_providers.dart';
import '../../domain/models.dart';
import '../review/review_controller.dart';

class StatsData {
  const StatsData({
    required this.today,
    required this.retired,
    required this.learning,
    required this.dueNow,
    required this.highestBand,
    required this.retiredPerBand,
    required this.totalWords,
    required this.knownFraction,
    required this.textCoverage,
    required this.skipped,
  });

  final Map<Grade, int> today;
  final int retired;
  final int learning;
  final int dueNow;
  final int highestBand;

  /// index 0 = band 1
  final List<int> retiredPerBand;
  final int totalWords;

  /// retired / total words.
  final double knownFraction;

  /// Frequency-weighted share of running text made of retired words
  /// (relative to the 40K list; knowing the top 5K already covers ~93 %).
  final double textCoverage;

  /// Jumped over by the streak rule, not yet verified.
  final int skipped;
}

final statsProvider = FutureProvider<StatsData>((ref) async {
  ref.watch(progressVersionProvider);
  ref.watch(reviewControllerProvider); // refresh after swipes
  final repo = ref.watch(progressRepositoryProvider);
  final now = DateTime.now();
  final swipes = await repo.swipesSince(DateTime(now.year, now.month, now.day));
  final today = {for (final g in Grade.values) g: swipes.where((e) => e.grade == g.name).length};
  final retiredIds = await repo.retiredIds();
  final total = ref.watch(dictionaryProvider).count;
  final bands = (total + 999) ~/ 1000;
  final perBand = List<int>.filled(bands, 0);
  for (final id in retiredIds) {
    final b = (id - 1) ~/ 1000;
    if (b < bands) perBand[b]++;
  }
  final weights = ref.watch(dictionaryProvider).frequencyWeights();
  final totalWeight = weights.values.fold(0.0, (a, b) => a + b);
  final knownWeight = retiredIds.fold(0.0, (a, id) => a + (weights[id] ?? 0));
  final learningIds = await repo.idsByState(ProgressState.learning, offset: 0, limit: 1 << 20);
  final highest = [...retiredIds, ...learningIds].fold<int>(0, (m, id) => id > m ? id : m);
  return StatsData(
    today: today,
    retired: retiredIds.length,
    learning: learningIds.length,
    dueNow: await repo.dueCount(now),
    highestBand: highest == 0 ? 0 : (highest - 1) ~/ 1000 + 1,
    retiredPerBand: perBand,
    totalWords: total,
    knownFraction: total == 0 ? 0 : retiredIds.length / total,
    textCoverage: totalWeight == 0 ? 0 : knownWeight / totalWeight,
    skipped: await repo.countByState(ProgressState.skipped),
  );
});

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final body = stats.when(
      loading: () => SizedBox(
        height: 240,
        child: Center(child: isCupertino ? const CupertinoActivityIndicator() : const CircularProgressIndicator()),
      ),
      error: (e, _) => SizedBox(height: 240, child: Center(child: Text('$e'))),
      data: (s) => ListView(
        // Inside the Cupertino sliver the parent scrolls, so this must not.
        shrinkWrap: isCupertino,
        physics: isCupertino ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _KnownHero(stats: s),
          const SizedBox(height: 24),
          const _SectionTitle('Today'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final g in [Grade.know, Grade.issues, Grade.unknown])
                Expanded(child: _Tile(label: g.label, value: '${s.today[g]}', color: g.color)),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Totals'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _Tile(label: 'retired', value: '${s.retired}')),
              Expanded(child: _Tile(label: 'learning', value: '${s.learning}')),
              Expanded(child: _Tile(label: 'due now', value: '${s.dueNow}')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Highest band touched: ${s.highestBand} of ${s.retiredPerBand.length}'
            '${s.skipped > 0 ? ' · ${s.skipped} words skipped ahead, to be checked later' : ''}',
            style: TextStyle(fontSize: 14, color: adaptiveSecondaryLabel(context)),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Retired per band'),
          const SizedBox(height: 8),
          _BandGrid(perBand: s.retiredPerBand),
          const SizedBox(height: 8),
          Text(
            '1,000 words each.',
            style: TextStyle(fontSize: 13, color: adaptiveSecondaryLabel(context)),
          ),
        ],
      ),
    );

    if (isCupertino) {
      // The nav bar is a sliver, so the content must be one too — wrapping a
      // ListView in SliverFillRemaining clipped the large title.
      return CupertinoPageScaffold(
        backgroundColor: adaptiveBackground(context, grouped: true),
        child: CustomScrollView(
          slivers: [
            const CupertinoSliverNavigationBar(largeTitle: Text('Progress')),
            SliverSafeArea(top: false, sliver: SliverToBoxAdapter(child: body)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: body,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    if (!isCupertino) return Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600));
    // Matches the grouped-list headers used elsewhere on iOS.
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 13, letterSpacing: -0.08, color: adaptiveSecondaryLabel(context)),
      ),
    );
  }
}

class _BandGrid extends StatelessWidget {
  const _BandGrid({required this.perBand});
  final List<int> perBand;

  @override
  Widget build(BuildContext context) {
    final empty = isCupertino
        ? CupertinoColors.tertiarySystemFill.resolveFrom(context)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return GridView.count(
      crossAxisCount: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (var i = 0; i < perBand.length; i++)
          Semantics(
            label: 'Band ${i + 1}: ${perBand[i]} retired',
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: Color.lerp(empty, GradeColors.know, perBand[i] / 1000),
              ),
              child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
            ),
          ),
      ],
    );
  }
}

/// "You know 12.5 % of the words" plus the share of everyday text that is.
class _KnownHero extends StatelessWidget {
  const _KnownHero({required this.stats});
  final StatsData stats;

  @override
  Widget build(BuildContext context) {
    final pct = stats.knownFraction * 100;
    final pctText = pct >= 10 ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
    final accent = adaptiveAccent(context);
    // On iOS the hero is a tinted rounded panel; on Android it stays a filled
    // primary-container Card.
    final onPanel = isCupertino ? CupertinoColors.label.resolveFrom(context) : Theme.of(context).colorScheme.onPrimaryContainer;
    final panel = isCupertino ? accent.withValues(alpha: 0.12) : Theme.of(context).colorScheme.primaryContainer;

    return Container(
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$pctText %', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: onPanel)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'of ${_thousands(stats.totalWords)} words known\n${_thousands(stats.retired)} retired',
                  style: TextStyle(fontSize: 14, color: onPanel),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Bar(value: stats.knownFraction, fill: isCupertino ? accent : onPanel, track: onPanel.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          Text(
            '≈ ${(stats.textCoverage * 100).toStringAsFixed(0)} % of everyday English text is made of words you know',
            style: TextStyle(fontSize: 12, color: onPanel),
          ),
        ],
      ),
    );
  }

  static String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

/// A plain rounded progress bar; LinearProgressIndicator needs Material.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.fill, required this.track});
  final double value;
  final Color fill;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            Container(color: track),
            FractionallySizedBox(widthFactor: value.clamp(0.0, 1.0), child: Container(color: fill)),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: adaptiveSecondaryLabel(context))),
        ],
      ),
    );

    if (!isCupertino) return Card(margin: const EdgeInsets.all(4), child: content);

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: adaptiveSurface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: adaptiveSeparator(context), width: 0.5),
      ),
      child: content,
    );
  }
}
