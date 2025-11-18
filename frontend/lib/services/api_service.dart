import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';

class ApiService {
  // Update this URL to match your backend server
  // For Android Emulator: use 'http://10.0.2.2:8000'
  // For iOS Simulator: use 'http://localhost:8000'
  // For Physical Device: use 'http://192.168.2.128:8000' (your computer's IP)
  // Change this IP to your computer's local IP address (check with: ipconfig on Windows)
  static const String baseUrl = 'http://192.168.2.128:8000';

  static Future<Product> getProductByBarcode(String barcode) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/product/barcode/$barcode'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout. Please check your network connection.');
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        try {
          return Product.fromJson(jsonData);
        } catch (e) {
          print('Error parsing product by barcode: $e');
          print('Product data: $jsonData');
          rethrow;
        }
      } else if (response.statusCode == 404) {
        throw Exception('Product not found');
      } else {
        throw Exception('Failed to load product: ${response.statusCode}');
      }
    } catch (e) {
      print('API Error (barcode): $e');
      if (e.toString().contains('timeout') || e.toString().contains('Connection timed out')) {
        throw Exception('Connection timeout. Please check your network connection.');
      }
      throw Exception('Network error: $e');
    }
  }

  static Future<Product> getProductById(int productId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/product/$productId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout. Please check your network connection.');
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        try {
          return Product.fromJson(jsonData);
        } catch (e) {
          print('Error parsing product by ID: $e');
          print('Product data: $jsonData');
          rethrow;
        }
      } else if (response.statusCode == 404) {
        throw Exception('Product not found');
      } else {
        throw Exception('Failed to load product: ${response.statusCode}');
      }
    } catch (e) {
      print('API Error (ID): $e');
      if (e.toString().contains('timeout') || e.toString().contains('Connection timed out')) {
        throw Exception('Connection timeout. Please check your network connection.');
      }
      throw Exception('Network error: $e');
    }
  }

  static Future<List<Product>> getAllProducts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/products'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout. Please check your network connection and ensure the backend is running at $baseUrl');
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        return jsonData.map((json) {
          try {
            return Product.fromJson(json);
          } catch (e) {
            print('Error parsing product: $e');
            print('Product data: $json');
            rethrow;
          }
        }).toList();
      } else {
        throw Exception('Failed to load products: ${response.statusCode}');
      }
    } catch (e) {
      print('API Error: $e');
      if (e.toString().contains('timeout') || e.toString().contains('Connection timed out')) {
        throw Exception('Connection timeout. Please ensure:\n1. Backend is running at $baseUrl\n2. Both devices are on the same WiFi network\n3. Firewall allows port 8000');
      }
      throw Exception('Network error: $e');
    }
  }

  static Future<List<Product>> searchProducts(String query) async {
    try {
      // Get all products and filter by query
      final allProducts = await getAllProducts();
      if (query.isEmpty) return [];
      
      final lowerQuery = query.toLowerCase();
      return allProducts.where((product) {
        final name = (product.name ?? '').toLowerCase();
        final externalId = (product.externalId ?? '').toString();
        final category = (product.categoryName ?? '').toLowerCase();
        return name.contains(lowerQuery) || 
               externalId.contains(lowerQuery) ||
               category.contains(lowerQuery);
      }).toList();
    } catch (e) {
      throw Exception('Search error: $e');
    }
  }

  static String getProductQrCodeUrl(int productId) {
    return '$baseUrl/api/product/$productId/qr-code';
  }

  static Future<Map<String, dynamic>> createOrder(Map<String, dynamic> orderData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/order'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(orderData),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Failed to create order');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}


