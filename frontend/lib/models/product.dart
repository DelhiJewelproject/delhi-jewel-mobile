class Product {
  final int? id;
  final String? name;
  final String? description;
  final double? price;
  final String? imageUrl;
  final String? barcode;
  final String? category;
  final int? stock;

  Product({
    this.id,
    this.name,
    this.description,
    this.price,
    this.imageUrl,
    this.barcode,
    this.category,
    this.stock,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int?,
      name: json['name'] as String?,
      description: json['description'] as String?,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      imageUrl: json['image_url'] as String?,
      barcode: json['barcode'] as String?,
      category: json['category'] as String?,
      stock: json['stock'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'barcode': barcode,
      'category': category,
      'stock': stock,
    };
  }
}


