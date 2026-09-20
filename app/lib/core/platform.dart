import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// True on iOS; the whole UI forks on this. One source so tests and
/// screenshot tooling can reason about a single switch.
final bool isCupertino = !kIsWeb && Platform.isIOS;
