import 'dart:convert';

/// Builds a stable, collision-free identity for one product/unit cart choice.
///
/// Main and sub-unit keys use different prefixes. API-provided IDs are encoded
/// individually, so punctuation inside either ID can never imitate a separator.
String buildCartLineId(String productId, String? sellingUnitId) {
  if (sellingUnitId == null) return 'main:$productId';

  final encodedProduct = base64UrlEncode(utf8.encode(productId));
  final encodedUnit = base64UrlEncode(utf8.encode(sellingUnitId));
  return 'unit:$encodedProduct:$encodedUnit';
}
