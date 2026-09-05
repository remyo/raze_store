import 'dart:async';

import 'package:flutter/material.dart';

enum AppToastType { info, success, error }

final _visibleToasts = Expando<_ToastEntry>('visible app toasts');

/// Shows a compact, pointer-transparent message above the current route.
///
/// The root overlay owns the toast, so a successful save may close its form
/// without also closing the message. A newer message replaces the previous one.
void showToast(
  BuildContext context,
  String message, {
  AppToastType type = AppToastType.info,
  Duration duration = const Duration(seconds: 3),
}) {
  if (!context.mounted || message.trim().isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null || !overlay.mounted) return;

  _visibleToasts[overlay]?.remove();
  final toast = _ToastEntry(
    overlay: overlay,
    theme: Theme.of(context),
    message: message.trim(),
    type: type,
    duration: duration.isNegative ? Duration.zero : duration,
  );
  _visibleToasts[overlay] = toast;
  overlay.insert(toast.entry);
}

class _ToastEntry {
  _ToastEntry({
    required this.overlay,
    required ThemeData theme,
    required String message,
    required AppToastType type,
    required Duration duration,
  }) {
    entry = OverlayEntry(
      // A newly pushed opaque route must not dispose the timer-owning widget.
      maintainState: true,
      builder: (context) => Theme(
        data: theme,
        child: _AppToast(
          message: message,
          type: type,
          duration: duration,
          onDismissed: remove,
        ),
      ),
    );
  }

  final OverlayState overlay;
  late final OverlayEntry entry;
  bool _removed = false;

  void remove() {
    if (_removed) return;
    _removed = true;
    if (identical(_visibleToasts[overlay], this)) {
      _visibleToasts[overlay] = null;
    }
    entry
      ..remove()
      ..dispose();
  }
}

class _AppToast extends StatefulWidget {
  const _AppToast({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final AppToastType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 140),
  );
  late final CurvedAnimation _opacity = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _position = Tween<Offset>(
    begin: const Offset(0, -.18),
    end: Offset.zero,
  ).animate(_opacity);
  Timer? _timer;
  bool _started = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _animation.value = 1;
    if (_started) return;
    _started = true;
    if (!_reduceMotion) _animation.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    if (!_reduceMotion) {
      try {
        await _animation.reverse().orCancel;
      } on TickerCanceled {
        if (mounted && _reduceMotion) widget.onDismissed();
        return;
      }
    }
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _opacity.dispose();
    _animation.dispose();
    // Also releases the entry if the root overlay is removed before expiry.
    widget.onDismissed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final safe = MediaQuery.viewPaddingOf(context);
    final icon = switch (widget.type) {
      AppToastType.info => Icons.info_outline_rounded,
      AppToastType.success => Icons.check_circle_outline_rounded,
      AppToastType.error => Icons.error_outline_rounded,
    };
    final iconColor = switch (widget.type) {
      AppToastType.info => colors.inversePrimary,
      AppToastType.success =>
        theme.brightness == Brightness.dark
            ? const Color(0xFF136B46)
            : const Color(0xFF89E6C0),
      AppToastType.error =>
        theme.brightness == Brightness.dark
            ? const Color(0xFF9F2520)
            : const Color(0xFFFFB4AB),
    };

    return Positioned(
      top: safe.top + 12,
      left: safe.left + 16,
      right: safe.right + 16,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: FadeTransition(
            key: const ValueKey('app-toast-fade'),
            opacity: _opacity,
            child: SlideTransition(
              key: const ValueKey('app-toast-slide'),
              position: _position,
              child: Semantics(
                container: true,
                liveRegion: true,
                label: widget.message,
                child: ExcludeSemantics(
                  child: Material(
                    key: const ValueKey('app-toast'),
                    color: colors.inverseSurface,
                    elevation: 8,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(18),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 20, color: iconColor),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                widget.message,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onInverseSurface,
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
