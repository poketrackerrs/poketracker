import 'package:flutter/material.dart';

/// A tap target that is ALSO focusable and activatable by a game controller or
/// keyboard: it takes touch taps like a normal button, but also joins focus
/// traversal so the D-pad can land on it, draws a focus ring while focused, and
/// fires [onTap] on A / Enter (ActivateIntent). Wrap any custom
/// `GestureDetector`-style tap target with this to make it controller-navigable
/// without changing its look or layout — the ring is an overlay, so it adds no
/// size.
class FocusableTap extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final BorderRadius borderRadius;
  final bool autofocus;
  const FocusableTap({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.autofocus = false,
  });

  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _focused = false;

  void _setFocused(bool v) {
    if (mounted && v != _focused) setState(() => _focused = v);
  }

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.primary;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowFocusHighlight: _setFocused,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // Stack sizes to the child; the ring overlays it, so layout is unchanged.
        child: Stack(
          children: [
            widget.child,
            if (_focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: widget.borderRadius,
                      border: Border.all(color: ring, width: 3),
                      boxShadow: [
                        BoxShadow(
                            color: ring.withValues(alpha: 0.45), blurRadius: 10),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
