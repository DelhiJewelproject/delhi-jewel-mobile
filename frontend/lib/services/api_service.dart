import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../models/challan.dart';

class ApiService {
  /// Backend API base URL. Frontend runs locally; API points to remote server by default.
  /// Override for local backend: flutter run --dart-define=API_BASE_URL=http://10.0.2.2:9010
  static String get baseUrl =>
      const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://13.202.81.19:9010',
      );

  static Future<Product> getProductByBarcode(String barcode) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/product/barcode/$barcode'), // Now this will be correct
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception(
              'Connection timeout. Please check your network connection.');
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
      if (e.toString().contains('timeout') ||
          e.toString().contains('Connection timed out')) {
        throw Exception(
            'Connection timeout. Please check your network connection.');
      }
      throw Exception('Network error: $e');
    }
  }

  // Update all other methods similarly:
  static Future<Product> getProductById(int productId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/products-master/$productId'), // Using products_master endpoint
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception(
              'Connection timeout. Please check your network connection.');
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
      if (e.toString().contains('timeout') ||
          e.toString().contains('Connection timed out')) {
        throw Exception(
            'Connection timeout. Please check your network connection.');
      }
      throw Exception('Network error: $e');
    }
  }

  /// In-memory cache for product catalog to avoid repeated slow loads in the same flow.
  static List<Product>? _productsCache;
  static DateTime? _productsCacheTime;
  static const _productsCacheValidDuration = Duration(minutes: 2);

  static Future<List<Product>> getAllProducts() async {
    final now = DateTime.now();
    if (_productsCache != null &&
        _productsCacheTime != null &&
        now.difference(_productsCacheTime!) < _productsCacheValidDuration) {
      return _productsCache!;
    }
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/products-master/'), // Using products_master endpoint
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 60), // Increased timeout for large product catalogs
        onTimeout: () {
          throw Exception(
              'Connection timeout. Please check your network connection and ensure the backend is running at $baseUrl');
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        final list = jsonData.map((json) {
          try {
            return Product.fromJson(json);
          } catch (e) {
            if (kDebugMode) {
              print('Error parsing product: $e');
              print('Product data: $json');
            }
            rethrow;
          }
        }).toList();
        _productsCache = list;
        _productsCacheTime = DateTime.now();
        return list;
      } else {
        throw Exception('Failed to load products: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('API Error: $e');
      if (e.toString().contains('timeout') ||
          e.toString().contains('Connection timed out')) {
        throw Exception(
            'Connection timeout. Please ensure:\n1. Backend is running at $baseUrl\n2. Both devices are on the same WiFi network\n3. Firewall allows port 9010');
      }
      throw Exception('Network error: $e');
    }
  }

  // Update all other endpoints similarly:
  static Future<Map<String, dynamic>> createOrder(
      Map<String, dynamic> orderData) async {
    try {
      print('Sending order data: $orderData');
      final response = await http
          .post(
        Uri.parse('$baseUrl/api/order'), // Fixed
        headers: {'Content-Type': 'application/json'},
        body: json.encode(orderData),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout. Please check your connection.');
        },
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        try {
          final errorData = json.decode(response.body);
          final errorMessage = errorData['detail'] ??
              errorData['message'] ??
              'Failed to create order';
          print('Error from server: $errorMessage');
          throw Exception(errorMessage);
        } catch (e) {
          if (e.toString().contains('Exception:')) {
            rethrow;
          }
          throw Exception(
              'Failed to create order: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      print('API Error in createOrder: $e');
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> createOrderWithMultipleItems(
      Map<String, dynamic> orderData) async {
    try {
      final response = await http
          .post(
        Uri.parse('$baseUrl/api/order/multiple'), // Fixed
        headers: {'Content-Type': 'application/json'},
        body: json.encode(orderData),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception(
              'Connection timeout. Please check your network connection.');
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception(
            'Order endpoint not found. Please ensure the backend server is running and has been restarted with the latest code.');
      } else {
        final errorBody = response.body;
        print('Error response (${response.statusCode}): $errorBody');
        try {
          final errorJson = json.decode(errorBody);
          final errorDetail =
              errorJson['detail'] ?? errorJson['message'] ?? 'Unknown error';
          throw Exception(errorDetail);
        } catch (e) {
          throw Exception(
              'Failed to create order: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      print('API Error in createOrderWithMultipleItems: $e');
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> generateLabels(
      Map<String, dynamic> labelData) async {
    try {
      print('Sending label data: $labelData');
      final response = await http
          .post(
        Uri.parse('$baseUrl/api/labels/generate'), // Fixed
        headers: {'Content-Type': 'application/json'},
        body: json.encode(labelData),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception(
              'Connection timeout. Please check your network connection.');
        },
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        try {
          final errorData = json.decode(response.body);
          final errorMessage = errorData['detail'] ??
              errorData['message'] ??
              'Failed to generate labels';
          print('Error from server: $errorMessage');
          throw Exception(errorMessage);
        } catch (e) {
          if (e.toString().contains('Exception:')) {
            rethrow;
          }
          throw Exception(
              'Failed to generate labels: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      print('API Error in generateLabels: $e');
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Update other methods...
  static String getProductQrCodeUrl(int productId) {
    return '$baseUrl/api/product/$productId/qr-code'; // Fixed
  }

  static Future<Map<String, dynamic>> verifyWhatsApp(String phoneNumber) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/verify/whatsapp/$phoneNumber'), // Fixed
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Connection timeout');
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to verify WhatsApp: ${response.statusCode}');
      }
    } catch (e) {
      print('API Error (WhatsApp verification): $e');
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> sendWhatsAppMessage(String phoneNumber, String message) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/whatsapp/send'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone_number': phoneNumber,
          'message': message,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? errorData['message'] ?? 'Failed to send WhatsApp message');
      }
    } catch (e) {
      print('API Error (WhatsApp send): $e');
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> _getChallanOptionsOnce({bool quick = false}) async {
    final uri = quick
        ? Uri.parse('$baseUrl/api/challan/options?quick=true')
        : Uri.parse('$baseUrl/api/challan/options');
    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw Exception('Connection timeout'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Server error ${response.statusCode}');
  }

  /// Load challan options. Use quick=true for challan form (faster, challans only).
  static Future<Map<String, dynamic>> getChallanOptions({bool quick = false}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        return await _getChallanOptionsOnce(quick: quick);
      } catch (e) {
        lastError = e;
        if (attempt == 4) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    final msg = lastError.toString();
    if (msg.contains('Timeout') || msg.contains('timeout') || msg.contains('Future') || msg.contains('Socket') || msg.contains('Connection') || msg.contains('Failed host')) {
      throw Exception('Cannot reach server. Check Wi‑Fi and that the server is on, then tap Retry.');
    }
    throw Exception('Unable to load options. Tap Retry or check your connection.');
  }

  static Future<Challan> createChallan(Map<String, dynamic> challanData) async {
    try {
      final response = await http
          .post(
        Uri.parse('$baseUrl/api/challans'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(challanData),
      )
          .timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('Request timed out while creating challan');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = json.decode(response.body);
        return Challan.fromJson(jsonData as Map<String, dynamic>);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ??
            'Failed to create challan (${response.statusCode})');
      }
    } catch (e) {
      if (e.toString().contains('Exception:')) rethrow;
      throw Exception('Error creating challan: $e');
    }
  }

  /// Delete a challan on the server (draft or otherwise). Use when user deletes a draft from Old Challans.
  static Future<void> deleteChallan(int challanId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/challans/$challanId'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 && response.statusCode != 204) {
      final body = response.body;
      throw Exception(
        body.isNotEmpty ? body : 'Failed to delete challan (${response.statusCode})',
      );
    }
  }

  static Future<Challan> updateChallan(int challanId, Map<String, dynamic> challanData) async {
    try {
      final response = await http
          .put(
        Uri.parse('$baseUrl/api/challans/$challanId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(challanData),
      )
          .timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('Request timed out while updating challan');
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return Challan.fromJson(jsonData as Map<String, dynamic>);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ??
            'Failed to update challan (${response.statusCode})');
      }
    } catch (e) {
      if (e.toString().contains('Exception:')) rethrow;
      throw Exception('Error updating challan: $e');
    }
  }

  static Future<List<Challan>> getChallans({
    String? status,
    String? search,
    int limit = 50,
  }) async {
    final queryParameters = <String, String>{
      'limit': limit.toString(),
    };
    if (status != null && status.isNotEmpty) {
      queryParameters['status'] = status;
    }
    if (search != null && search.isNotEmpty) {
      queryParameters['search'] = search;
    }
    final uri = Uri.parse('$baseUrl/api/challans')
        .replace(queryParameters: queryParameters);

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await http.get(
          uri,
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 90));

        if (response.statusCode == 200) {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          final List<dynamic> challansJson =
              jsonData['challans'] as List<dynamic>? ?? [];
          return challansJson
              .map((c) => Challan.fromJson(c as Map<String, dynamic>))
              .toList();
        } else {
          throw Exception('Failed to load challans (${response.statusCode})');
        }
      } catch (e) {
        lastError = e;
        if (attempt == 3) {
          throw Exception(
            e.toString().contains('Timeout') || e.toString().contains('timeout')
                ? 'Server took too long. Tap Retry or check your connection.'
                : 'Error fetching challans: $e',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw Exception('Error fetching challans: $lastError');
  }

  /// Draft challans with zero items. Used to reuse one instead of creating a new challan.
  static Future<List<Challan>> getEmptyDraftChallans({int limit = 10}) async {
    final uri = Uri.parse('$baseUrl/api/challans/empty-drafts')
        .replace(queryParameters: {'limit': limit.toString()});
    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      return [];
    }
    final jsonData = json.decode(response.body) as Map<String, dynamic>?;
    final List<dynamic> list = jsonData?['challans'] as List<dynamic>? ?? [];
    return list
        .map((c) => Challan.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  static Future<Challan> getChallanById(int challanId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/challans/$challanId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return Challan.fromJson(
            json.decode(response.body) as Map<String, dynamic>);
      } else if (response.statusCode == 404) {
        throw Exception('Challan not found');
      } else {
        throw Exception('Failed to load challan (${response.statusCode})');
      }
    } catch (e) {
      throw Exception('Error fetching challan: $e');
    }
  }

  static Future<Challan> getChallanByNumber(String challanNumber) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/challans/by-number/${Uri.encodeComponent(challanNumber)}'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return Challan.fromJson(
            json.decode(response.body) as Map<String, dynamic>);
      } else if (response.statusCode == 404) {
        throw Exception('Challan not found');
      } else {
        throw Exception('Failed to load challan (${response.statusCode})');
      }
    } catch (e) {
      throw Exception('Error fetching challan: $e');
    }
  }

  static String getChallanQrUrl(int challanId) {
    return '$baseUrl/api/challans/$challanId/qr';
  }

  static String getChallanQrUrlByNumber(String challanNumber) {
    return '$baseUrl/api/challans/qr/${Uri.encodeComponent(challanNumber)}';
  }

  static Future<Map<String, String?>?> getPartyDataFromOrders(String partyName) async {
    if (partyName.trim().isEmpty) return null;
    final encoded = Uri.encodeComponent(partyName.trim());
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/api/orders/party-data?party_name=$encoded'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 25));

        if (response.statusCode == 200) {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          String? station = jsonData['station']?.toString();
          String? phoneNumber = jsonData['phone_number']?.toString();
          String? priceCategory = jsonData['price_category']?.toString();
          String? transportName = jsonData['transport_name']?.toString();
          return {
            'station': (station != null && station.isNotEmpty) ? station : null,
            'phone_number': (phoneNumber != null && phoneNumber.isNotEmpty) ? phoneNumber : null,
            'price_category': (priceCategory != null && priceCategory.isNotEmpty) ? priceCategory : null,
            'transport_name': (transportName != null && transportName.isNotEmpty) ? transportName : null,
          };
        } else if (response.statusCode == 404) {
          return null;
        } else {
          throw Exception('Failed to load party data (${response.statusCode})');
        }
      } catch (e) {
        if (attempt == 2) {
          if (kDebugMode) print('Error fetching party data: $e');
          return null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    return null;
  }
}
