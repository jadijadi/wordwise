import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/platform.dart';
import 'core/settings.dart';
import 'router.dart';

const _seed = Color(0xFF3F6E9A);

class WordwiseApp extends ConsumerWidget {
  const WordwiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const Settings();
    final router = ref.watch(routerProvider);

    if (!isCupertino) {
      return MaterialApp.router(
        title: 'Wordwise',
        themeMode: settings.themeMode,
        theme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.light, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark, useMaterial3: true),
        routerConfig: router,
      );
    }

    // iOS: CupertinoApp has no themeMode, so resolve the brightness ourselves
    // and let `system` follow the platform.
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = switch (settings.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };
    return CupertinoApp.router(
      title: 'Wordwise',
      theme: CupertinoThemeData(brightness: brightness, primaryColor: _seed),
      routerConfig: router,
      builder: (context, child) {
        // Some descendants (text-field selection handles, showLicensePage) still
        // expect a Material ancestor; this keeps them working without changing
        // the Cupertino look.
        return Material(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
