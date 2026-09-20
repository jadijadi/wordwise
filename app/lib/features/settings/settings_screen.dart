import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/adaptive.dart';
import '../../core/platform.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/word_providers.dart';
import '../../data/progress/progress_repository.dart';
import '../review/review_controller.dart';

final lastBulkRetireProvider = FutureProvider<LogEntry?>((ref) {
  ref.watch(progressVersionProvider);
  return ref.watch(progressRepositoryProvider).lastBulkRetire();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const Settings();
    final notifier = ref.read(settingsProvider.notifier);
    final bulk = ref.watch(lastBulkRetireProvider).value;

    void toast(String msg) => showAdaptiveToast(context, msg);

    Future<void> afterWrite() async {
      ref.read(progressVersionProvider.notifier).bump();
      await ref.read(reviewControllerProvider.notifier).refresh();
    }

    Future<void> export() async {
      final data = await ref.read(progressRepositoryProvider).export();
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'wordwise-progress-${DateTime.now().toIso8601String().substring(0, 10)}.json'));
      await file.writeAsString(const JsonEncoder.withIndent(' ').convert(data));
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')], subject: 'Wordwise progress'));
    }

    Future<void> import() async {
      final picked = await FilePicker.pickFiles(type: FileType.any);
      final path = picked.isEmpty ? null : picked.single.path;
      if (path == null) return;
      try {
        final data = jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
        final dict = ref.read(dictionaryProvider);
        final n = await ref.read(progressRepositoryProvider).import(data, (lemma) => dict.byLemma(lemma)?.id);
        ref.invalidate(settingsProvider);
        await afterWrite();
        toast('Imported $n words');
      } catch (e) {
        toast('Could not import: $e');
      }
    }

    Future<void> undoCalibration() async {
      if (bulk == null) return;
      final n = await ref.read(progressRepositoryProvider).undoBulkRetire(bulk);
      await afterWrite();
      toast('Un-retired $n words');
    }

    final undoSubtitle = bulk == null ? null : 'Un-retire the ${(bulk.after['word_ids'] as List).length} words retired at first launch';

    if (isCupertino) {
      return _CupertinoSettings(
        settings: settings,
        notifier: notifier,
        onSpeakSample: () => ref.read(ttsProvider).speak('ubiquitous'),
        onExport: export,
        onImport: import,
        onUndoCalibration: bulk == null ? null : undoCalibration,
        undoSubtitle: undoSubtitle,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('New words per day'),
            subtitle: Slider(
              value: settings.newPerDay.toDouble(),
              min: 10,
              max: 200,
              divisions: 19,
              label: '${settings.newPerDay}',
              onChanged: (v) => notifier.setNewPerDay(v.round()),
            ),
            trailing: Text('${settings.newPerDay}'),
          ),
          SwitchListTile(title: const Text('Show IPA transcription'), value: settings.showIpa, onChanged: notifier.setShowIpa),
          SwitchListTile(
            title: const Text('Skip ahead on streaks'),
            subtitle: const Text('10 known in a row jumps over the next 100+ words; they return once you start missing words'),
            value: settings.skipAhead,
            onChanged: notifier.setSkipAhead,
          ),
          ListTile(
            title: const Text('Speech rate'),
            subtitle: Slider(value: settings.ttsRate, min: 0.25, max: 0.7, onChanged: notifier.setTtsRate),
            trailing: IconButton(onPressed: () => ref.read(ttsProvider).speak('ubiquitous'), icon: const Icon(Icons.volume_up_rounded)),
          ),
          ListTile(
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              onChanged: (m) => m == null ? null : notifier.setThemeMode(m),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
            ),
          ),
          const Divider(),
          ListTile(leading: const Icon(Icons.upload_rounded), title: const Text('Export progress'), subtitle: const Text('JSON file via the share sheet'), onTap: export),
          ListTile(leading: const Icon(Icons.download_rounded), title: const Text('Import progress'), subtitle: const Text('Merges by word; newest wins'), onTap: import),
          if (bulk != null)
            ListTile(
              leading: const Icon(Icons.undo_rounded),
              title: const Text('Undo calibration'),
              subtitle: Text(undoSubtitle!),
              onTap: undoCalibration,
            ),
          const Divider(),
          ListTile(leading: const Icon(Icons.info_outline_rounded), title: const Text('About & licenses'), onTap: () => context.push('/settings/about')),
        ],
      ),
    );
  }
}

/// iOS settings: inset-grouped sections, the native switch, sliders and a
/// segmented control for the theme.
class _CupertinoSettings extends StatelessWidget {
  const _CupertinoSettings({
    required this.settings,
    required this.notifier,
    required this.onSpeakSample,
    required this.onExport,
    required this.onImport,
    required this.onUndoCalibration,
    required this.undoSubtitle,
  });

  final Settings settings;
  final SettingsNotifier notifier;
  final VoidCallback onSpeakSample;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final Future<void> Function()? onUndoCalibration;
  final String? undoSubtitle;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: adaptiveBackground(context, grouped: true),
      navigationBar: const CupertinoNavigationBar(middle: Text('Settings')),
      child: SafeArea(
        bottom: false,
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              header: const Text('Reviewing'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('New words per day'),
                  additionalInfo: Text('${settings.newPerDay}'),
                  subtitle: CupertinoSlider(
                    value: settings.newPerDay.toDouble(),
                    min: 10,
                    max: 200,
                    divisions: 19,
                    onChanged: (v) => notifier.setNewPerDay(v.round()),
                  ),
                ),
                CupertinoListTile.notched(
                  title: const Text('Show IPA transcription'),
                  trailing: CupertinoSwitch(value: settings.showIpa, onChanged: notifier.setShowIpa),
                ),
                CupertinoListTile.notched(
                  title: const Text('Skip ahead on streaks'),
                  subtitle: const Text('10 known in a row jumps over the next 100+ words; they return once you start missing words'),
                  trailing: CupertinoSwitch(value: settings.skipAhead, onChanged: notifier.setSkipAhead),
                ),
                CupertinoListTile.notched(
                  title: const Text('Speech rate'),
                  subtitle: CupertinoSlider(value: settings.ttsRate, min: 0.25, max: 0.7, onChanged: notifier.setTtsRate),
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    onPressed: onSpeakSample,
                    child: const Icon(CupertinoIcons.speaker_2_fill, size: 22),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('Appearance'),
              children: [
                CupertinoListTile.notched(
                  title: const Text('Theme'),
                  trailing: CupertinoSlidingSegmentedControl<ThemeMode>(
                    groupValue: settings.themeMode,
                    onValueChanged: (m) => m == null ? null : notifier.setThemeMode(m),
                    children: const {
                      ThemeMode.system: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('Auto')),
                      ThemeMode.light: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('Light')),
                      ThemeMode.dark: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('Dark')),
                    },
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('Progress'),
              children: [
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.square_arrow_up),
                  title: const Text('Export progress'),
                  subtitle: const Text('JSON file via the share sheet'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: onExport,
                ),
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.square_arrow_down),
                  title: const Text('Import progress'),
                  subtitle: const Text('Merges by word; newest wins'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: onImport,
                ),
                if (onUndoCalibration != null)
                  CupertinoListTile.notched(
                    leading: const Icon(CupertinoIcons.arrow_uturn_left),
                    title: const Text('Undo calibration'),
                    subtitle: Text(undoSubtitle!),
                    onTap: onUndoCalibration,
                  ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.info_circle),
                  title: const Text('About & licenses'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => context.push('/settings/about'),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
