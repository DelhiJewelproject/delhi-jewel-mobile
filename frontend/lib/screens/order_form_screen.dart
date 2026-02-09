import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../models/product.dart';
import '../models/product_size.dart';
import '../models/cart_item.dart';
import '../models/challan.dart';
import 'order_form_products_screen.dart';

class OrderFormScreen extends StatefulWidget {
  final List<CartItem>? initialCartItems;
  final String? initialPriceCategory;
  final int? initialQuantity;

  const OrderFormScreen({
    super.key,
    this.initialCartItems,
    this.initialPriceCategory,
    this.initialQuantity,
  });

  @override
  State<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends State<OrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _partyNameController = TextEditingController();
  final _stationController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerEmailController = TextEditingController();
  final _customerAddressController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _sizeTextController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _unitPriceController = TextEditingController();
  final _transportNameController = TextEditingController();
  final _createdByController = TextEditingController();

  String? _selectedPaymentMethod;
  bool _isLoading = false;
  bool _isSearchingProducts = false;
  bool _isLoadingOptions = false;
  bool _isLoadingPartyData = false;
  String? _errorMessage;

  List<String> _partyOptions = [];
  List<String> _stationOptions = [];
  List<String> _customerNameOptions = [];
  List<String> _customerPhoneOptions = [];
  List<String> _priceCategories = [];
  List<String> _transportNames = [];
  List<String> _createdByOptions = ['Admin', 'User', 'Manager', 'Staff']; // Default options
  String? _selectedPriceCategory;

  Product? _selectedProduct;
  ProductSize? _selectedSize;
  String? _selectedPriceTier; // A, B, C, D, E, R
  List<Product> _productSuggestions = [];
  double _calculatedTotal = 0.0;
  bool _hasWhatsApp = false;
  bool _isVerifyingWhatsApp = false;
  Timer? _whatsAppCheckTimer;
  String? _lastGreetedPhone; // Track last phone number that received greeting

  // Cart for multiple products
  List<CartItem> _cartItems = [];
  
  // Track if cart has been initialized to prevent accidental resets
  bool _cartInitialized = false;

  // QR Scanner
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
bool _isScanning = false;

void toggleScanner() async {
  if (_isScanning) {
    await _scannerController.stop();
    _isScanning = false;
  } else {
    await _scannerController.start();
    _isScanning = true;
  }
}
  bool _showScanner = false;
  String? _lastScannedCode;

  @override
  void initState() {
    super.initState();
    // Initialize cart with items from view screen if provided
    // Always append to existing cart items, never replace
    if (widget.initialCartItems != null &&
        widget.initialCartItems!.isNotEmpty) {
      // Create cart items with explicit quantity preservation
      final newItems = widget.initialCartItems!.map((item) {
        final qty = item.quantity; // Explicitly capture quantity
        return CartItem(
          product: item.product,
          selectedSize: item.selectedSize,
          quantity: qty, // Explicitly set quantity
          unitPrice: item.unitPrice,
        );
      }).toList();
      
      // Append new items to existing cart, don't replace
      _cartItems.addAll(newItems);
      
      _cartInitialized = true; // Mark as initialized
      _updateTotal();
    }
    // Set initial price category if provided
    if (widget.initialPriceCategory != null) {
      _selectedPriceCategory = widget.initialPriceCategory;
    }
    // Set initial quantity if provided
    if (widget.initialQuantity != null) {
      _quantityController.text = widget.initialQuantity.toString();
    }
    _loadOptions().then((_) {
      // Ensure quantity is set after options load
      if (widget.initialQuantity != null && mounted) {
        _quantityController.text = widget.initialQuantity.toString();
        // NEVER re-initialize cart items here - they should already be initialized in initState
        // Only update the quantity controller text, don't touch cart items at all
        setState(() {});
      }
      // Check for incomplete orders after options are loaded
      _checkForIncompleteOrder();
    });
  }

  Future<void> _checkForIncompleteOrder() async {
    try {
      final draftOrder = await LocalStorageService.getDraftOrder();
      if (draftOrder != null && mounted) {
        final orderData = draftOrder['order_data'] as Map<String, dynamic>;
        final storedItems = draftOrder['stored_items'] as List<ChallanItem>;
        final itemCount = storedItems.length;
        final savedAt = draftOrder['saved_at'] as String?;
        
        // Show dialog to continue or create new
        final shouldContinue = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withOpacity(0.6),
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header with icon
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFB8860B), Color(0xFFC9A227)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shopping_cart_outlined,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Title - wrapped to prevent overflow
                      Text(
                        'Incomplete Order Found',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You have an order that was not completed',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      
                      // Order details card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F8F8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFB8860B).withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildOrderDetailRow(
                              Icons.receipt_long_outlined,
                              'Order Number',
                              draftOrder['order_number'] as String,
                            ),
                            const SizedBox(height: 12),
                            _buildOrderDetailRow(
                              Icons.business_outlined,
                              'Party',
                              orderData['party_name'] ?? 'N/A',
                            ),
                            const SizedBox(height: 12),
                            _buildOrderDetailRow(
                              Icons.location_city_outlined,
                              'Station',
                              orderData['station'] ?? 'N/A',
                            ),
                            if (itemCount > 0) ...[
                              const SizedBox(height: 12),
                              _buildOrderDetailRow(
                                Icons.inventory_2_outlined,
                                'Items Added',
                                '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).pop(false); // Create new
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: BorderSide(
                                  color: Colors.grey.shade300,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Create New',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop(true); // Continue
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB8860B),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.arrow_forward, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'Continue',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        if (shouldContinue == true && mounted) {
          // Load the incomplete order data
          final orderData = draftOrder['order_data'] as Map<String, dynamic>;
          final storedItems = draftOrder['stored_items'] as List<ChallanItem>;
          final designAllocations = draftOrder['design_allocations'] as Map<String, Map<String, int>>;
          
          // Fill form with saved data
          _partyNameController.text = orderData['party_name'] ?? '';
          _stationController.text = orderData['station'] ?? '';
          _selectedPriceCategory = orderData['price_category'];
          _customerPhoneController.text = orderData['customer_phone'] ?? '';
          _customerEmailController.text = orderData['customer_email'] ?? '';
          _customerAddressController.text = orderData['customer_address'] ?? '';
          _transportNameController.text = orderData['transport_name'] ?? '';
          _createdByController.text = orderData['created_by'] ?? '';
          _selectedPaymentMethod = orderData['payment_method'];
          
          // Navigate directly to add quantity screen with saved data
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => OrderFormProductsScreen(
                partyName: _partyNameController.text,
                orderNumber: draftOrder['order_number'] as String,
                orderData: orderData,
                initialStoredItems: storedItems,
                initialDesignAllocations: designAllocations,
              ),
            ),
          );
        } else if (shouldContinue == false && mounted) {
          // User chose to create new - clear draft order
          await LocalStorageService.removeDraftOrder();
        }
      }
    } catch (e) {
      print('Error checking for incomplete order: $e');
    }
  }

  @override
  void dispose() {
    _whatsAppCheckTimer?.cancel();
    _partyNameController.dispose();
    _stationController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    _customerAddressController.dispose();
    _productSearchController.dispose();
    _sizeTextController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    _transportNameController.dispose();
    _createdByController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _calculateTotal() {
    final quantity = int.tryParse(_quantityController.text) ?? 1;
    final unitPrice = double.tryParse(_unitPriceController.text) ?? 0.0;
    setState(() {
      _calculatedTotal = quantity * unitPrice;
    });
  }

  Future<void> _loadOptions() async {
    setState(() {
      _isLoadingOptions = true;
      _errorMessage = null;
    });
    try {
      final options = await ApiService.getChallanOptions();
      if (!mounted) return;

      // Remove duplicates and normalize data
      final rawPartyNames = List<String>.from(options['party_names'] ?? []);
      final rawStationNames = List<String>.from(options['station_names'] ?? []);

      // Handle customer names - ensure it's a list and convert all items to strings
      final customerNamesRaw = options['customer_names'];
      final rawCustomerNames = customerNamesRaw != null
          ? (customerNamesRaw as List)
              .map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList()
              .cast<String>()
          : <String>[];

      // Handle customer phones - ensure it's a list and convert all items to strings
      final customerPhonesRaw = options['customer_phones'];
      final rawCustomerPhones = customerPhonesRaw != null
          ? (customerPhonesRaw as List)
              .map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList()
              .cast<String>()
          : <String>[];

      // Deduplicate party names (case-insensitive)
      final seenParty = <String>{};
      final partyNames = <String>[];
      for (var name in rawPartyNames) {
        if (name.isNotEmpty) {
          final normalized = name.trim().toLowerCase();
          if (normalized.isNotEmpty && !seenParty.contains(normalized)) {
            seenParty.add(normalized);
            partyNames.add(name.trim());
          }
        }
      }

      // Deduplicate station names (case-insensitive)
      final seenStation = <String>{};
      final stationNames = <String>[];
      for (var name in rawStationNames) {
        if (name.isNotEmpty) {
          final normalized = name.trim().toLowerCase();
          if (normalized.isNotEmpty && !seenStation.contains(normalized)) {
            seenStation.add(normalized);
            stationNames.add(name.trim());
          }
        }
      }

      // Deduplicate customer names (case-insensitive)
      final seenCustomerNames = <String>{};
      final customerNames = <String>[];
      for (var name in rawCustomerNames) {
        if (name.isNotEmpty) {
          final normalized = name.trim().toLowerCase();
          if (normalized.isNotEmpty &&
              !seenCustomerNames.contains(normalized)) {
            seenCustomerNames.add(normalized);
            customerNames.add(name.trim());
          }
        }
      }

      // Deduplicate customer phones
      final seenCustomerPhones = <String>{};
      final customerPhones = <String>[];
      for (var phone in rawCustomerPhones) {
        if (phone.isNotEmpty) {
          // Normalize phone by removing non-digits for comparison
          final cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
          if (cleanPhone.isNotEmpty &&
              !seenCustomerPhones.contains(cleanPhone)) {
            seenCustomerPhones.add(cleanPhone);
            customerPhones.add(phone.trim());
          }
        }
      }

      // Handle price categories
      final rawPriceCategories = List<String>.from(options['price_categories'] ?? [])
          .where((name) => name != null && name.toString().isNotEmpty)
          .map((name) => name.toString().trim())
          .toSet()
          .toList()
        ..sort();

      // Handle transport names
      final rawTransportNames = List<String>.from(options['transport_names'] ?? [])
          .where((name) => name != null && name.toString().isNotEmpty)
          .map((name) => name.toString().trim())
          .toSet()
          .toList()
        ..sort();

      // Sort for better UX
      partyNames.sort();
      stationNames.sort();
      customerNames.sort();
      customerPhones.sort();


      setState(() {
        _partyOptions = partyNames;
        _stationOptions = stationNames;
        _customerNameOptions = customerNames;
        _customerPhoneOptions = customerPhones;
        _priceCategories = rawPriceCategories;
        _transportNames = rawTransportNames;
        _isLoadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingOptions = false;
        _errorMessage = 'Unable to load options. Please check your connection.';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Unable to load options: ${e.toString().split(':').last}'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadOptions,
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadPartyData(String partyName) async {
    if (partyName.trim().isEmpty) {
      return;
    }

    setState(() => _isLoadingPartyData = true);

    try {
      // Get all data from orders (station, phone number, price category, transport_name)
      final partyData = await ApiService.getPartyDataFromOrders(partyName.trim());

      if (!mounted) return;

      bool hasChanges = false;
      List<String> filledFields = [];

      // Debug: Print party data to see what we're getting
      if (kDebugMode && partyData != null) {
        print('Party data received: $partyData');
        print('Transport name in response: ${partyData['transport_name']}');
      }

      if (mounted && partyData != null) {
        // Auto-fill station from orders (always update when party changes)
        if (partyData['station'] != null &&
            partyData['station']!.toString().trim().isNotEmpty) {
          final newStation = partyData['station']!.toString().trim();
          if (_stationController.text != newStation) {
            _stationController.text = newStation;
            hasChanges = true;
            filledFields.add('Station');
          }
        }

        // Auto-fill price category from orders (always update when party changes)
        if (partyData['price_category'] != null &&
            partyData['price_category']!.toString().trim().isNotEmpty) {
          final newPriceCategory = partyData['price_category']!.toString().trim();
          if (_selectedPriceCategory != newPriceCategory) {
            setState(() {
              _selectedPriceCategory = newPriceCategory;
            });
            hasChanges = true;
            filledFields.add('Price Category');
          }
        }

        // Auto-fill phone number from orders (always update when party changes)
        if (partyData['phone_number'] != null &&
            partyData['phone_number']!.toString().trim().isNotEmpty) {
          final newPhone = partyData['phone_number']!.toString().trim();
          if (_customerPhoneController.text != newPhone) {
            _customerPhoneController.text = newPhone;
            hasChanges = true;
            filledFields.add('Phone Number');
          }
        }

        // Auto-fill transport name from orders (always update when party changes)
        if (partyData['transport_name'] != null &&
            partyData['transport_name']!.toString().trim().isNotEmpty) {
          final newTransport = partyData['transport_name']!.toString().trim();
          // Always update transport name when party changes, even if it's the same
          _transportNameController.text = newTransport;
          hasChanges = true;
          filledFields.add('Transport Name');
        } else {
          // Clear transport name if no data found for this party
          if (_transportNameController.text.isNotEmpty) {
            _transportNameController.clear();
            hasChanges = true;
          }
        }

        if (hasChanges) {
          setState(() {});

          // Show a subtle notification
          // if (mounted) {
          //   ScaffoldMessenger.of(context).showSnackBar(
          //     SnackBar(
          //       content: Row(
          //         children: [
          //           const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
          //           const SizedBox(width: 8),
          //           Expanded(
          //             child: Text(
          //               'Auto-filled: ${filledFields.join(", ")}',
          //             ),
          //           ),
          //         ],
          //       ),
          //       backgroundColor: const Color(0xFF10B981),
          //       duration: const Duration(seconds: 2),
          //       behavior: SnackBarBehavior.floating,
          //     ),
          //   );
          // }
        }
      }
    } catch (e, stackTrace) {
      // Log error but don't show to user - auto-fill is optional
    } finally {
      if (mounted) {
        setState(() => _isLoadingPartyData = false);
      }
    }
  }

  Future<void> _checkWhatsApp(String phone) async {
    // Cancel previous timer if exists
    _whatsAppCheckTimer?.cancel();

    if (phone.isEmpty) {
      setState(() {
        _hasWhatsApp = false;
        _isVerifyingWhatsApp = false;
        _lastGreetedPhone = null; // Reset greeting when phone is cleared
      });
      return;
    }

    // Clean phone number (remove spaces, dashes, +, etc.)
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');

    // Remove leading 0 if present
    if (cleanPhone.startsWith('0')) {
      cleanPhone = cleanPhone.substring(1);
    }

    // Add country code if not present (assuming India +91)
    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }

    if (cleanPhone.length < 10) {
      setState(() {
        _hasWhatsApp = false;
        _isVerifyingWhatsApp = false;
      });
      return;
    }

    // Validate phone number format (should be 10-15 digits)
    final phoneRegex = RegExp(r'^[1-9]\d{9,14}$');
    if (!phoneRegex.hasMatch(cleanPhone)) {
      setState(() {
        _hasWhatsApp = false;
        _isVerifyingWhatsApp = false;
      });
      return;
    }

    // Debounce: Wait 1 second after user stops typing before checking
    _whatsAppCheckTimer = Timer(const Duration(seconds: 1), () async {
      await _performWhatsAppCheck(cleanPhone);
    });
  }

  Future<void> _performWhatsAppCheck(String cleanPhone) async {
    if (!mounted) return;

    setState(() => _isVerifyingWhatsApp = true);

    try {
      // Use backend API to verify WhatsApp number format
      final result = await ApiService.verifyWhatsApp(cleanPhone);

      if (mounted) {
        final isValid =
            result['valid'] == true && result['has_whatsapp_format'] == true;

        setState(() {
          _hasWhatsApp = isValid;
          _isVerifyingWhatsApp = false;
        });

        if (isValid) {
          // Send "Hi" greeting automatically when valid WhatsApp number is detected
          // Only send once per phone number to avoid spamming
          if (_lastGreetedPhone != cleanPhone) {
            _lastGreetedPhone = cleanPhone;
            // Send greeting after a short delay to ensure WhatsApp is ready
            // Pass the cleaned phone number directly to avoid re-processing
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                _sendHiToWhatsApp(cleanPhone);
              }
            });
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(result['message'] ?? 'WhatsApp number format is valid'),
              backgroundColor: const Color(0xFF25D366),
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(result['message'] ?? 'Invalid WhatsApp number format'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // Fallback to local validation if API fails
        final whatsappUrl = 'https://wa.me/$cleanPhone';
        final uri = Uri.parse(whatsappUrl);

        final isValid = uri.scheme == 'https' && uri.host == 'wa.me';

        setState(() {
          _hasWhatsApp = isValid;
          _isVerifyingWhatsApp = false;
        });

        if (isValid) {
          // Send "Hi" greeting automatically when valid WhatsApp number is detected (fallback case)
          // Only send once per phone number to avoid spamming
          if (_lastGreetedPhone != cleanPhone) {
            _lastGreetedPhone = cleanPhone;
            // Send greeting after a short delay to ensure WhatsApp is ready
            // Pass the cleaned phone number directly to avoid re-processing
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                _sendHiToWhatsApp(cleanPhone);
              }
            });
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Could not verify WhatsApp number: ${e.toString()}'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<void> _sendToWhatsApp(String orderNumber) async {
    final phone =
        _customerPhoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (phone.isEmpty) return;

    final message = '''
*Order Confirmation - DecoJewels*

Order Number: *$orderNumber*
Party Name: ${_partyNameController.text}
Station: ${_stationController.text}
Customer: ${_customerNameController.text}
Phone: ${_customerPhoneController.text}

Product: ${_selectedProduct?.name ?? 'N/A'}
Size: ${_sizeTextController.text}
Quantity: ${_quantityController.text}
Unit Price: ₹${_unitPriceController.text}
Total: ₹${_calculatedTotal.toStringAsFixed(2)}

Payment Method: ${_selectedPaymentMethod ?? 'Not specified'}

Thank you for your order!
    ''';

    final whatsappUrl =
        'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';
    try {
      final uri = Uri.parse(whatsappUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open WhatsApp: $e')),
      );
    }
  }

  Future<void> _sendHiToWhatsApp([String? phoneNumber]) async {
    // Use provided phone number or get from controller
    String phone = phoneNumber ?? _customerPhoneController.text
        .replaceAll(RegExp(r'[^\d]'), '');
    
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter phone number')),
      );
      return;
    }

    // Clean phone number (remove spaces, dashes, +, etc.)
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    
    // Remove leading 0 if present
    if (cleanPhone.startsWith('0')) {
      cleanPhone = cleanPhone.substring(1);
    }

    // Add country code if missing (India)
    String formattedPhone = cleanPhone;
    if (formattedPhone.length == 10) {
      formattedPhone = '91$formattedPhone';
    }

    final message = 'HI';

    try {
      // Send message via API (automatic, no app opening)
      final result = await ApiService.sendWhatsAppMessage(formattedPhone, message);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Greeting message sent successfully'),
            backgroundColor: const Color(0xFF25D366),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send greeting: ${e.toString()}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // COMMENTED OUT - Product search functionality
  // Future<List<Product>> _searchProducts(String query) async {
  //   try {
  //     final allProducts = await ApiService.getAllProducts();

  //     // If query is empty, return first 30 products by default
  //     if (query.isEmpty) {
  //       return allProducts.take(30).toList();
  //     }

  //     // Filter products based on search query
  //     return allProducts
  //         .where((product) {
  //           final name = (product.name ?? '').toLowerCase();
  //           final externalId = product.externalId?.toString() ?? '';
  //           final searchQuery = query.toLowerCase();
  //           return name.contains(searchQuery) ||
  //               externalId.contains(searchQuery);
  //         })
  //         .take(30)
  //         .toList();
  //   } catch (e) {
  //     return [];
  //   }
  // }

  // COMMENTED OUT - Product selection functionality
  // Future<void> _selectProduct(Product product) async {
  //   setState(() {
  //     _isLoading = true;
  //     _selectedProduct = product;
  //     _selectedSize = null;
  //     _selectedPriceTier = null;
  //     _productSearchController.text = product.name ?? '';
  //     _sizeTextController.text = '';
  //     _unitPriceController.text = '';
  //   });

  //   try {
  //     // Fetch full product details with sizes from API
  //     if (product.id != null) {
  //       final fullProduct = await ApiService.getProductById(product.id!);
  //       setState(() {
  //         _selectedProduct = fullProduct;
  //         _isLoading = false;
  //       });

  //       // Auto-select first size if available
  //       if (fullProduct.sizes != null && fullProduct.sizes!.isNotEmpty) {
  //         _selectSize(fullProduct.sizes!.first);
  //       } else {
  //         setState(() {
  //           _isLoading = false;
  //         });
  //       }
  //     } else {
  //       setState(() {
  //         _isLoading = false;
  //       });
  //     }
  //   } catch (e) {
  //     setState(() {
  //       _isLoading = false;
  //     });
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Error loading product details: $e'),
  //         backgroundColor: Colors.red.shade600,
  //       ),
  //     );
  //   }
  // }

  // COMMENTED OUT - Size selection functionality
  // void _selectSize(ProductSize size) {
  //   setState(() {
  //     _selectedSize = size;
  //     _sizeTextController.text = size.sizeText ?? '';
  //     
  //     // Auto-select price tier based on selected price category
  //     if (_selectedPriceCategory != null && _selectedPriceCategory!.isNotEmpty) {
  //       final category = _selectedPriceCategory!.toUpperCase().trim();
  //       double? price;
  //       
  //       switch (category) {
  //         case 'A':
  //           price = size.priceA;
  //           if (price != null) {
  //             _selectedPriceTier = 'A';
  //             _unitPriceController.text = price.toStringAsFixed(2);
  //           }
  //           break;
  //         case 'B':
  //           price = size.priceB;
  //           if (price != null) {
  //             _selectedPriceTier = 'B';
  //             _unitPriceController.text = price.toStringAsFixed(2);
  //           }
  //           break;
  //         case 'C':
  //           price = size.priceC;
  //           if (price != null) {
  //             _selectedPriceTier = 'C';
  //             _unitPriceController.text = price.toStringAsFixed(2);
  //           }
  //           break;
  //         case 'D':
  //           price = size.priceD;
  //           if (price != null) {
  //             _selectedPriceTier = 'D';
  //             _unitPriceController.text = price.toStringAsFixed(2);
  //           }
  //           break;
  //         case 'E':
  //           price = size.priceE;
  //           if (price != null) {
  //             _selectedPriceTier = 'E';
  //             _unitPriceController.text = price.toStringAsFixed(2);
  //           }
  //           break;
  //         case 'R':
  //           price = size.priceR;
  //           if (price != null) {
  //             _selectedPriceTier = 'R';
  //             _unitPriceController.text = price.toStringAsFixed(2);
  //           }
  //           break;
  //         default:
  //           // Try to find category in the string
  //           if (category.contains('A') && size.priceA != null) {
  //             _selectedPriceTier = 'A';
  //             _unitPriceController.text = size.priceA!.toStringAsFixed(2);
  //           } else if (category.contains('B') && size.priceB != null) {
  //             _selectedPriceTier = 'B';
  //             _unitPriceController.text = size.priceB!.toStringAsFixed(2);
  //           } else if (category.contains('C') && size.priceC != null) {
  //             _selectedPriceTier = 'C';
  //             _unitPriceController.text = size.priceC!.toStringAsFixed(2);
  //           } else if (category.contains('D') && size.priceD != null) {
  //             _selectedPriceTier = 'D';
  //             _unitPriceController.text = size.priceD!.toStringAsFixed(2);
  //           } else if (category.contains('E') && size.priceE != null) {
  //             _selectedPriceTier = 'E';
  //             _unitPriceController.text = size.priceE!.toStringAsFixed(2);
  //           } else if (category.contains('R') && size.priceR != null) {
  //             _selectedPriceTier = 'R';
  //             _unitPriceController.text = size.priceR!.toStringAsFixed(2);
  //           } else {
  //             _selectedPriceTier = null;
  //             _unitPriceController.text = '';
  //           }
  //       }
  //     } else {
  //       _selectedPriceTier = null;
  //       _unitPriceController.text = '';
  //     }
  //     
  //     _calculateTotal();
  //   });
  // }

  // COMMENTED OUT - Price tier selection functionality
  // void _selectPriceTier(String tier) {
  //   if (_selectedSize == null) return;

  //   setState(() {
  //     _selectedPriceTier = tier;
  //     double? price;
  //     switch (tier) {
  //       case 'A':
  //         price = _selectedSize!.priceA;
  //         break;
  //       case 'B':
  //         price = _selectedSize!.priceB;
  //         break;
  //       case 'C':
  //         price = _selectedSize!.priceC;
  //         break;
  //       case 'D':
  //         price = _selectedSize!.priceD;
  //         break;
  //       case 'E':
  //         price = _selectedSize!.priceE;
  //         break;
  //       case 'R':
  //         price = _selectedSize!.priceR;
  //         break;
  //     }
  //     if (price != null) {
  //       _unitPriceController.text = price.toStringAsFixed(2);
  //     }
  //     _calculateTotal();
  //   });
  // }

  // COMMENTED OUT - Add to cart functionality
  // void _addToCart() {
  //   if (_selectedProduct == null) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('Please select a product first'),
  //         backgroundColor: Colors.orange,
  //       ),
  //     );
  //     return;
  //   }

  //   if (_selectedSize == null &&
  //       _selectedProduct!.sizes != null &&
  //       _selectedProduct!.sizes!.isNotEmpty) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('Please select a size first'),
  //         backgroundColor: Colors.orange,
  //       ),
  //     );
  //     return;
  //   }

  //   final unitPrice = double.tryParse(_unitPriceController.text) ?? 0.0;
  //   if (unitPrice <= 0) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('Please enter a valid unit price'),
  //         backgroundColor: Colors.orange,
  //       ),
  //     );
  //     return;
  //   }

  //   final quantity = int.tryParse(_quantityController.text) ?? 1;
  //   if (quantity <= 0) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('Please enter a valid quantity'),
  //         backgroundColor: Colors.orange,
  //       ),
  //     );
  //     return;
  //   }

  //   // Create a cart item with the selected product, size, and price
  //   final cartItem = CartItem(
  //     product: _selectedProduct!,
  //     selectedSize: _selectedSize,
  //     quantity: quantity,
  //     unitPrice: unitPrice, // Use the unit price from the controller
  //   );

  //   final productName = _selectedProduct!.name ?? 'Product';

  //   // Always add as new item - don't check for duplicates
  //   // Allow same product ID with different sizes to be added separately
  //   setState(() {
  //     // Simply add the new item to the cart without any duplicate checking
  //     _cartItems.add(cartItem);
  //     
  //     // Update total
  //     double total = 0.0;
  //     for (var item in _cartItems) {
  //       total += item.totalPrice;
  //     }
  //     _calculatedTotal = total;
  //     
  //     // Reset selection
  //     _selectedProduct = null;
  //     _selectedSize = null;
  //     _selectedPriceTier = null;
  //     _productSearchController.clear();
  //     _sizeTextController.clear();
  //     _quantityController.text = '1';
  //     _unitPriceController.clear();
  //   });

  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(
  //       content: Text('$productName added to cart'),
  //       backgroundColor: const Color(0xFF10B981),
  //       duration: const Duration(seconds: 1),
  //     ),
  //   );
  // }

  void _removeFromCart(int index) {
    setState(() {
      _cartItems.removeAt(index);
      _updateTotal();
    });
  }

  void _updateCartItemQuantity(int index, int change) {
    if (index >= _cartItems.length) return;
    setState(() {
      final newQuantity = _cartItems[index].quantity + change;
      if (newQuantity > 0) {
        _cartItems[index].quantity = newQuantity;
      } else {
        _cartItems.removeAt(index);
      }
      _updateTotal();
    });
  }

  void _updateTotal() {
    double total = 0.0;
    for (var item in _cartItems) {
      total += item.totalPrice;
    }
    _calculatedTotal = total;
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // COMMENTED OUT - Cart items validation (not sending items to database)
    // if (_cartItems.isEmpty) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(
    //       content: Text('Please add at least one product to cart'),
    //       backgroundColor: Colors.orange,
    //     ),
    //   );
    //   return;
    // }

    setState(() {
      _isLoading = true;
    });

    try {
      // COMMENTED OUT - Prepare items for the order (don't send cart items to database)
      // List<Map<String, dynamic>> items = [];
      // for (var item in _cartItems) {
      //   // Use the unit price stored in the cart item (from the price tier selected)
      //   final unitPrice = item.unitPrice;
      //   if (unitPrice <= 0) {
      //     throw Exception('${item.product.name}: Invalid price');
      //   }
      //   items.add({
      //     'product_id': item.product.id,
      //     'product_external_id': item.product.externalId,
      //     'product_name': item.product.name,
      //     'size_id': item.selectedSize?.id,
      //     'size_text': item.selectedSize?.sizeText ?? '',
      //     'quantity': item.quantity,
      //     'unit_price': unitPrice, // Use the unit price from cart item
      //   });
      // }

      // Create a single order with all items
      // Use phone number as customer name if customer name is empty
      final customerName = _customerNameController.text.trim().isNotEmpty
          ? _customerNameController.text.trim()
          : _customerPhoneController.text.trim().isNotEmpty
              ? _customerPhoneController.text.trim()
              : 'Customer';
      
      final orderData = {
        'party_name': _partyNameController.text,
        'station': _stationController.text,
        'price_category': _selectedPriceCategory,
        'customer_name': customerName,
        'customer_phone': _customerPhoneController.text,
        'customer_email': _customerEmailController.text.isEmpty
            ? null
            : _customerEmailController.text,
        'customer_address': _customerAddressController.text.isEmpty
            ? null
            : _customerAddressController.text,
        'payment_method': _selectedPaymentMethod,
        'transport_name': _transportNameController.text.trim().isEmpty ? null : _transportNameController.text.trim(),
        'created_by': _createdByController.text.trim().isEmpty ? null : _createdByController.text.trim(),
        'order_status': 'pending',
        'payment_status': 'pending',
        // COMMENTED OUT - Don't send cart items to database
        // 'items': items,
      };

      // Create order immediately with empty items list to get order number
      final orderDataWithItems = {
        ...orderData,
        'items': [], // Empty items list - items will be added later
      };
      
      final orderResult = await ApiService.createOrderWithMultipleItems(orderDataWithItems);
      final actualOrderNumber = (orderResult['order_number'] ?? 'PENDING').toString();
      
      // Save draft order to local storage
      await LocalStorageService.saveDraftOrder(
        orderNumber: actualOrderNumber,
        orderData: orderData,
        storedItems: [],
        designAllocations: {},
      );

      if (mounted) {
        // Navigate to order form products screen with actual order number
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OrderFormProductsScreen(
              partyName: _partyNameController.text,
              orderNumber: actualOrderNumber,
              orderData: orderData,
            ),
          ),
        );
        return;
      }
    } catch (e) {
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: const Color(0xFF1A1A1A)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Error: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _partyNameController.clear();
    _stationController.clear();
    _customerNameController.clear();
    _customerPhoneController.clear();
    _customerEmailController.clear();
    _customerAddressController.clear();
    _productSearchController.clear();
    _sizeTextController.clear();
    _quantityController.text = '1';
    _unitPriceController.clear();
    _transportNameController.clear();
    _createdByController.clear();
    _selectedPaymentMethod = null;
    _selectedProduct = null;
    _selectedSize = null;
    _selectedPriceTier = null;
    _selectedPriceCategory = null;
    _calculatedTotal = 0.0;
    _hasWhatsApp = false;
    _isVerifyingWhatsApp = false;
    _cartItems.clear();
  }

  // COMMENTED OUT - QR Scanner functionality
  // Future<void> _openQRScanner() async {
  //   if (kIsWeb) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('QR Scanner is not available on web'),
  //         backgroundColor: Colors.orange,
  //       ),
  //     );
  //     return;
  //   }

  //   // Request camera permission
  //   final status = await Permission.camera.status;
  //   if (status.isDenied) {
  //     final newStatus = await Permission.camera.request();
  //     if (newStatus.isDenied || newStatus.isPermanentlyDenied) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('Camera permission is required to scan QR codes'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //       return;
  //     }
  //   }

  //   if (status.isPermanentlyDenied) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: const Text(
  //             'Camera permission is permanently denied. Please enable it in app settings.'),
  //         backgroundColor: Colors.red.shade600,
  //         duration: const Duration(seconds: 4),
  //         action: SnackBarAction(
  //           label: 'Open Settings',
  //           textColor: Colors.white,
  //           onPressed: () => openAppSettings(),
  //         ),
  //       ),
  //     );
  //     return;
  //   }

  //   // With mobile_scanner v7, the controller is attached and started by the
  //   // MobileScanner widget itself. Once permissions are granted we just show
  //   // the scanner overlay and let the widget manage the camera lifecycle.
  //   setState(() {
  //     _showScanner = true;
  //     _lastScannedCode = null;
  //     _isScanning = false;
  //   });
  // }

  // COMMENTED OUT - Barcode handling functionality
  // Future<void> _handleBarcode(BarcodeCapture barcodeCapture) async {
  //   if (_isScanning) return;

  //   final List<Barcode> barcodes = barcodeCapture.barcodes;
  //   if (barcodes.isEmpty) return;

  //   final String? barcode = barcodes.first.rawValue;
  //   if (barcode == null || barcode.isEmpty) return;

  //   // Prevent duplicate scans - only block if same code was just scanned
  //   if (_lastScannedCode == barcode) return;

  //   // Set lastScannedCode immediately to prevent duplicate detection
  //   _lastScannedCode = barcode;

  //   setState(() {
  //     _isScanning = true;
  //   });

  //   try {
  //     final product = await ApiService.getProductByBarcode(barcode);

  //     if (mounted) {
  //       // Close scanner and return to order form
  //       setState(() {
  //         _isScanning = false;
  //         _showScanner = false; // Close the QR scanner screen
  //         _lastScannedCode = null;
  //       });

  //       // Stop the scanner
  //       try {
  //         await _scannerController.stop();
  //       } catch (e) {
  //         // Ignore errors when stopping
  //       }

  //       // Select the product
  //       await _selectProduct(product);

  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Product found: ${product.name}'),
  //           backgroundColor: const Color(0xFF10B981),
  //           duration: const Duration(seconds: 2),
  //         ),
  //       );
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       setState(() {
  //         _isScanning = false;
  //       });
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Product not found: ${e.toString()}'),
  //           backgroundColor: Colors.red.shade600,
  //           duration: const Duration(seconds: 2),
  //         ),
  //       );

  //       // Clear lastScannedCode on error to allow retry
  //       Future.delayed(const Duration(seconds: 1), () {
  //         if (mounted) {
  //           setState(() {
  //             _lastScannedCode = null;
  //           });
  //         }
  //       });
  //     }
  //   }
  // }

  // COMMENTED OUT - Price tier chip builder (part of Product Information section)
  // Widget _buildPriceTierChip(String tier, double price) {
  //   final isSelected = _selectedPriceTier == tier;
  //   return GestureDetector(
  //     onTap: () => _selectPriceTier(tier),
  //     child: Container(
  //       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  //       decoration: BoxDecoration(
  //         color: isSelected ? const Color(0xFFB8860B) : const Color(0xFF1A1A1A),
  //         borderRadius: BorderRadius.circular(10),
  //         border: Border.all(
  //           color: isSelected
  //               ? const Color(0xFFB8860B)
  //               : const Color(0xFFB8860B).withOpacity(0.5),
  //           width: isSelected ? 2 : 1,
  //         ),
  //       ),
  //       child: Column(
  //         mainAxisSize: MainAxisSize.min,
  //         children: [
  //           Text(
  //             tier,
  //             style: TextStyle(
  //               color: isSelected ? Colors.black : const Color(0xFFB8860B),
  //               fontWeight: FontWeight.bold,
  //               fontSize: 16,
  //             ),
  //           ),
  //           const SizedBox(height: 4),
  //           Text(
  //             '₹${price.toStringAsFixed(2)}',
  //             style: TextStyle(
  //               color: isSelected ? Colors.black : Colors.white,
  //               fontSize: 12,
  //               fontWeight: FontWeight.w600,
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    final isSmallScreen = screenSize.width < 360;

    // COMMENTED OUT - QR Scanner overlay UI
    // Show QR Scanner overlay if active
    // if (_showScanner && !kIsWeb) {
    //   return Scaffold(
    //     backgroundColor: Colors.black,
    //     body: Stack(
    //       children: [
    //         MobileScanner(
    //           controller: _scannerController,
    //           onDetect: _handleBarcode,
    //         ),
    //         // Overlay with instructions
    //         Container(
    //           decoration: BoxDecoration(
    //             gradient: LinearGradient(
    //               begin: Alignment.topCenter,
    //               end: Alignment.bottomCenter,
    //               colors: [
    //                 Colors.black.withOpacity(0.7),
    //                 Colors.transparent,
    //                 Colors.transparent,
    //                 Colors.black.withOpacity(0.7),
    //               ],
    //             ),
    //           ),
    //         ),
    //         // Top bar with close button
    //         SafeArea(
    //           child: Column(
    //             children: [
    //               Container(
    //                 padding: const EdgeInsets.all(16),
    //                 decoration: BoxDecoration(
    //                   gradient: const LinearGradient(
    //                     colors: [Color(0xFFB8860B), Color(0xFFC9A227)],
    //                   ),
    //                 ),
    //                 child: Row(
    //                   children: [
    //                     const Icon(Icons.qr_code_scanner,
    //                         color: Colors.black, size: 28),
    //                     const SizedBox(width: 12),
    //                     const Expanded(
    //                       child: Text(
    //                         'Scan QR Code',
    //                         style: TextStyle(
    //                           fontSize: 20,
    //                           fontWeight: FontWeight.bold,
    //                           color: Colors.black,
    //                         ),
    //                       ),
    //                     ),
    //                     IconButton(
    //                       icon: const Icon(Icons.close, color: Colors.black),
    //                       onPressed: () async {
    //                         try {
    //                           await _scannerController.stop();
    //                         } catch (e) {
    //                           // Ignore errors when stopping
    //                         }
    //                         setState(() {
    //                           _showScanner = false;
    //                           _lastScannedCode = null;
    //                         });
    //                       },
    //                     ),
    //                   ],
    //                 ),
    //               ),
    //               const Spacer(),
    //               // Scanning indicator
    //               if (_isScanning)
    //                 Container(
    //                   padding: const EdgeInsets.all(16),
    //                   margin: const EdgeInsets.all(16),
    //                   decoration: BoxDecoration(
    //                     color: const Color(0xFFB8860B).withOpacity(0.9),
    //                     borderRadius: BorderRadius.circular(12),
    //                   ),
    //                   child: const Row(
    //                     mainAxisAlignment: MainAxisAlignment.center,
    //                     children: [
    //                       SizedBox(
    //                         width: 20,
    //                         height: 20,
    //                         child: CircularProgressIndicator(
    //                           strokeWidth: 2,
    //                           color: Colors.black,
    //                         ),
    //                       ),
    //                       SizedBox(width: 12),
    //                       Text(
    //                         'Scanning...',
    //                         style: TextStyle(
    //                           color: Colors.black,
    //                           fontWeight: FontWeight.bold,
    //                         ),
    //                       ),
    //                     ],
    //                   ),
    //                 ),
    //               // Reset scanner button
    //               Container(
    //                 padding: const EdgeInsets.all(16),
    //                 margin: const EdgeInsets.all(16),
    //                 child: Row(
    //                   mainAxisAlignment: MainAxisAlignment.center,
    //                   children: [
    //                     ElevatedButton.icon(
    //                       onPressed: () {
    //                         // Just clear last scanned state; the camera
    //                         // continues running and MobileScanner will keep
    //                         // delivering frames.
    //                         setState(() {
    //                           _lastScannedCode = null;
    //                           _isScanning = false;
    //                         });
    //                         ScaffoldMessenger.of(context).showSnackBar(
    //                           const SnackBar(
    //                             content:
    //                                 Text('Scanner reset. Ready to scan again.'),
    //                             duration: Duration(seconds: 1),
    //                           ),
    //                         );
    //                       },
    //                       icon: const Icon(Icons.refresh_rounded,
    //                           color: Colors.black),
    //                       label: const Text(
    //                         'Reset Scanner',
    //                         style: TextStyle(
    //                           color: Colors.black,
    //                           fontWeight: FontWeight.bold,
    //                         ),
    //                       ),
    //                       style: ElevatedButton.styleFrom(
    //                         backgroundColor: const Color(0xFFB8860B),
    //                         padding: const EdgeInsets.symmetric(
    //                             horizontal: 20, vertical: 12),
    //                         shape: RoundedRectangleBorder(
    //                           borderRadius: BorderRadius.circular(12),
    //                         ),
    //                       ),
    //                     ),
    //                   ],
    //                 ),
    //               ),
    //               const SizedBox(height: 16),
    //             ],
    //           ),
    //         ),
    //       ],
    //     ),
    //   );
    // }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        // Return cart items when navigating back
        final cartItemsCopy = _cartItems.map((item) {
          return CartItem(
            product: item.product,
            selectedSize: item.selectedSize,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
          );
        }).toList();
        Navigator.pop(context, cartItemsCopy);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFFFFF),
              const Color(0xFFF8F8F8),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.shopping_cart_rounded,
                      color: const Color(0xFFB8860B),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order Form',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Create a new order',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF666666),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF1A1A1A)),
                      onPressed: () {
                        // Return cart items when closing
                        final cartItemsCopy = _cartItems.map((item) {
                          return CartItem(
                            product: item.product,
                            selectedSize: item.selectedSize,
                            quantity: item.quantity,
                            unitPrice: item.unitPrice,
                          );
                        }).toList();
                        Navigator.pop(context, cartItemsCopy);
                      },
                    ),
                  ],
                ),
              ),
              // Form Content
              Expanded(
                child: _isLoadingOptions
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFB8860B)),
                              strokeWidth: 3,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Loading options...',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _errorMessage != null && _partyOptions.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    size: 64,
                                    color: Color(0xFFFFCDD2),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton.icon(
                                    onPressed: _loadOptions,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFB8860B),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.all(isSmallScreen
                                ? 16
                                : isTablet
                                    ? 32
                                    : 24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Party Information Section
                                  _buildSectionHeader('Party Information',
                                      Icons.business_outlined),
                                  const SizedBox(height: 12),
                                  _buildTypeAheadField(
                                    controller: _partyNameController,
                                    label: 'Party Name *',
                                    hint: 'Select or enter party name',
                                    icon: Icons.business_outlined,
                                    options: _partyOptions,
                                    isLoading: _isLoadingPartyData,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Please enter party name';
                                      }
                                      return null;
                                    },
                                    onSelected: (value) {
                                      _loadPartyData(value);
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTypeAheadField(
                                    controller: _stationController,
                                    label: 'Station *',
                                    hint: 'Select or enter station name',
                                    icon: Icons.location_city_outlined,
                                    options: _stationOptions,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Please enter station';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  // Customer Information Section
                                  // _buildTypeAheadField(
                                  //   controller: _customerNameController,
                                  //   label: 'Customer Name *',
                                  //   hint: 'Select or enter customer name',
                                  //   icon: Icons.person_outline_rounded,
                                  //   options: _customerNameOptions,
                                  //   validator: (value) {
                                  //     if (value == null ||
                                  //         value.trim().isEmpty) {
                                  //       return 'Please enter customer name';
                                  //     }
                                  //     return null;
                                  //   },
                                  //   onSelected: (value) {
                                  //     _loadCustomerDataByName(value);
                                  //   },
                                  // ),
                                  // const SizedBox(height: 16),
                                  // Price Category Dropdown
                                  DropdownButtonFormField<String>(
                                    value: _selectedPriceCategory,
                                    style: const TextStyle(
                                      color: const Color(0xFF1A1A1A),
                                      fontSize: 16,
                                    ),
                                    decoration: _buildInputDecoration(
                                      label: 'Price Category',
                                      hint: 'Select price category',
                                      icon: Icons.category_outlined,
                                      suffix: const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: Color(0xFFB8860B)),
                                    ),
                                    dropdownColor: Colors.white,
                                    iconEnabledColor: const Color(0xFFB8860B),
                                    items: _priceCategories
                                        .map((category) => DropdownMenuItem(
                                              value: category,
                                              child: Text(
                                                category,
                                                style: const TextStyle(
                                                  color: const Color(0xFF1A1A1A),
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ))
                                        .toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedPriceCategory = value;
                                        // Auto-select price tier if size is already selected
                                        if (_selectedSize != null && value != null && value.isNotEmpty) {
                                          final category = value.toUpperCase().trim();
                                          double? price;
                                          
                                          switch (category) {
                                            case 'A':
                                              price = _selectedSize!.priceA;
                                              if (price != null) {
                                                _selectedPriceTier = 'A';
                                                _unitPriceController.text = price.toStringAsFixed(2);
                                              }
                                              break;
                                            case 'B':
                                              price = _selectedSize!.priceB;
                                              if (price != null) {
                                                _selectedPriceTier = 'B';
                                                _unitPriceController.text = price.toStringAsFixed(2);
                                              }
                                              break;
                                            case 'C':
                                              price = _selectedSize!.priceC;
                                              if (price != null) {
                                                _selectedPriceTier = 'C';
                                                _unitPriceController.text = price.toStringAsFixed(2);
                                              }
                                              break;
                                            case 'D':
                                              price = _selectedSize!.priceD;
                                              if (price != null) {
                                                _selectedPriceTier = 'D';
                                                _unitPriceController.text = price.toStringAsFixed(2);
                                              }
                                              break;
                                            case 'E':
                                              price = _selectedSize!.priceE;
                                              if (price != null) {
                                                _selectedPriceTier = 'E';
                                                _unitPriceController.text = price.toStringAsFixed(2);
                                              }
                                              break;
                                            case 'R':
                                              price = _selectedSize!.priceR;
                                              if (price != null) {
                                                _selectedPriceTier = 'R';
                                                _unitPriceController.text = price.toStringAsFixed(2);
                                              }
                                              break;
                                            default:
                                              // Try to find category in the string
                                              if (category.contains('A') && _selectedSize!.priceA != null) {
                                                _selectedPriceTier = 'A';
                                                _unitPriceController.text = _selectedSize!.priceA!.toStringAsFixed(2);
                                              } else if (category.contains('B') && _selectedSize!.priceB != null) {
                                                _selectedPriceTier = 'B';
                                                _unitPriceController.text = _selectedSize!.priceB!.toStringAsFixed(2);
                                              } else if (category.contains('C') && _selectedSize!.priceC != null) {
                                                _selectedPriceTier = 'C';
                                                _unitPriceController.text = _selectedSize!.priceC!.toStringAsFixed(2);
                                              } else if (category.contains('D') && _selectedSize!.priceD != null) {
                                                _selectedPriceTier = 'D';
                                                _unitPriceController.text = _selectedSize!.priceD!.toStringAsFixed(2);
                                              } else if (category.contains('E') && _selectedSize!.priceE != null) {
                                                _selectedPriceTier = 'E';
                                                _unitPriceController.text = _selectedSize!.priceE!.toStringAsFixed(2);
                                              } else if (category.contains('R') && _selectedSize!.priceR != null) {
                                                _selectedPriceTier = 'R';
                                                _unitPriceController.text = _selectedSize!.priceR!.toStringAsFixed(2);
                                              } else {
                                                _selectedPriceTier = null;
                                                _unitPriceController.text = '';
                                              }
                                          }
                                          _calculateTotal();
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTypeAheadFieldWithSuffix(
                                    controller: _customerPhoneController,
                                    label: 'Phone Number *',
                                    hint: 'Select or enter phone number',
                                    icon: Icons.phone_outlined,
                                    options: _customerPhoneOptions,
                                    keyboardType: TextInputType.phone,
                                    suffixIcon: _isVerifyingWhatsApp
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFFB8860B),
                                            ),
                                          )
                                        : _hasWhatsApp
                                            ? const Icon(Icons.chat,
                                                color: Color(0xFF25D366))
                                            : null,
                                    onChanged: (value) => _checkWhatsApp(value),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Please enter phone number';
                                      }
                                      // Clean and validate phone number
                                      final cleanPhone = value.replaceAll(
                                          RegExp(r'[^\d]'), '');
                                      if (cleanPhone.length < 10) {
                                        return 'Phone number must be at least 10 digits';
                                      }
                                      if (cleanPhone.length > 15) {
                                        return 'Phone number is too long';
                                      }
                                      return null;
                                    },
                                    onSelected: (value) {
                                      _loadCustomerDataByPhone(value);
                                    },
                                  ),
                                  if (_hasWhatsApp)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle,
                                              color: Color(0xFF25D366),
                                              size: 16),
                                          const SizedBox(width: 8),
                                          Text(
                                            'WhatsApp number verified',
                                            style: TextStyle(
                                              color: Colors.green.shade400,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                 // const SizedBox(height: ),
                                  // Product Information Section - COMMENTED OUT
                                  // _buildSectionHeader('Product Information',
                                  //     Icons.inventory_2_outlined),
                                  // const SizedBox(height: 12),
                                  // Row(
                                  //   children: [
                                  //     Expanded(
                                  //       child: TypeAheadField<Product>(
                                  //         controller: _productSearchController,
                                  //         builder:
                                  //             (context, controller, focusNode) {
                                  //           return TextField(
                                  //             controller: controller,
                                  //             focusNode: focusNode,
                                  //             style: const TextStyle(
                                  //                 color:
                                  //                     const Color(0xFF1A1A1A)),
                                  //             decoration: InputDecoration(
                                  //               labelText: 'Search Product *',
                                  //               labelStyle: const TextStyle(
                                  //                   color: const Color(
                                  //                       0xFF666666)),
                                  //               prefixIcon: const Icon(
                                  //                   Icons.search_rounded,
                                  //                   color: Color(0xFFB8860B)),
                                  //               border: OutlineInputBorder(
                                  //                 borderRadius:
                                  //                     BorderRadius.circular(12),
                                  //                 borderSide: BorderSide(
                                  //                     color:
                                  //                         Colors.grey.shade300),
                                  //               ),
                                  //               filled: true,
                                  //               fillColor:
                                  //                   const Color(0xFFF8F8F8),
                                  //               enabledBorder:
                                  //                   OutlineInputBorder(
                                  //                 borderRadius:
                                  //                     BorderRadius.circular(12),
                                  //                 borderSide: BorderSide(
                                  //                     color:
                                  //                         Colors.grey.shade300),
                                  //               ),
                                  //               focusedBorder:
                                  //                   OutlineInputBorder(
                                  //                 borderRadius:
                                  //                     BorderRadius.circular(12),
                                  //                 borderSide: const BorderSide(
                                  //                     color: Color(0xFFB8860B),
                                  //                     width: 2),
                                  //               ),
                                  //             ),
                                  //           );
                                  //         },
                                  //         suggestionsCallback: (pattern) async {
                                  //           return await _searchProducts(
                                  //               pattern);
                                  //         },
                                  //         itemBuilder:
                                  //             (context, Product product) {
                                  //           return ListTile(
                                  //             leading: const Icon(
                                  //                 Icons.inventory_2_outlined,
                                  //                 color: Color(0xFFB8860B)),
                                  //             title: Text(
                                  //               product.name ?? 'Product',
                                  //               style: const TextStyle(
                                  //                   color: const Color(
                                  //                       0xFF1A1A1A)),
                                  //             ),
                                  //             subtitle: Text(
                                  //               'ID: ${product.externalId ?? 'N/A'}',
                                  //               style: TextStyle(
                                  //                   color:
                                  //                       const Color(0xFF1A1A1A)
                                  //                           .withOpacity(0.7)),
                                  //             ),
                                  //             tileColor: Colors.white,
                                  //           );
                                  //         },
                                  //         onSelected: (Product product) {
                                  //           _selectProduct(product);
                                  //         },
                                  //       ),
                                  //     ),
                                  //     const SizedBox(width: 12),
                                  //     Container(
                                  //       decoration: BoxDecoration(
                                  //         borderRadius:
                                  //             BorderRadius.circular(12),
                                  //         border: Border.all(
                                  //           color: const Color(0xFFB8860B),
                                  //           width: 2,
                                  //         ),
                                  //         gradient: const LinearGradient(
                                  //           colors: [
                                  //             Color(0xFFB8860B),
                                  //             Color(0xFFC9A227)
                                  //           ],
                                  //         ),
                                  //       ),
                                  //       child: IconButton(
                                  //         icon: const Icon(
                                  //             Icons.qr_code_scanner,
                                  //             color: Colors.black),
                                  //         onPressed: _openQRScanner,
                                  //         tooltip: 'Scan QR Code',
                                  //         iconSize: 28,
                                  //       ),
                                  //     ),
                                  //   ],
                                  // ),
                                  // if (_selectedProduct != null) ...[
                                  //   const SizedBox(height: 16),
                                  //   Container(
                                  //     padding: const EdgeInsets.all(16),
                                  //     decoration: BoxDecoration(
                                  //       color: const Color(0xFFB8860B)
                                  //           .withOpacity(0.2),
                                  //       borderRadius: BorderRadius.circular(12),
                                  //       border: Border.all(
                                  //         color: const Color(0xFFB8860B)
                                  //             .withOpacity(0.5),
                                  //         width: 1,
                                  //       ),
                                  //     ),
                                  //     child: Column(
                                  //       crossAxisAlignment:
                                  //           CrossAxisAlignment.start,
                                  //       children: [
                                  //         Row(
                                  //           children: [
                                  //             const Icon(Icons.check_circle,
                                  //                 color: Color(0xFFB8860B)),
                                  //             const SizedBox(width: 12),
                                  //             Expanded(
                                  //               child: Text(
                                  //                 _selectedProduct!.name ??
                                  //                     'Product',
                                  //                 style: const TextStyle(
                                  //                   fontWeight: FontWeight.w600,
                                  //                   color:
                                  //                       const Color(0xFF1A1A1A),
                                  //                 ),
                                  //               ),
                                  //             ),
                                  //           ],
                                  //         ),
                                  //         if (_selectedProduct!.externalId !=
                                  //             null) ...[
                                  //           const SizedBox(height: 8),
                                  //           Text(
                                  //             'ID: ${_selectedProduct!.externalId}',
                                  //             style: TextStyle(
                                  //               color: const Color(0xFF1A1A1A)
                                  //                   .withOpacity(0.7),
                                  //               fontSize: 12,
                                  //             ),
                                  //           ),
                                  //         ],
                                  //       ],
                                  //     ),
                                  //   ),
                                  //   // Size Selection Dropdown
                                  //   if (_selectedProduct!.sizes != null &&
                                  //       _selectedProduct!
                                  //           .sizes!.isNotEmpty) ...[
                                  //     const SizedBox(height: 16),
                                  //     DropdownButtonFormField<ProductSize>(
                                  //       value: _selectedSize,
                                  //       style: const TextStyle(
                                  //         color: const Color(0xFF1A1A1A),
                                  //         fontSize: 16,
                                  //       ),
                                  //       decoration: _buildInputDecoration(
                                  //         label: 'Select Size *',
                                  //         hint: 'Choose a size',
                                  //         icon: Icons.straighten_outlined,
                                  //         suffix: const Icon(
                                  //             Icons.keyboard_arrow_down_rounded,
                                  //             color: Color(0xFFB8860B)),
                                  //       ),
                                  //       dropdownColor: Colors.white,
                                  //       iconEnabledColor:
                                  //           const Color(0xFFB8860B),
                                  //       items: _selectedProduct!.sizes!
                                  //           .where((size) =>
                                  //               size.isActive != false)
                                  //           .map((size) => DropdownMenuItem(
                                  //                 value: size,
                                  //                 child: Text(
                                  //                   size.sizeText ?? 'N/A',
                                  //                   style: const TextStyle(
                                  //                       color: const Color(
                                  //                           0xFF1A1A1A)),
                                  //                 ),
                                  //               ))
                                  //           .toList(),
                                  //       onChanged: (size) {
                                  //         if (size != null) {
                                  //           _selectSize(size);
                                  //         }
                                  //       },
                                  //       validator: (value) {
                                  //         if (value == null) {
                                  //           return 'Please select a size';
                                  //         }
                                  //         return null;
                                  //       },
                                  //     ),
                                  //     // Price Tier Selection - Only show the tier matching priceCategory
                                  //     if (_selectedSize != null) ...[
                                  //       const SizedBox(height: 16),
                                  //       if (_selectedPriceCategory != null && _selectedPriceCategory!.isNotEmpty) ...[
                                  //         Text(
                                  //           'Price Tier: ${_selectedPriceCategory!.toUpperCase()}',
                                  //           style: const TextStyle(
                                  //             color: const Color(0xFF1A1A1A),
                                  //             fontSize: 14,
                                  //             fontWeight: FontWeight.w600,
                                  //           ),
                                  //         ),
                                  //         const SizedBox(height: 8),
                                  //         // Only show the price tier chip matching the selected price category
                                  //         Builder(
                                  //           builder: (context) {
                                  //             final category = _selectedPriceCategory!.toUpperCase().trim();
                                  //             double? price;
                                  //             String? tier;
                                  //             
                                  //             switch (category) {
                                  //               case 'A':
                                  //                 price = _selectedSize!.priceA;
                                  //                 tier = 'A';
                                  //                 break;
                                  //               case 'B':
                                  //                 price = _selectedSize!.priceB;
                                  //                 tier = 'B';
                                  //                 break;
                                  //               case 'C':
                                  //                 price = _selectedSize!.priceC;
                                  //                 tier = 'C';
                                  //                 break;
                                  //               case 'D':
                                  //                 price = _selectedSize!.priceD;
                                  //                 tier = 'D';
                                  //                 break;
                                  //               case 'E':
                                  //                 price = _selectedSize!.priceE;
                                  //                 tier = 'E';
                                  //                 break;
                                  //               case 'R':
                                  //                 price = _selectedSize!.priceR;
                                  //                 tier = 'R';
                                  //                 break;
                                  //               default:
                                  //                 // Try to find category in the string
                                  //                 if (category.contains('A')) {
                                  //                   price = _selectedSize!.priceA;
                                  //                   tier = 'A';
                                  //                 } else if (category.contains('B')) {
                                  //                   price = _selectedSize!.priceB;
                                  //                   tier = 'B';
                                  //                 } else if (category.contains('C')) {
                                  //                   price = _selectedSize!.priceC;
                                  //                   tier = 'C';
                                  //                 } else if (category.contains('D')) {
                                  //                   price = _selectedSize!.priceD;
                                  //                   tier = 'D';
                                  //                 } else if (category.contains('E')) {
                                  //                   price = _selectedSize!.priceE;
                                  //                   tier = 'E';
                                  //                 } else if (category.contains('R')) {
                                  //                   price = _selectedSize!.priceR;
                                  //                   tier = 'R';
                                  //                 }
                                  //             }
                                  //             
                                  //             if (price != null && tier != null) {
                                  //               return _buildPriceTierChip(tier, price);
                                  //             } else {
                                  //               return Container(
                                  //                 padding: const EdgeInsets.all(12),
                                  //                 decoration: BoxDecoration(
                                  //                   color: Colors.orange.shade50,
                                  //                   borderRadius: BorderRadius.circular(10),
                                  //                   border: Border.all(
                                  //                     color: Colors.orange.shade300,
                                  //                     width: 1,
                                  //                   ),
                                  //                 ),
                                  //                 child: Row(
                                  //                   children: [
                                  //                     Icon(Icons.warning_amber_rounded,
                                  //                         color: Colors.orange.shade700,
                                  //                         size: 20),
                                  //                     const SizedBox(width: 8),
                                  //                     Expanded(
                                  //                       child: Text(
                                  //                         'Price tier ${_selectedPriceCategory!.toUpperCase()} not available for this size',
                                  //                         style: TextStyle(
                                  //                           color: Colors.orange.shade700,
                                  //                           fontSize: 12,
                                  //                         ),
                                  //                       ),
                                  //                     ),
                                  //                   ],
                                  //                 ),
                                  //               );
                                  //             }
                                  //           },
                                  //         ),
                                  //       ] else ...[
                                  //         const Text(
                                  //           'Select Price Tier:',
                                  //           style: TextStyle(
                                  //             color: const Color(0xFF1A1A1A),
                                  //             fontSize: 14,
                                  //             fontWeight: FontWeight.w600,
                                  //           ),
                                  //         ),
                                  //         const SizedBox(height: 8),
                                  //         Container(
                                  //           padding: const EdgeInsets.all(12),
                                  //           decoration: BoxDecoration(
                                  //             color: Colors.grey.shade100,
                                  //             borderRadius: BorderRadius.circular(10),
                                  //             border: Border.all(
                                  //               color: Colors.grey.shade300,
                                  //               width: 1,
                                  //             ),
                                  //           ),
                                  //           child: Row(
                                  //             children: [
                                  //               Icon(Icons.info_outline,
                                  //                   color: Colors.grey.shade600,
                                  //                   size: 20),
                                  //               const SizedBox(width: 8),
                                  //               Expanded(
                                  //                 child: Text(
                                  //                   'Please select a price category first',
                                  //                   style: TextStyle(
                                  //                     color: Colors.grey.shade700,
                                  //                     fontSize: 12,
                                  //                   ),
                                  //                 ),
                                  //               ),
                                  //             ],
                                  //           ),
                                  //         ),
                                  //       ],
                                  //     ],
                                  //   ] else ...[
                                  //     const SizedBox(height: 16),
                                  //     _buildTextField(
                                  //       controller: _sizeTextController,
                                  //       label: 'Size (Optional)',
                                  //       icon: Icons.straighten_outlined,
                                  //     ),
                                  //   ],
                                  //   const SizedBox(height: 16),
                                  //   Row(
                                  //     children: [
                                  //       Expanded(
                                  //         child: _buildTextField(
                                  //           controller: _quantityController,
                                  //           label: 'Quantity *',
                                  //           icon: Icons.numbers_outlined,
                                  //           keyboardType: TextInputType.number,
                                  //           onChanged: (_) => _calculateTotal(),
                                  //           validator: (value) {
                                  //             if (value == null ||
                                  //                 value.isEmpty) {
                                  //               return 'Required';
                                  //             }
                                  //             if (int.tryParse(value) == null ||
                                  //                 int.parse(value) < 1) {
                                  //               return 'Invalid';
                                  //             }
                                  //             return null;
                                  //           },
                                  //         ),
                                  //       ),
                                  //     ],
                                  //   ),
                                  // ],
                                  // const SizedBox(height: 16),
                                  // _buildTextField(
                                  //   controller: _unitPriceController,
                                  //   label: _cartItems.isNotEmpty
                                  //       ? 'Unit Price'
                                  //       : 'Unit Price *',
                                  //   icon: Icons.currency_rupee_rounded,
                                  //   keyboardType:
                                  //       TextInputType.numberWithOptions(
                                  //           decimal: true),
                                  //   onChanged: (_) => _calculateTotal(),
                                  //   validator: (value) {
                                  //     // If cart has items, unit price is not required
                                  //     if (_cartItems.isNotEmpty) {
                                  //       // Only validate if value is provided
                                  //       if (value != null && value.isNotEmpty) {
                                  //         if (double.tryParse(value) == null ||
                                  //             double.parse(value) <= 0) {
                                  //           return 'Please enter a valid price';
                                  //         }
                                  //       }
                                  //       return null; // Not required when cart has items
                                  //     }
                                  //     // If cart is empty, unit price is required
                                  //     if (value == null || value.isEmpty) {
                                  //       return 'Please enter unit price';
                                  //     }
                                  //     if (double.tryParse(value) == null ||
                                  //         double.parse(value) <= 0) {
                                  //       return 'Please enter a valid price';
                                  //     }
                                  //     return null;
                                  //   },
                                  // ),
                                  // if (_calculatedTotal > 0) ...[
                                  //   const SizedBox(height: 12),
                                  //   Container(
                                  //     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  //     decoration: BoxDecoration(
                                  //       color: const Color(0xFF1A1A1A),
                                  //       borderRadius: BorderRadius.circular(10),
                                  //     ),
                                  //     child: Row(
                                  //       mainAxisAlignment:
                                  //           MainAxisAlignment.spaceBetween,
                                  //       children: [
                                  //         const Text(
                                  //           'Item Total:',
                                  //           style: TextStyle(
                                  //             fontSize: 14,
                                  //             color: Colors.white,
                                  //             fontWeight: FontWeight.w600,
                                  //           ),
                                  //         ),
                                  //         Text(
                                  //           '₹${_calculatedTotal.toStringAsFixed(1)}',
                                  //           style: TextStyle(
                                  //             fontSize: 16,
                                  //             fontWeight: FontWeight.bold,
                                  //             color: Colors.white.withOpacity(0.9),
                                  //           ),
                                  //         ),
                                  //       ],
                                  //     ),
                                  //   ),
                                  //   const SizedBox(height: 12),
                                  //   ElevatedButton.icon(
                                  //     onPressed: _addToCart,
                                  //     icon: const Icon(Icons.add_shopping_cart,
                                  //         color: Colors.white),
                                  //     label: const Text(
                                  //       'Add to Cart',
                                  //       style: TextStyle(
                                  //         color: Colors.white,
                                  //         fontWeight: FontWeight.w600,
                                  //         fontSize: 14,
                                  //       ),
                                  //     ),
                                  //     style: ElevatedButton.styleFrom(
                                  //       backgroundColor:
                                  //           const Color(0xFFB8860B),
                                  //       padding: const EdgeInsets.symmetric(
                                  //           vertical: 14),
                                  //       shape: RoundedRectangleBorder(
                                  //         borderRadius:
                                  //             BorderRadius.circular(10),
                                  //       ),
                                  //     ),
                                  //   ),
                                  // ],
                                  const SizedBox(height: 24),
                                  // COMMENTED OUT - Cart Items Section
                                  // if (_cartItems.isNotEmpty) ...[
                                  //   _buildSectionHeader('Cart Items',
                                  //       Icons.shopping_cart_outlined),
                                  //   const SizedBox(height: 12),
                                  //   ...List.generate(_cartItems.length,
                                  //       (index) {
                                  //     return _buildCartItemCard(index);
                                  //   }),
                                  //   const SizedBox(height: 12),
                                  //   Container(
                                  //     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  //     decoration: BoxDecoration(
                                  //       color: const Color(0xFF1A1A1A),
                                  //       borderRadius: BorderRadius.circular(10),
                                  //     ),
                                  //     child: Row(
                                  //       mainAxisAlignment:
                                  //           MainAxisAlignment.spaceBetween,
                                  //       children: [
                                  //         Row(
                                  //           children: [
                                  //             Icon(
                                  //               Icons.receipt_long_outlined,
                                  //               color: Colors.white.withOpacity(0.9),
                                  //               size: 16,
                                  //             ),
                                  //             const SizedBox(width: 8),
                                  //             const Text(
                                  //               'Cart Total:',
                                  //               style: TextStyle(
                                  //                 fontSize: 14,
                                  //                 color: Colors.white,
                                  //                 fontWeight: FontWeight.w600,
                                  //               ),
                                  //             ),
                                  //           ],
                                  //         ),
                                  //         Text(
                                  //           '₹${_calculatedTotal.toStringAsFixed(1)}',
                                  //           style: TextStyle(
                                  //             fontSize: 16,
                                  //             fontWeight: FontWeight.bold,
                                  //             color: Colors.white.withOpacity(0.9),
                                  //           ),
                                  //         ),
                                  //       ],
                                  //     ),
                                  //   ),
                                  //   const SizedBox(height: 24),
                                  // ],
                                  // Payment Section
                                  // _buildSectionHeader('Payment Information',
                                  //     Icons.payment_outlined),
                                  // const SizedBox(height: 16),
                                  // DropdownButtonFormField<String>(
                                  //   value: _selectedPaymentMethod,
                                  //   style: const TextStyle(
                                  //     color: const Color(0xFF1A1A1A),
                                  //     fontSize: 16,
                                  //   ),
                                  //   decoration: _buildInputDecoration(
                                  //     label: 'Payment Method',
                                  //     hint: 'Select payment method',
                                  //     icon: Icons.payment_outlined,
                                  //     suffix: const Icon(
                                  //         Icons.keyboard_arrow_down_rounded,
                                  //         color: Color(0xFFB8860B)),
                                  //   ),
                                  //   dropdownColor: Colors.white,
                                  //   iconEnabledColor: const Color(0xFFB8860B),
                                  //   iconDisabledColor: Colors.grey.shade600,
                                  //   items: [
                                  //     'Cash',
                                  //     'Card',
                                  //     'UPI',
                                  //     'Bank Transfer',
                                  //     'Other'
                                  //   ]
                                  //       .map((method) => DropdownMenuItem(
                                  //             value: method,
                                  //             child: Text(
                                  //               method,
                                  //               style: const TextStyle(
                                  //                 color:
                                  //                     const Color(0xFF1A1A1A),
                                  //                 fontSize: 16,
                                  //               ),
                                  //             ),
                                  //           ))
                                  //       .toList(),
                                  //   selectedItemBuilder:
                                  //       (BuildContext context) {
                                  //     return [
                                  //       'Cash',
                                  //       'Card',
                                  //       'UPI',
                                  //       'Bank Transfer',
                                  //       'Other'
                                  //     ].map<Widget>((String method) {
                                  //       return Text(
                                  //         method,
                                  //         style: const TextStyle(
                                  //           color: const Color(0xFF1A1A1A),
                                  //           fontSize: 16,
                                  //         ),
                                  //       );
                                  //     }).toList();
                                  //   },
                                  //   onChanged: (value) {
                                  //     setState(() {
                                  //       _selectedPaymentMethod = value;
                                  //     });
                                  //   },
                                  // ),
                                  const SizedBox(height: 16),
                                  // Transport Name Field
                                  _buildTypeAheadField(
                                    controller: _transportNameController,
                                    label: 'Transport Name',
                                    hint: 'Select or enter transport name',
                                    icon: Icons.local_shipping_outlined,
                                    options: _transportNames,
                                    validator: (value) {
                                      return null; // Optional field
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  // Created By Field
                                  _buildTypeAheadField(
                                    controller: _createdByController,
                                    label: 'Created By',
                                    hint: 'Select or enter created by',
                                    icon: Icons.person_outline,
                                    options: _createdByOptions,
                                    validator: (value) {
                                      return null; // Optional field
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  // Submit Button
                                  ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () async {
                                            await _sendHiToWhatsApp();
                                            _submitOrder(); // keep your existing flow
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFFB8860B),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.5,
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.check_circle_outline,
                                                  size: 20),
                                              SizedBox(width: 8),
                                              Text(
                                                'Start',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildCartItemCard(int index) {
    final item = _cartItems[index];
    final product = item.product;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name ?? 'Product',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                if (item.selectedSize != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Size: ${item.selectedSize!.sizeText ?? 'N/A'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      onPressed: () => _updateCartItemQuantity(index, -1),
                      color: const Color(0xFFB8860B),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      onPressed: () => _updateCartItemQuantity(index, 1),
                      color: const Color(0xFFB8860B),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 18),
                onPressed: () => _removeFromCart(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 4),
              Text(
                '₹${item.totalPrice.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB8860B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFB8860B), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  final Color _fieldFillColor = const Color(0xFFFFFFFF);
  final Color _fieldBorderColor = const Color(0xFFE5E7EB);
  final Color _fieldFocusColor = const Color(0xFFB8860B);

  OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: 1.4),
      );

  Widget? _buildPrefixIcon(IconData? icon) {
    if (icon == null) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 6),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB8860B), Color(0xFFC9A227)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB8860B).withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.black, size: 20),
      ),
    );
  }

  Widget? _buildSuffixIcons({
    required TextEditingController controller,
    bool showClear = true,
    bool isLoading = false,
    Widget? custom,
    VoidCallback? onCleared,
  }) {
    final widgets = <Widget>[];
    if (custom != null) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: custom,
      ));
    }
    if (isLoading) {
      widgets.add(const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB8860B)),
        ),
      ));
    }
    if (showClear && controller.text.isNotEmpty) {
      widgets.add(IconButton(
        icon:
            const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
        onPressed: () {
          controller.clear();
          onCleared?.call();
          setState(() {});
        },
        splashRadius: 16,
      ));
    }
    if (widgets.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  InputDecoration _buildInputDecoration({
    required String label,
    String? hint,
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: _fieldFillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: const TextStyle(
        color: Color(0xFF6B7280),
        fontWeight: FontWeight.w600,
      ),
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
      prefixIcon: _buildPrefixIcon(icon),
      suffixIcon: suffix,
      border: _fieldBorder(_fieldBorderColor),
      enabledBorder: _fieldBorder(_fieldBorderColor),
      focusedBorder: _fieldBorder(_fieldFocusColor),
      errorBorder: _fieldBorder(const Color(0xFFEF4444)),
      focusedErrorBorder: _fieldBorder(const Color(0xFFEF4444)),
    );
  }

  Widget _buildTypeAheadField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required List<String> options,
    required String? Function(String?)? validator,
    bool isLoading = false,
    void Function(String)? onSelected,
  }) {
    return TypeAheadField<String>(
      controller: controller,
      builder: (context, textController, focusNode) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          validator: validator,
          style: const TextStyle(color: Color(0xFF0F172A)),
          decoration: _buildInputDecoration(
            label: label,
            hint: hint,
            icon: icon,
            suffix: _buildSuffixIcons(
              controller: textController,
              isLoading: isLoading,
            ),
          ),
          onChanged: (value) {
            setState(() {});
          },
          onFieldSubmitted: (value) {
            // When user presses enter/next, check if it matches an option and trigger callback
            if (onSelected != null && value.isNotEmpty) {
              final trimmedValue = value.trim();
              final exactMatch = options.firstWhere(
                (option) =>
                    option.trim().toLowerCase() == trimmedValue.toLowerCase(),
                orElse: () => '',
              );
              if (exactMatch.isNotEmpty) {
                onSelected(trimmedValue);
              }
            }
          },
        );
      },
      suggestionsCallback: (pattern) async {
        if (pattern.isEmpty) {
          return options;
        }
        return options
            .where((option) =>
                option.toLowerCase().contains(pattern.toLowerCase()))
            .toList();
      },
      itemBuilder: (context, suggestion) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB8860B), Color(0xFFC9A227)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: Colors.black,
                ),
              ),
              title: Text(
                suggestion,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
      onSelected: (suggestion) {
        controller.text = suggestion;
        setState(() {});
        onSelected?.call(suggestion);
      },
      hideOnEmpty: false,
      hideOnError: false,
      hideOnLoading: false,
      debounceDuration: const Duration(milliseconds: 300),
    );
  }

  Widget _buildTypeAheadFieldWithSuffix({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required List<String> options,
    required String? Function(String?)? validator,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    void Function(String)? onChanged,
    void Function(String)? onSelected,
  }) {
    return TypeAheadField<String>(
      controller: controller,
      builder: (context, textController, focusNode) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          keyboardType: keyboardType,
          validator: validator,
          onChanged: onChanged,
          style: const TextStyle(color: Color(0xFF0F172A)),
          decoration: _buildInputDecoration(
            label: label,
            hint: hint,
            icon: icon,
            suffix: _buildSuffixIcons(
              controller: textController,
              custom: suffixIcon,
              onCleared: () => onChanged?.call(''),
            ),
          ),
        );
      },
      suggestionsCallback: (pattern) async {
        if (pattern.isEmpty) {
          return options;
        }
        final filtered = options
            .where((option) =>
                option.toLowerCase().contains(pattern.toLowerCase()))
            .toList();
        return filtered;
      },
      itemBuilder: (context, suggestion) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB8860B), Color(0xFFC9A227)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: Colors.black,
                ),
              ),
              title: Text(
                suggestion,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
      onSelected: (suggestion) {
        controller.text = suggestion;
        setState(() {});
        if (onChanged != null) {
          onChanged(suggestion);
        }
        if (onSelected != null) {
          onSelected(suggestion);
        }
      },
      hideOnEmpty: false,
      hideOnError: false,
      hideOnLoading: false,
      debounceDuration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _loadCustomerDataByName(String customerName) async {
    if (customerName.trim().isEmpty) return;

    // Only auto-fill if phone field is empty
    if (_customerPhoneController.text.isNotEmpty) {
      return;
    }

    try {
      // Get customer phone from options that matches this name
      // We'll search through the options to find matching phone
      // For now, just try to find in the loaded options
      // In a real scenario, you might want to fetch from API
    } catch (e) {
    }
  }

  Future<void> _loadCustomerDataByPhone(String customerPhone) async {
    if (customerPhone.trim().isEmpty) return;

    // Only auto-fill if name field is empty
    if (_customerNameController.text.isNotEmpty) {
      return;
    }

    try {
      // Get customer name from options that matches this phone
      // We'll search through the options to find matching name
      // For now, just try to find in the loaded options
      // In a real scenario, you might want to fetch from API
    } catch (e) {
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool enabled = true,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(color: Color(0xFF0F172A)),
      decoration: _buildInputDecoration(
        label: label,
        icon: icon,
        suffix: suffixIcon,
      ).copyWith(
        fillColor: enabled ? _fieldFillColor : const Color(0xFFE5E7EB),
      ),
    );
  }

  Widget _buildOrderDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFB8860B).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: const Color(0xFFB8860B),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
