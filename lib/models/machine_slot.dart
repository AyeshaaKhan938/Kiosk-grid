/// Representa un slot físico de la vending machine con su producto e inventario.
class MachineSlot {
  final int lineNumber;
  final int? productId;
  /// ID externo para integración con Reyeah Cloud (machineLineProductId).
  final String? externalId;
  final String productName;
  final String? productImage;
  final String? productDescription;
  final String? productBrand;
  final String? productCategory;
  final String? productSku;
  final double? productWeight;
  final String? productWeightUnit;
  /// URLs adicionales de imágenes/videos del producto (media_expansions).
  final List<String> productMedia;
  final double price;
  final int currentStock;
  final int maxStock;
  final bool isAvailable;
  final bool isFault;

  const MachineSlot({
    required this.lineNumber,
    this.productId,
    this.externalId,
    required this.productName,
    this.productImage,
    this.productDescription,
    this.productBrand,
    this.productCategory,
    this.productSku,
    this.productWeight,
    this.productWeightUnit,
    this.productMedia = const [],
    required this.price,
    required this.currentStock,
    required this.maxStock,
    required this.isAvailable,
    required this.isFault,
  });

  factory MachineSlot.fromJson(Map<String, dynamic> json) {
    final rawMedia = json['product_media'];
    final media = rawMedia is List
        ? rawMedia.map((e) => e.toString()).toList()
        : <String>[];

    final w = json['product_weight'];
    return MachineSlot(
      lineNumber:          (json['line_number'] as num).toInt(),
      productId:           json['product_id'] as int?,
      productName:         json['product_name'] as String? ?? 'Product',
      productImage:        json['product_image'] as String?,
      productDescription:  json['product_description'] as String?,
      productBrand:        json['product_brand'] as String?,
      productCategory:     json['product_category'] as String?,
      productSku:          json['product_sku'] as String?,
      productWeight:       w != null ? (w as num).toDouble() : null,
      productWeightUnit:   json['product_weight_unit'] as String?,
      productMedia:        media,
      price:               (json['price'] as num).toDouble(),
      currentStock:        (json['current_stock'] as num).toInt(),
      maxStock:            (json['max_stock'] as num).toInt(),
      isAvailable:         json['is_available'] as bool? ?? false,
      isFault:             json['is_fault'] as bool? ?? false,
    );
  }

  bool get isOutOfStock => currentStock == 0;

  String get priceFormatted => '\$${price.toStringAsFixed(2)}';

  /// Todas las imágenes del producto: main_image primero, luego media_expansions.
  List<String> get allImages => [
    if (productImage != null && productImage!.isNotEmpty) productImage!,
    ...productMedia,
  ];
}

/// Respuesta completa del endpoint GET /machines/{no}/slots.
class MachineSlotsResponse {
  final String machineNumber;
  final String machineName;
  final List<MachineSlot> slots;

  const MachineSlotsResponse({
    required this.machineNumber,
    required this.machineName,
    required this.slots,
  });

  factory MachineSlotsResponse.fromJson(Map<String, dynamic> json) {
    return MachineSlotsResponse(
      machineNumber: json['machine_number'] as String,
      machineName:   json['machine_name'] as String,
      slots: (json['slots'] as List)
          .map((s) => MachineSlot.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
