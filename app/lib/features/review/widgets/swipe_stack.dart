
import 'package:flutter/material.dart';

import '../../../core/adaptive.dart';
import '../../../core/grade_style.dart';
import '../../../domain/models.dart';

/// Two cards: the current one is draggable in three directions, the next
/// sits underneath at 95 % and grows as the drag progresses (tech §6).
class SwipeStack extends StatefulWidget {
  const SwipeStack({super.key, required this.current, required this.next, required this.onSwipe, required this.itemKey});

  final Widget current;
  final Widget? next;
  final Future<void> Function(Grade grade) onSwipe;

  /// Identity of the current card; a change resets the drag state.
  final Object itemKey;

  @override
  State<SwipeStack> createState() => _SwipeStackState();
}

class _SwipeStackState extends State<SwipeStack> with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Offset>? _fly;
  bool _committed = false; // top card has flown; hide until the next item arrives
  bool _busy = false; // a commit is under way: ignore further input on this card

  @override
  void didUpdateWidget(covariant SwipeStack old) {
    super.didUpdateWidget(old);
    if (old.itemKey != widget.itemKey) {
      _committed = false;
      _busy = false;
      _offset = Offset.zero;
      _fly = null;
      _anim.reset();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// The outcome the drag is heading towards, from its first few pixels.
  Grade? _direction() {
    final dx = _offset.dx, dy = _offset.dy;
    if (_offset.distance < 12) return null;
    if (dy > 0 && dy.abs() > dx.abs()) return Grade.issues;
    if (dy < 0 && dy.abs() > dx.abs()) return null; // upwards means nothing
    return dx > 0 ? Grade.know : Grade.unknown;
  }

  /// 0 → 1 as the drag approaches the commit threshold in its direction.
  double _progress(Size size) {
    final d = _direction();
    if (d == null) return 0;
    return switch (d) {
      Grade.issues => _offset.dy / (size.height * 0.35),
      Grade.know => _offset.dx / (size.width * 0.35),
      Grade.unknown => -_offset.dx / (size.width * 0.35),
    }.clamp(0.0, 1.0);
  }

  Grade? _pending(Size size) => _progress(size) >= 1 ? _direction() : null;

  Grade? _flung(Velocity v) {
    final p = v.pixelsPerSecond;
    if (p.distance < 900) return null;
    if (p.dy > 0 && p.dy.abs() > p.dx.abs()) return Grade.issues;
    if (p.dy < 0 && p.dy.abs() > p.dx.abs()) return null;
    return p.dx > 0 ? Grade.know : Grade.unknown;
  }

  void _onEnd(DragEndDetails d, Size size) {
    final grade = _pending(size) ?? _flung(d.velocity);
    if (grade == null) {
      _springBack();
      return;
    }
    commit(grade, size);
  }

  void _springBack() {
    final from = _offset;
    _fly = Tween(begin: from, end: Offset.zero).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack));
    _anim
      ..reset()
      ..addListener(_tick)
      ..forward().whenComplete(() {
        _anim.removeListener(_tick);
        setState(() => _fly = null);
      });
  }

  void _tick() => setState(() => _offset = _fly!.value);

  /// Fly the card off in the grade's direction, then report it. Also used by
  /// the buttons below the stack.
  Future<void> commit(Grade grade, Size size) async {
    if (_busy) return;
    _busy = true;
    final target = switch (grade) {
      Grade.know => Offset(size.width * 1.5, _offset.dy),
      Grade.unknown => Offset(-size.width * 1.5, _offset.dy),
      Grade.issues => Offset(_offset.dx, size.height * 1.5),
    };
    _fly = Tween(begin: _offset, end: target).animate(CurvedAnimation(parent: _anim, curve: Curves.easeIn));
    _anim
      ..reset()
      ..addListener(_tick);
    await _anim.forward();
    _anim.removeListener(_tick);
    if (!mounted) return;
    setState(() => _committed = true);
    await widget.onSwipe(grade);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final progress = _progress(size);
        final direction = _direction();
        final pending = _pending(size);
        final angle = (_offset.dx / size.width) * 0.25;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (widget.next != null)
              Transform.scale(
                scale: _committed ? 1.0 : 0.95 + 0.05 * progress,
                child: IgnorePointer(child: widget.next),
              ),
            if (!_committed)
              GestureDetector(
                onPanUpdate: _busy ? null : (d) => setState(() => _offset += d.delta),
                onPanEnd: _busy ? null : (d) => _onEnd(d, size),
                child: Transform.translate(
                  offset: _offset,
                  child: Transform.rotate(
                    angle: angle,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        widget.current,
                        // Hint: fades in with the drag, solid past the threshold.
                        if (direction != null)
                          IgnorePointer(
                            child: Opacity(
                              opacity: 0.25 + 0.75 * progress,
                              child: _GradeOverlay(grade: direction, committed: pending != null),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GradeOverlay extends StatelessWidget {
  const _GradeOverlay({required this.grade, required this.committed});
  final Grade grade;

  /// Past the threshold: releasing now commits.
  final bool committed;

  @override
  Widget build(BuildContext context) {
    final color = grade.color;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: committed ? 4 : 2),
        color: color.withValues(alpha: committed ? 0.14 : 0.06),
      ),
      child: Align(
        alignment: switch (grade) {
          Grade.know => Alignment.topLeft,
          Grade.unknown => Alignment.topRight,
          Grade.issues => Alignment.topCenter,
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 16), // below the chip row
          child: Transform.rotate(
            angle: switch (grade) { Grade.know => -0.2, Grade.unknown => 0.2, Grade.issues => 0.0 },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 3),
                borderRadius: BorderRadius.circular(10),
                color: adaptiveSurface(context).withValues(alpha: 0.85),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(grade.icon, color: color, size: 22),
                        const SizedBox(width: 6),
                        Text(
                          grade.label.toUpperCase(),
                          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    committed ? 'release' : grade.hint,
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Exposes [SwipeStackState.commit] to the buttons via a GlobalKey.
typedef SwipeStackKey = GlobalKey<_SwipeStackState>;

extension SwipeStackControl on SwipeStackKey {
  Future<void> commit(Grade grade) async {
    final s = currentState;
    if (s == null) return;
    final size = s.context.size ?? const Size(360, 520);
    await s.commit(grade, size);
  }
}

