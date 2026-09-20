import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'platform.dart';

/// The three outcome colours, also used for progress state elsewhere
/// (word list icons, stats heatmap) so there is one source for each.
abstract final class GradeColors {
  static const know = Color(0xFF2E9E5B);
  static const issues = Color(0xFFE0A100);
  static const unknown = Color(0xFFD64545);
}

/// One place for the colour, icon and wording of each swipe outcome.
extension GradeStyle on Grade {
  Color get color => switch (this) {
        Grade.know => GradeColors.know,
        Grade.issues => GradeColors.issues,
        Grade.unknown => GradeColors.unknown,
      };

  /// The platform's glyph for this outcome.
  IconData get icon => isCupertino ? cupertinoIcon : materialIcon;

  IconData get materialIcon => switch (this) {
        Grade.know => Icons.check_rounded,
        Grade.issues => Icons.replay_rounded,
        Grade.unknown => Icons.close_rounded,
      };

  IconData get cupertinoIcon => switch (this) {
        Grade.know => CupertinoIcons.check_mark,
        Grade.issues => CupertinoIcons.arrow_counterclockwise,
        Grade.unknown => CupertinoIcons.xmark,
      };

  String get label => switch (this) {
        Grade.know => 'Easy',
        Grade.issues => 'Shaky',
        Grade.unknown => 'No idea',
      };

  String get hint => switch (this) {
        Grade.know => 'Never show again',
        Grade.issues => 'Show again later',
        Grade.unknown => 'Show again soon',
      };
}
