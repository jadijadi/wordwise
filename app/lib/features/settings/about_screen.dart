import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/adaptive.dart';
import '../../core/platform.dart';
import '../../core/providers.dart';

final packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(packageInfoProvider).value;
    final dict = ref.watch(dictionaryProvider);

    // showLicensePage builds a Material page; on iOS it needs a Material and a
    // Theme ancestor of its own, so push it inside one.
    void openLicenses() {
      if (!isCupertino) {
        showLicensePage(context: context, applicationName: 'Wordwise', applicationVersion: info?.version);
        return;
      }
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute<void>(
          builder: (_) => Theme(
            data: ThemeData(
              colorSchemeSeed: const Color(0xFF3F6E9A),
              brightness: CupertinoTheme.brightnessOf(context),
              useMaterial3: true,
            ),
            child: LicensePage(applicationName: 'Wordwise', applicationVersion: info?.version),
          ),
        ),
      );
    }

    final body = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Wordwise', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        Text(info == null ? '' : 'Version ${info.version} (${info.buildNumber})'),
        Text('Dictionary built ${dict.built} · ${dict.count} words'),
        const SizedBox(height: 20),
        const Text('Data sources', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Word frequencies: wordfreq by Robyn Speer — data under CC BY-SA 4.0.'),
        const SizedBox(height: 8),
        const Text('Definitions, examples, inflections and most pronunciations: Wiktionary, via the kaikki.org machine-readable extract (Tatu Ylonen) — CC BY-SA 3.0 and GFDL. Text may have been shortened.'),
        const SizedBox(height: 8),
        const Text('Additional pronunciations: The CMU Pronouncing Dictionary — BSD 2-clause.'),
        const SizedBox(height: 8),
        const Text('Pronunciation audio is generated on your device by its text-to-speech engine.'),
        const SizedBox(height: 20),
        const Text('Wordwise is open source under the MIT license. No account, no tracking; your progress stays on this device unless you export it.'),
        const SizedBox(height: 20),
        isCupertino
            ? CupertinoButton.tinted(onPressed: openLicenses, child: const Text('Third-party software licenses'))
            : OutlinedButton(onPressed: openLicenses, child: const Text('Third-party software licenses')),
      ],
    );

    if (isCupertino) {
      return CupertinoPageScaffold(
        backgroundColor: adaptiveBackground(context, grouped: true),
        navigationBar: const CupertinoNavigationBar(middle: Text('About')),
        child: SafeArea(bottom: false, child: body),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: body,
    );
  }
}
