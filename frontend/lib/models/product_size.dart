class ProductSize {
  final int? id;
  final int? sizeId;
  final String? sizeText;
  final double? priceA;
  final double? priceB;
  final double? priceC;
  final double? priceD;
  final double? priceE;
  final double? priceR;
  final bool? isActive;

  ProductSize({
    this.id,
    this.sizeId,
    this.sizeText,
    this.priceA,
    this.priceB,
    this.priceC,
    this.priceD,
    this.priceE,
    this.priceR,
    this.isActive,
  });

  factory ProductSize.fromJson(Map<String, dynamic> json) {
    return ProductSize(
      id: json['id'] as int?,
      sizeId: json['size_id'] as int?,
      sizeText: json['size_text'] as String?,
      priceA: json['price_a'] != null ? (json['price_a'] as num).toDouble() : null,
      priceB: json['price_b'] != null ? (json['price_b'] as num).toDouble() : null,
      priceC: json['price_c'] != null ? (json['price_c'] as num).toDouble() : null,
      priceD: json['price_d'] != null ? (json['price_d'] as num).toDouble() : null,
      priceE: json['price_e'] != null ? (json['price_e'] as num).toDouble() : null,
      priceR: json['price_r'] != null ? (json['price_r'] as num).toDouble() : null,
      isActive: json['is_active'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'size_id': sizeId,
      'size_text': sizeText,
      'price_a': priceA,
      'price_b': priceB,
      'price_c': priceC,
      'price_d': priceD,
      'price_e': priceE,
      'price_r': priceR,
      'is_active': isActive,
    };
  }

  // Get minimum price across all price tiers
  double? get minPrice {
    final prices = [priceA, priceB, priceC, priceD, priceE, priceR]
        .where((p) => p != null)
        .cast<double>()
        .toList();
    return prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b);
  }

  // Get maximum price across all price tiers
  double? get maxPrice {
    final prices = [priceA, priceB, priceC, priceD, priceE, priceR]
        .where((p) => p != null)
        .cast<double>()
        .toList();
    return prices.isEmpty ? null : prices.reduce((a, b) => a > b ? a : b);
  }
}


