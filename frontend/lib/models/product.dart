import 'dart:convert';
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
  final List<String>? designs; // Product designs (e.g., ['ACK', 'BLK', 'BLC'])

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
    this.designs,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    // Parse designs field - can be a list, JSON string, comma-separated string, or object with 'designs' key
    List<String>? designs;
    if (json['designs'] != null) {
      final designsData = json['designs'];
      
      if (designsData is List) {
        // Already a list - convert to List<String>
        designs = designsData.map((d) => d.toString()).toList();
      } else if (designsData is Map) {
        // Object format: {"count": 21, "designs": [...]}
        if (designsData.containsKey('designs') && designsData['designs'] is List) {
          final designsList = designsData['designs'] as List;
          designs = designsList.map((d) {
            // If d is a Map, extract design_name, design_code, or name
            if (d is Map) {
              return (d['design_name'] ?? d['design_code'] ?? d['name'] ?? '').toString();
            }
            return d.toString();
          }).where((d) => d.isNotEmpty).toList();
        }
      } else if (designsData is String) {
        final designsStr = designsData;
        if (designsStr.trim().startsWith('[')) {
          // JSON array string
          try {
            final parsed = jsonDecode(designsStr) as List;
            designs = parsed.map((d) => d.toString()).toList();
          } catch (e) {
            // If parsing fails, try comma-separated
            designs = designsStr.split(',').map((d) => d.trim()).where((d) => d.isNotEmpty).toList();
          }
        } else {
          // Comma-separated string
          designs = designsStr.split(',').map((d) => d.trim()).where((d) => d.isNotEmpty).toList();
        }
      }
    }
    
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
      designs: designs,
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
      'designs': designs,
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


