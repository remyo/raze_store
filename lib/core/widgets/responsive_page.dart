import 'package:flutter/material.dart';
import 'package:raze_store/app/theme/theme.dart';

/// Centers page content, constrains it on large screens, and supplies adaptive
/// gutters without making feature widgets aware of screen breakpoints.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.contentMaxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: padding ?? AppSpacing.pageInsetsFor(availableWidth),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// A page shell with consistent app-bar sizing, safe areas, and responsive
/// content width. Scrolling remains owned by [body] so lists stay lazy.
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    required this.body,
    this.title,
    this.appBar,
    this.leading,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.bodyPadding,
    this.maxContentWidth = AppBreakpoints.contentMaxWidth,
    this.padBody = true,
    this.useSafeArea = true,
    this.resizeToAvoidBottomInset = true,
    this.extendBody = false,
  });

  final Widget body;
  final String? title;
  final PreferredSizeWidget? appBar;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? bodyPadding;
  final double maxContentWidth;
  final bool padBody;
  final bool useSafeArea;
  final bool resizeToAvoidBottomInset;
  final bool extendBody;

  @override
  Widget build(BuildContext context) {
    Widget content = padBody
        ? ResponsiveContent(
            maxWidth: maxContentWidth,
            padding: bodyPadding,
            child: body,
          )
        : body;

    if (useSafeArea) {
      content = SafeArea(top: appBar == null && title == null, child: content);
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar:
          appBar ??
          (title == null
              ? null
              : AppBar(
                  title: Text(title!),
                  leading: leading,
                  actions: actions,
                )),
      body: AppKeyboardDismissRegion(child: content),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      extendBody: extendBody,
    );
  }
}

/// Dismisses a focused field when the user taps elsewhere on the page.
class AppKeyboardDismissRegion extends StatelessWidget {
  const AppKeyboardDismissRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      child: child,
    );
  }

  static void _handlePointerDown(PointerDownEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;

    final renderObject = focus.context?.findRenderObject();
    if (renderObject is RenderBox && renderObject.attached) {
      final localPosition = renderObject.globalToLocal(event.position);
      if ((Offset.zero & renderObject.size).contains(localPosition)) return;
    }

    focus.unfocus();
  }
}
