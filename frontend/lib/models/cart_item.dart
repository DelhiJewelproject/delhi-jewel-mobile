import 'product.dart';
import 'product_size.dart';

class CartItem {
  final Product product;
  ProductSize? selectedSize;
  int quantity;
  double get totalPrice {
    if (selectedSize != null) {
      final price = selectedSize!.minPrice ?? 0.0;
      return price * quantity;
    }
    return 0.0;
  }

  CartItem({
    required this.product,
    this.selectedSize,
    this.quantity = 1,
  });
}

