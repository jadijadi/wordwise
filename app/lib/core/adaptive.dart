import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'platform.dart';

/// Shared surface between the Cupertino and Material trees: colours, chrome and
/// transient messages, so each screen's two implementations agree on the parts
/// that are not really platform-specific.

/// Page background. Cupertino settings-style screens sit on the grouped
/// background; the review screen asks for [grouped] = false.
Color adaptiveBackground(BuildContext context, {bool grouped = false}) {
  if (isCupertino) {
    return CupertinoDynamicColor.resolve(
      grouped ? CupertinoColors.systemGroupedBackground : CupertinoColors.systemBackground,
      context,
    );
  }
  final scheme = Theme.of(context).colorScheme;
  return grouped ? scheme.surfaceContainerLowest : scheme.surface;
}

/// The colour of a raised card / row sitting on [adaptiveBackground].
Color adaptiveSurface(BuildContext context) => isCupertino
    ? CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context)
    : Theme.of(context).colorScheme.surface;

/// Secondary label colour for captions, hints and footnotes.
Color adaptiveSecondaryLabel(BuildContext context) => isCupertino
    ? CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context)
    : Theme.of(context).colorScheme.outline;

/// Hairline / separator colour.
Color adaptiveSeparator(BuildContext context) => isCupertino
    ? CupertinoDynamicColor.resolve(CupertinoColors.separator, context)
    : Theme.of(context).colorScheme.outlineVariant;

/// The app's accent colour on either platform.
Color adaptiveAccent(BuildContext context) =>
    isCupertino ? CupertinoTheme.of(context).primaryColor : Theme.of(context).colorScheme.primary;

/// The tinted pill background used by the chips on the word card.
Color adaptiveChipBackground(BuildContext context) => isCupertino
    ? CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemFill, context)
    : Theme.of(context).colorScheme.secondaryContainer;

/// A primary call-to-action button.
Widget adaptiveFilledButton({required VoidCallback? onPressed, required Widget child}) => isCupertino
    ? CupertinoButton.filled(onPressed: onPressed, child: child)
    : FilledButton(onPressed: onPressed, child: child);

/// A secondary, outlined/tinted button.
Widget adaptiveSecondaryButton({required VoidCallback? onPressed, required Widget child}) => isCupertino
    ? CupertinoButton.tinted(onPressed: onPressed, child: child)
    : OutlinedButton(onPressed: onPressed, child: child);

/// A low-emphasis text button.
Widget adaptiveTextButton({required VoidCallback? onPressed, required Widget child}) => isCupertino
    ? CupertinoButton(padding: EdgeInsets.zero, onPressed: onPressed, child: child)
    : TextButton(onPressed: onPressed, child: child);

/// A determinate progress bar. [LinearProgressIndicator] requires Material.
class AdaptiveProgressBar extends StatelessWidget {
  const AdaptiveProgressBar({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    if (!isCupertino) return LinearProgressIndicator(value: value);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Container(color: CupertinoColors.tertiarySystemFill.resolveFrom(context)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(color: adaptiveAccent(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A transient message. [ScaffoldMessenger] does not exist under a
/// [CupertinoPageScaffold], so iOS gets an overlay banner instead of a SnackBar.
void showAdaptiveToast(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
  if (!isCupertino) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 96), // above the grade buttons
      ));
    return;
  }
  _CupertinoToast.show(context, message, duration);
}

/// An iOS-flavoured transient banner: a blurred rounded capsule that slides up
/// from the bottom, above the grade buttons, and fades itself out.
class _CupertinoToast extends StatefulWidget {
  const _CupertinoToast({required this.message, required this.duration, required this.onDone});

  final String message;
  final Duration duration;
  final VoidCallback onDone;

  static OverlayEntry? _current;

  static void show(BuildContext context, String message, Duration duration) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _current?.remove();
    _current = null;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CupertinoToast(
        message: message,
        duration: duration,
        onDone: () {
          if (_current == entry) _current = null;
          entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  @override
  State<_CupertinoToast> createState() => _CupertinoToastState();
}

class _CupertinoToastState extends State<_CupertinoToast> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _anim.forward();
    Future<void>.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    await _anim.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      left: 20,
      right: 20,
      bottom: media.padding.bottom + 96, // clear of the grade buttons
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.4), end: Offset.zero)
                .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic)),
            child: _capsule(context),
          ),
        ),
      ),
    );
  }

  Widget _capsule(BuildContext context) {
    final fill = CupertinoDynamicColor.resolve(CupertinoColors.systemGrey6, context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: fill.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: adaptiveSeparator(context), width: 0.5),
            boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Text(
            widget.message,
            textAlign: TextAlign.center,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(fontSize: 14),
          ),
        ),
      ),
    );
  }
}
