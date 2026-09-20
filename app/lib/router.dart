import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/platform.dart';
import 'core/settings.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/review/review_screen.dart';
import 'features/settings/about_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/stats/stats_screen.dart';
import 'features/words/word_detail_screen.dart';
import 'features/words/words_screen.dart';

/// On iOS this yields a [CupertinoPage], which brings the interactive
/// edge-swipe back gesture and the iOS push transition; Material elsewhere.
Page<void> _page(Widget child) => isCupertino ? CupertinoPage<void>(child: child) : MaterialPage<void>(child: child);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final settings = await ref.read(settingsProvider.future);
      final onOnboarding = state.matchedLocation == '/onboarding';
      if (!settings.onboarded && !onOnboarding) return '/onboarding';
      if (settings.onboarded && onOnboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', pageBuilder: (_, _) => _page(const ReviewScreen())),
      GoRoute(path: '/onboarding', pageBuilder: (_, _) => _page(const OnboardingScreen())),
      GoRoute(
        path: '/words',
        pageBuilder: (_, _) => _page(const WordsScreen()),
        routes: [
          GoRoute(path: ':id', pageBuilder: (_, s) => _page(WordDetailScreen(wordId: int.parse(s.pathParameters['id']!)))),
        ],
      ),
      GoRoute(path: '/stats', pageBuilder: (_, _) => _page(const StatsScreen())),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, _) => _page(const SettingsScreen()),
        routes: [GoRoute(path: 'about', pageBuilder: (_, _) => _page(const AboutScreen()))],
      ),
    ],
  );
});
