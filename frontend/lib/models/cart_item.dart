import 'product.dart';
import 'product_size.dart';

class CartItem {
  final Product product;
  ProductSize? selectedSize;
  int quantity;
  final double unitPrice; // Store the actual unit price entered
  
  double get totalPrice {
    return unitPrice * quantity;
  }

  CartItem({
    required this.product,
    this.selectedSize,
    this.quantity = 1,
    required this.unitPrice, // Require unit price
  });
}

