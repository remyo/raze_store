import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/core/widgets/app_toast.dart';

const _toast = ValueKey('app-toast');

Future<BuildContext> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  EdgeInsets safeArea = const EdgeInsets.only(top: 47, bottom: 34),
  EdgeInsets keyboard = EdgeInsets.zero,
  double textScale = 1,
  bool reduceMotion = false,
  Widget? child,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: safeArea,
          viewPadding: safeArea,
          viewInsets: keyboard,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            pageContext = context;
            return child ?? const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return pageContext;
}

Future<void> _show(
  WidgetTester tester,
  BuildContext context,
  String message, {
  AppToastType type = AppToastType.info,
  Duration duration = const Duration(seconds: 3),
}) async {
  showToast(context, message, type: type, duration: duration);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _removeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('shows a rounded live-region overlay, not a SnackBar', (
    tester,
  ) async {
    final context = await _mount(tester);
    await _show(tester, context, 'Receipt added. Check the details.');

    expect(find.byKey(_toast), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final surface = tester.widget<Material>(find.byKey(_toast));
    expect(surface.borderRadius, BorderRadius.circular(18));
    expect(surface.elevation, 8);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
    expect(
      semantics.any(
        (widget) =>
            widget.properties.liveRegion == true &&
            widget.properties.label == 'Receipt added. Check the details.',
      ),
      isTrue,
    );
    await _removeApp(tester);
  });

  testWidgets('top safe-area positioning stays clear of the keyboard', (
    tester,
  ) async {
    final context = await _mount(
      tester,
      keyboard: const EdgeInsets.only(bottom: 340),
    );
    await _show(tester, context, 'Receipt read');

    final rect = tester.getRect(find.byKey(_toast));
    expect(rect.top, 59);
    expect(rect.left, greaterThanOrEqualTo(16));
    expect(rect.right, lessThanOrEqualTo(374));
    expect(rect.bottom, lessThan(844 - 340));
    await _removeApp(tester);
  });

  testWidgets('long messages wrap on narrow screens with large text', (
    tester,
  ) async {
    final context = await _mount(
      tester,
      size: const Size(280, 640),
      textScale: 2,
      safeArea: const EdgeInsets.only(top: 24),
    );
    const message =
        'Receipt added. Check the name, number, amount, reference, and date '
        'before saving your record.';
    await _show(tester, context, message);

    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byKey(_toast));
    final text = tester.getRect(find.text(message));
    expect(rect.left, 16);
    expect(rect.right, 264);
    expect(rect.bottom, lessThan(640));
    expect(rect.contains(text.topLeft), isTrue);
    expect(rect.contains(text.bottomRight), isTrue);
    expect(tester.widget<Text>(find.text(message)).maxLines, isNull);
    await _removeApp(tester);
  });

  testWidgets('toast does not absorb pointer events', (tester) async {
    var taps = 0;
    final context = await _mount(
      tester,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps++,
        child: const SizedBox.expand(),
      ),
    );
    await _show(tester, context, 'Tap still reaches the page');
    await tester.tapAt(tester.getCenter(find.byKey(_toast)));
    expect(taps, 1);
    await _removeApp(tester);
  });

  testWidgets('success and error messages use their own icon', (tester) async {
    final context = await _mount(tester);
    await _show(tester, context, 'Record saved', type: AppToastType.success);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    await _show(
      tester,
      context,
      'Receipt could not be read',
      type: AppToastType.error,
    );
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
    await _removeApp(tester);
  });

  testWidgets('automatically dismisses after the requested duration', (
    tester,
  ) async {
    final context = await _mount(tester);
    await _show(tester, context, 'Temporary message');
    await tester.pump(const Duration(milliseconds: 2700));
    expect(find.byKey(_toast), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byKey(_toast), findsNothing);
    await _removeApp(tester);
  });

  testWidgets('replacement does not stack or inherit the old expiry timer', (
    tester,
  ) async {
    final context = await _mount(tester);
    await _show(tester, context, 'First');
    await tester.pump(const Duration(seconds: 2));
    await _show(
      tester,
      context,
      'Replacement',
      duration: const Duration(seconds: 5),
    );
    expect(find.byKey(_toast), findsOneWidget);
    expect(find.text('First'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Replacement'), findsOneWidget);
    await _removeApp(tester);
  });

  testWidgets('can replace an entry before its first build', (tester) async {
    final context = await _mount(tester);
    showToast(context, 'First');
    showToast(context, 'Second');
    showToast(context, 'Third');
    await tester.pumpAndSettle();
    expect(find.byKey(_toast), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _removeApp(tester);
  });

  testWidgets('save toast survives the originating route being popped', (
    tester,
  ) async {
    final context = await _mount(tester);
    final navigator = Navigator.of(context);
    late BuildContext formContext;
    navigator.push<void>(
      MaterialPageRoute(
        builder: (context) {
          formContext = context;
          return const Scaffold(body: Text('Form'));
        },
      ),
    );
    await tester.pumpAndSettle();
    showToast(formContext, 'Record saved', type: AppToastType.success);
    navigator.pop();
    await tester.pumpAndSettle();

    expect(formContext.mounted, isFalse);
    expect(find.text('Record saved'), findsOneWidget);
    expect(find.text('Form'), findsNothing);
    await _removeApp(tester);
  });

  testWidgets('uses the root overlay even from a nested navigator', (
    tester,
  ) async {
    late BuildContext nestedContext;
    final context = await _mount(
      tester,
      child: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (context) {
            nestedContext = context;
            return const Scaffold(body: Text('Nested form'));
          },
        ),
      ),
    );
    final rootOverlay = Overlay.of(context, rootOverlay: true);
    final nestedOverlay = Overlay.of(nestedContext);
    expect(nestedOverlay, isNot(same(rootOverlay)));
    await _show(tester, nestedContext, 'Above every sheet');
    final toastContext = tester.element(find.byKey(_toast));
    expect(Overlay.of(toastContext), same(rootOverlay));
    await _removeApp(tester);
  });

  testWidgets(
    'can show above a new opaque record route using history context',
    (tester) async {
      final context = await _mount(tester);
      final navigator = Navigator.of(context);
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Saved record')),
        ),
      );
      // The history page is still mounted below the new route. Its root overlay
      // is also the correct owner of the post-save confirmation.
      showToast(context, 'GCash record saved', type: AppToastType.success);
      await tester.pumpAndSettle();
      expect(find.text('Saved record'), findsOneWidget);
      expect(find.text('GCash record saved'), findsOneWidget);
      final toastRect = tester.getRect(find.byKey(_toast));
      expect(toastRect.top, 59);
      expect(tester.takeException(), isNull);
      await _removeApp(tester);
    },
  );

  testWidgets('replacement during exit keeps the new message alive', (
    tester,
  ) async {
    final context = await _mount(tester);
    await _show(
      tester,
      context,
      'Exiting',
      duration: const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 40));
    await _show(tester, context, 'New message');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('New message'), findsOneWidget);
    expect(find.text('Exiting'), findsNothing);
    expect(find.byKey(_toast), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _removeApp(tester);
  });

  testWidgets('landscape toast stays inside left and right safe areas', (
    tester,
  ) async {
    final context = await _mount(
      tester,
      size: const Size(844, 390),
      safeArea: const EdgeInsets.fromLTRB(44, 0, 44, 21),
    );
    await _show(tester, context, 'Receipt uploaded');
    final rect = tester.getRect(find.byKey(_toast));
    expect(rect.top, 12);
    expect(rect.left, greaterThanOrEqualTo(60));
    expect(rect.right, lessThanOrEqualTo(784));
    await _removeApp(tester);
  });

  testWidgets('reduced motion skips both entry and exit animation', (
    tester,
  ) async {
    final context = await _mount(tester, reduceMotion: true);
    showToast(context, 'Still message', duration: const Duration(seconds: 1));
    await tester.pump();
    final fade = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('app-toast-fade')),
    );
    final slide = tester.widget<SlideTransition>(
      find.byKey(const ValueKey('app-toast-slide')),
    );
    expect(fade.opacity.value, 1);
    expect(slide.position.value, Offset.zero);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(_toast), findsNothing);
    await _removeApp(tester);
  });

  testWidgets('removing the app during entry or exit cancels all work', (
    tester,
  ) async {
    var context = await _mount(tester);
    showToast(context, 'Entering');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await _removeApp(tester);

    context = await _mount(tester);
    await _show(
      tester,
      context,
      'Leaving',
      duration: const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 30));
    await _removeApp(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank messages do not replace an existing toast', (
    tester,
  ) async {
    final context = await _mount(tester);
    await _show(tester, context, 'Keep this');
    showToast(context, '   ');
    await tester.pump();
    expect(find.text('Keep this'), findsOneWidget);
    await _removeApp(tester);
    showToast(context, 'Context is already unmounted');
    expect(tester.takeException(), isNull);
  });
}
