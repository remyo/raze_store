import '../../../core/money/money.dart';

const int maximumCartQuantity = 999;

/// Receipt-safe snapshot of one product in the unfinished cart.
///
/// The name and price do not change if the catalog item is later edited or
/// deleted. Re-adding the same product increments this row's quantity.
final class CartItem {
  const CartItem({
    required this.lineId,
    required this.productId,
    required this.sellingUnitId,
    required this.barcode,
    required this.nameSnapshot,
    required this.unitPrice,
    required this.quantity,
    required this.addedAt,
    required this.updatedAt,
    this.brandSnapshot,
    this.unitLabelSnapshot,
    this.imagePathSnapshot,
  });

  final String lineId;
  final String productId;
  final String? sellingUnitId;
  final String? barcode;
  final String nameSnapshot;
  final String? brandSnapshot;
  final String? unitLabelSnapshot;
  final String? imagePathSnapshot;
  final Money unitPrice;
  final int quantity;
  final DateTime addedAt;
  final DateTime updatedAt;

  String get name => nameSnapshot;
  int get unitPriceCentavos => unitPrice.centavos;
  Money get lineTotal => unitPrice.times(quantity);
  int get lineTotalCentavos => lineTotal.centavos;

  bool get usesDefaultSellingUnit => sellingUnitId == null;
}

final class CartDraft {
  CartDraft(Iterable<CartItem> items)
    : items = List<CartItem>.unmodifiable(items);

  final List<CartItem> items;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  int get distinctProductCount =>
      items.map((item) => item.productId).toSet().length;

  int get totalQuantity =>
      items.fold(0, (total, item) => total + item.quantity);

  Money get total => Money.fromCentavos(
    items.fold(0, (total, item) => total + item.lineTotalCentavos),
  );

  int get totalCentavos => total.centavos;
}
