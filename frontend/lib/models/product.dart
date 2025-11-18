import 'product_size.dart';

class Product {
  final int? id;
  final int? externalId;
  final String? name;
  final int? categoryId;
  final String? categoryName;
  final String? imageUrl;
  final String? videoUrl;
  final String? qrCode;
  final bool? isActive;
  final List<ProductSize>? sizes;

  Product({
    this.id,
    this.externalId,
    this.name,
    this.categoryId,
    this.categoryName,
    this.imageUrl,
    this.videoUrl,
    this.qrCode,
    this.isActive,
    this.sizes,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int?,
      externalId: json['external_id'] as int?,
      name: json['name'] as String?,
      categoryId: json['category_id'] as int?,
      categoryName: json['category_name'] as String?,
      imageUrl: json['image_url'] as String?,
      videoUrl: json['video_url'] as String?,
      qrCode: json['qr_code'] as String?,
      isActive: json['is_active'] as bool?,
      sizes: json['sizes'] != null
          ? (json['sizes'] as List)
              .map((size) => ProductSize.fromJson(size as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'external_id': externalId,
      'name': name,
      'category_id': categoryId,
      'category_name': categoryName,
      'image_url': imageUrl,
      'video_url': videoUrl,
      'qr_code': qrCode,
      'is_active': isActive,
      'sizes': sizes?.map((size) => size.toJson()).toList(),
    };
  }

  // Get minimum price across all sizes
  double? get minPrice {
    if (sizes == null || sizes!.isEmpty) return null;
    final prices = sizes!
        .map((s) => s.minPrice)
        .where((p) => p != null)
        .cast<double>()
        .toList();
    return prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b);
  }

  // Get maximum price across all sizes
  double? get maxPrice {
    if (sizes == null || sizes!.isEmpty) return null;
    final prices = sizes!
        .map((s) => s.maxPrice)
        .where((p) => p != null)
        .cast<double>()
        .toList();
    return prices.isEmpty ? null : prices.reduce((a, b) => a > b ? a : b);
  }

  // Get price range string
  String get priceRange {
    final min = minPrice;
    final max = maxPrice;
    if (min == null && max == null) return 'Price not available';
    if (min == max) return '₹${min!.toStringAsFixed(2)}';
    return '₹${min!.toStringAsFixed(2)} - ₹${max!.toStringAsFixed(2)}';
  }
}


