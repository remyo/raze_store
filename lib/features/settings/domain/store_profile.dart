/// Store identity printed on a screenshot-able/downloadable cart receipt.
final class StoreProfile {
  const StoreProfile({
    required this.storeName,
    this.address = '',
    this.contact = '',
    this.receiptFooter = 'Salamat po!',
  });

  static const defaults = StoreProfile(storeName: 'Raze Store');

  final String storeName;
  final String address;
  final String contact;
  final String receiptFooter;

  StoreProfile copyWith({
    String? storeName,
    String? address,
    String? contact,
    String? receiptFooter,
  }) => StoreProfile(
    storeName: storeName ?? this.storeName,
    address: address ?? this.address,
    contact: contact ?? this.contact,
    receiptFooter: receiptFooter ?? this.receiptFooter,
  );
}
