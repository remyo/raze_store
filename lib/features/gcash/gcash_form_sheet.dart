import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'gcash_record.dart';
import 'gcash_screen.dart' show GcashFormScreen;

/// Opens the transaction form with the native, scroll-aware iOS sheet motion.
Future<GcashRecord?> showGcashFormSheet(
  BuildContext context, {
  GcashKind kind = GcashKind.cashIn,
  GcashRecord? record,
}) {
  late final _GcashFormSheetRoute route;
  route = _GcashFormSheetRoute(
    scrollableBuilder: (context, controller) => GcashFormScreen(
      kind: record?.kind ?? kind,
      record: record,
      asBottomSheet: true,
      scrollController: controller,
      onBusyChanged: route.setBusy,
    ),
  );
  return Navigator.of(context, rootNavigator: true).push<GcashRecord>(route);
}

class _GcashFormSheetRoute extends CupertinoSheetRoute<GcashRecord> {
  _GcashFormSheetRoute({required super.scrollableBuilder});

  bool _busy = false;

  @override
  bool get enableDrag => !_busy;

  void setBusy(bool busy) {
    if (_busy == busy) return;
    _busy = busy;
    // The header gesture detector captures this flag when transitions build.
    changedInternalState();
  }

  @override
  bool didPop(GcashRecord? result) {
    if (_busy) {
      // Cupertino's drag can finish after work begins, and bypasses PopScope.
      // Restore after its drag-end handler has finished setting the animation.
      scheduleMicrotask(() {
        if (isActive) {
          controller?.animateTo(
            1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      return false;
    }
    return super.didPop(result);
  }
}
