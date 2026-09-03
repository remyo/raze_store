import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../receipt/domain/receipt_draft.dart';

/// An immutable snapshot of one product line in a finalized sale.
@immutable
final class CompletedSaleLine {
  const CompletedSaleLine({
    required this.position,
    required this.productId,
    required this.sellingUnitId,
    required this.barcode,
    required this.nameSnapshot,
    required this.brandSnapshot,
    required this.unitLabelSnapshot,
    required this.imagePathSnapshot,
    required this.unitPrice,
    required this.quantity,
  });

  final int position;
  final String? productId;
  final String? sellingUnitId;
  final String? barcode;
  final String nameSnapshot;
  final String? brandSnapshot;
  final String? unitLabelSnapshot;
  final String? imagePathSnapshot;
  final Money unitPrice;
  final int quantity;

  String get name => nameSnapshot;
  int get unitPriceCentavos => unitPrice.centavos;
  Money get lineTotal => unitPrice.times(quantity);
  int get lineTotalCentavos => lineTotal.centavos;
}

/// A finalized, fully local transaction that can recreate its original receipt.
@immutable
final class CompletedSale {
  CompletedSale({
    required this.id,
    required this.completedAt,
    required this.storeNameSnapshot,
    required this.storeAddressSnapshot,
    required this.storeContactSnapshot,
    required this.footerMessageSnapshot,
    required List<CompletedSaleLine> lines,
    required this.cashReceivedCentavos,
  }) : lines = List<CompletedSaleLine>.unmodifiable(lines) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
    if (storeNameSnapshot.trim().isEmpty) {
      throw ArgumentError.value(
        storeNameSnapshot,
        'storeNameSnapshot',
        'Must not be blank.',
      );
    }
    if (this.lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'Must not be empty.');
    }
    if (cashReceivedCentavos != null && cashReceivedCentavos! < 0) {
      throw ArgumentError.value(
        cashReceivedCentavos,
        'cashReceivedCentavos',
        'Must not be negative.',
      );
    }
  }

  final String id;
  final DateTime completedAt;
  final String storeNameSnapshot;
  final String? storeAddressSnapshot;
  final String? storeContactSnapshot;
  final String? footerMessageSnapshot;
  final List<CompletedSaleLine> lines;
  final int? cashReceivedCentavos;

  int get totalQuantity =>
      lines.fold(0, (total, line) => total + line.quantity);

  Money get total => Money.fromCentavos(totalCentavos);

  int get totalCentavos =>
      lines.fold(0, (total, line) => total + line.lineTotalCentavos);

  /// Positive means customer change; negative means an amount remains due.
  int? get changeCentavos {
    final received = cashReceivedCentavos;
    return received == null ? null : received - totalCentavos;
  }

  ReceiptDraft toReceiptDraft() {
    return ReceiptDraft(
      storeName: storeNameSnapshot,
      storeAddress: storeAddressSnapshot,
      storeContact: storeContactSnapshot,
      footerMessage: footerMessageSnapshot,
      createdAt: completedAt,
      cashReceivedCentavos: cashReceivedCentavos,
      lines: [
        for (final line in lines)
          ReceiptLine(
            productName: line.nameSnapshot,
            barcode: line.barcode,
            unitLabel: line.unitLabelSnapshot,
            quantity: line.quantity,
            unitPriceCentavos: line.unitPriceCentavos,
          ),
      ],
    );
  }
}
