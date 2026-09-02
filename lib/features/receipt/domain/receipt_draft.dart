import 'package:flutter/foundation.dart';

/// One product line in a temporary customer receipt.
///
/// Money is stored as integer centavos so totals are exact. This model is
/// intentionally independent from the cart and database models: creating it
/// does not represent a completed sale.
@immutable
final class ReceiptLine {
  ReceiptLine({
    required String productName,
    required this.quantity,
    required this.unitPriceCentavos,
    String? barcode,
  }) : productName = productName.trim(),
       barcode = _trimToNull(barcode) {
    if (this.productName.isEmpty) {
      throw ArgumentError.value(
        productName,
        'productName',
        'A receipt line needs a product name.',
      );
    }
    if (quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Quantity must be greater than zero.',
      );
    }
    if (unitPriceCentavos < 0) {
      throw ArgumentError.value(
        unitPriceCentavos,
        'unitPriceCentavos',
        'A unit price cannot be negative.',
      );
    }
  }

  final String productName;
  final String? barcode;
  final int quantity;
  final int unitPriceCentavos;

  int get lineTotalCentavos => quantity * unitPriceCentavos;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ReceiptLine &&
            productName == other.productName &&
            barcode == other.barcode &&
            quantity == other.quantity &&
            unitPriceCentavos == other.unitPriceCentavos;
  }

  @override
  int get hashCode =>
      Object.hash(productName, barcode, quantity, unitPriceCentavos);
}

/// A snapshot of the current cart suitable for previewing or sharing.
///
/// The list is copied and made unmodifiable. Callers may safely keep editing
/// the cart after constructing a draft without changing the customer copy.
@immutable
final class ReceiptDraft {
  ReceiptDraft({
    required String storeName,
    required List<ReceiptLine> lines,
    required this.createdAt,
    String? storeAddress,
    String? storeContact,
    String? footerMessage,
    this.cashReceivedCentavos,
  }) : storeName = storeName.trim(),
       storeAddress = _trimToNull(storeAddress),
       storeContact = _trimToNull(storeContact),
       footerMessage = _trimToNull(footerMessage),
       lines = List<ReceiptLine>.unmodifiable(lines) {
    if (this.storeName.isEmpty) {
      throw ArgumentError.value(
        storeName,
        'storeName',
        'A receipt needs a store name.',
      );
    }
    if (this.lines.isEmpty) {
      throw ArgumentError.value(
        lines,
        'lines',
        'A receipt needs at least one product.',
      );
    }
    if (cashReceivedCentavos != null && cashReceivedCentavos! < 0) {
      throw ArgumentError.value(
        cashReceivedCentavos,
        'cashReceivedCentavos',
        'Cash received cannot be negative.',
      );
    }
  }

  final String storeName;
  final String? storeAddress;
  final String? storeContact;
  final String? footerMessage;
  final List<ReceiptLine> lines;
  final DateTime createdAt;
  final int? cashReceivedCentavos;

  int get totalQuantity => lines.fold(0, (sum, line) => sum + line.quantity);

  int get totalCentavos =>
      lines.fold(0, (sum, line) => sum + line.lineTotalCentavos);

  /// Positive means change for the customer; negative means an amount is due.
  int? get changeCentavos {
    final cash = cashReceivedCentavos;
    return cash == null ? null : cash - totalCentavos;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ReceiptDraft &&
            storeName == other.storeName &&
            storeAddress == other.storeAddress &&
            storeContact == other.storeContact &&
            footerMessage == other.footerMessage &&
            createdAt == other.createdAt &&
            cashReceivedCentavos == other.cashReceivedCentavos &&
            listEquals(lines, other.lines);
  }

  @override
  int get hashCode => Object.hash(
    storeName,
    storeAddress,
    storeContact,
    footerMessage,
    createdAt,
    cashReceivedCentavos,
    Object.hashAll(lines),
  );
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
