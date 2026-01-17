double _parseDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

class Challan {
  final int? id;
  final String challanNumber;
  final String partyName;
  final String stationName;
  final String? transportName;
  final String? priceCategory;
  final double totalAmount;
  final double totalQuantity;
  final String status;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ChallanItem> items;
  final int? itemCount; // Item count from list endpoint
  final Map<String, dynamic>? metadata; // Metadata including design allocations

  const Challan({
    required this.id,
    required this.challanNumber,
    required this.partyName,
    required this.stationName,
    this.transportName,
    this.priceCategory,
    this.totalAmount = 0,
    this.totalQuantity = 0,
    this.status = 'draft',
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.items = const [],
    this.itemCount,
    this.metadata,
  });

  factory Challan.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>? ?? const [];
    final itemCount = json['item_count'] as int?;
    final metadata = json['metadata'] as Map<String, dynamic>?;
    return Challan(
      id: json['id'] as int?,
      challanNumber:
          json['challan_number'] ?? json['challanNumber'] ?? 'CHL-UNKNOWN',
      partyName: json['party_name'] ?? json['partyName'] ?? 'Unknown Party',
      stationName:
          json['station_name'] ?? json['stationName'] ?? 'Unknown Station',
      transportName: json['transport_name'] ?? json['transportName'],
      priceCategory: json['price_category'] ?? json['priceCategory'],
      totalAmount: _parseDouble(json['total_amount'] ?? json['totalAmount']),
      totalQuantity:
          _parseDouble(json['total_quantity'] ?? json['totalQuantity']),
      status: json['status'] ?? 'draft',
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      items: itemsJson
          .map((item) => ChallanItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      itemCount: itemCount,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'challan_number': challanNumber,
      'party_name': partyName,
      'station_name': stationName,
      'transport_name': transportName,
      'price_category': priceCategory,
      'total_amount': totalAmount,
      'total_quantity': totalQuantity,
      'status': status,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
      'metadata': metadata,
    };
  }

  Challan copyWith({
    int? id,
    String? challanNumber,
    String? partyName,
    String? stationName,
    String? transportName,
    String? priceCategory,
    double? totalAmount,
    double? totalQuantity,
    String? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChallanItem>? items,
    int? itemCount,
    Map<String, dynamic>? metadata,
  }) {
    return Challan(
      id: id ?? this.id,
      challanNumber: challanNumber ?? this.challanNumber,
      partyName: partyName ?? this.partyName,
      stationName: stationName ?? this.stationName,
      transportName: transportName ?? this.transportName,
      priceCategory: priceCategory ?? this.priceCategory,
      totalAmount: totalAmount ?? this.totalAmount,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
      itemCount: itemCount ?? this.itemCount,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ChallanItem {
  final int? id;
  final int? challanId;
  final int? productId;
  final String productName;
  final int? sizeId;
  final String? sizeText;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String? qrCode;

  const ChallanItem({
    this.id,
    this.challanId,
    this.productId,
    required this.productName,
    this.sizeId,
    this.sizeText,
    this.quantity = 0,
    this.unitPrice = 0,
    double? totalPrice,
    this.qrCode,
  }) : totalPrice = totalPrice ?? quantity * unitPrice;

  factory ChallanItem.fromJson(Map<String, dynamic> json) {
    return ChallanItem(
      id: json['id'] as int?,
      challanId: json['challan_id'] as int?,
      productId: json['product_id'] as int?,
      productName: json['product_name'] ?? 'Product',
      sizeId: json['size_id'] as int?,
      sizeText: json['size_text'] as String?,
      quantity: _parseDouble(json['quantity']),
      unitPrice: _parseDouble(json['unit_price']),
      totalPrice: _parseDouble(json['total_price']),
      qrCode: json['qr_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'challan_id': challanId,
      'product_id': productId,
      'product_name': productName,
      'size_id': sizeId,
      'size_text': sizeText,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'qr_code': qrCode,
    };
  }

  Map<String, dynamic> toPayload() {
    return {
      'product_id': productId,
      'product_name': productName,
      'size_id': sizeId,
      'size_text': sizeText,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'qr_code': qrCode,
    };
  }

  ChallanItem copyWith({
    int? id,
    int? challanId,
    int? productId,
    String? productName,
    int? sizeId,
    String? sizeText,
    double? quantity,
    double? unitPrice,
    double? totalPrice,
    String? qrCode,
  }) {
    final newQuantity = quantity ?? this.quantity;
    final newUnitPrice = unitPrice ?? this.unitPrice;
    return ChallanItem(
      id: id ?? this.id,
      challanId: challanId ?? this.challanId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      sizeId: sizeId ?? this.sizeId,
      sizeText: sizeText ?? this.sizeText,
      quantity: newQuantity,
      unitPrice: newUnitPrice,
      totalPrice: totalPrice ?? (newQuantity * newUnitPrice),
      qrCode: qrCode ?? this.qrCode,
    );
  }
}
