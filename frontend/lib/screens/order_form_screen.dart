import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/product.dart';

class OrderFormScreen extends StatefulWidget {
  const OrderFormScreen({super.key});

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
  final _notesController = TextEditingController();
  
  String? _selectedPaymentMethod;
  bool _isLoading = false;
  bool _isSearchingProducts = false;
  Product? _selectedProduct;
  List<Product> _productSuggestions = [];
  double _calculatedTotal = 0.0;
  bool _hasWhatsApp = false;

  @override
  void dispose() {
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
    _notesController.dispose();
    super.dispose();
  }

  void _calculateTotal() {
    final quantity = int.tryParse(_quantityController.text) ?? 1;
    final unitPrice = double.tryParse(_unitPriceController.text) ?? 0.0;
    setState(() {
      _calculatedTotal = quantity * unitPrice;
    });
  }

  Future<void> _checkWhatsApp(String phone) async {
    if (phone.isEmpty || phone.length < 10) {
      setState(() => _hasWhatsApp = false);
      return;
    }
    
    // Clean phone number (remove spaces, dashes, etc.)
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.length < 10) {
      setState(() => _hasWhatsApp = false);
      return;
    }
    
    // Try to open WhatsApp to check if number exists
    // Note: This is a best-effort check - we'll try to launch WhatsApp
    final whatsappUrl = 'https://wa.me/$cleanPhone';
    try {
      final uri = Uri.parse(whatsappUrl);
      if (await canLaunchUrl(uri)) {
        setState(() => _hasWhatsApp = true);
      } else {
        setState(() => _hasWhatsApp = false);
      }
    } catch (e) {
      setState(() => _hasWhatsApp = false);
    }
  }

  Future<void> _sendToWhatsApp(String orderNumber) async {
    final phone = _customerPhoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (phone.isEmpty) return;
    
    final message = '''
*Order Confirmation - Delhi Jewel*

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
    
    final whatsappUrl = 'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';
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

  Future<List<Product>> _searchProducts(String query) async {
    if (query.isEmpty) return [];
    
    try {
      final allProducts = await ApiService.getAllProducts();
      return allProducts.where((product) {
        final name = (product.name ?? '').toLowerCase();
        final externalId = product.externalId?.toString() ?? '';
        final searchQuery = query.toLowerCase();
        return name.contains(searchQuery) || externalId.contains(searchQuery);
      }).take(10).toList();
    } catch (e) {
      return [];
    }
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _productSearchController.text = product.name ?? '';
      if (product.sizes != null && product.sizes!.isNotEmpty) {
        final firstSize = product.sizes!.first;
        _sizeTextController.text = firstSize.sizeText ?? '';
        _unitPriceController.text = (firstSize.minPrice ?? 0.0).toStringAsFixed(2);
      }
      _calculateTotal();
    });
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a product'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final orderData = {
        'party_name': _partyNameController.text,
        'station': _stationController.text,
        'product_id': _selectedProduct!.id,
        'product_external_id': _selectedProduct!.externalId,
        'product_name': _selectedProduct!.name,
        'size_text': _sizeTextController.text,
        'quantity': int.tryParse(_quantityController.text) ?? 1,
        'unit_price': double.tryParse(_unitPriceController.text) ?? 0.0,
        'customer_name': _customerNameController.text,
        'customer_phone': _customerPhoneController.text,
        'customer_email': _customerEmailController.text.isEmpty ? null : _customerEmailController.text,
        'customer_address': _customerAddressController.text.isEmpty ? null : _customerAddressController.text,
        'payment_method': _selectedPaymentMethod,
        'notes': _notesController.text.isEmpty ? null : _notesController.text,
        'order_status': 'pending',
        'payment_status': 'pending',
      };

      final result = await ApiService.createOrder(orderData);
      final orderNumber = result['order_number'] ?? 'N/A';

      if (mounted) {
        // Show success dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2C5F7C), Color(0xFF1A3D52)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Order Placed!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2C5F7C), Color(0xFF1A3D52)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      orderNumber,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your order has been successfully placed!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                if (_hasWhatsApp) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _sendToWhatsApp(orderNumber);
                    },
                    icon: const Icon(Icons.chat, color: Colors.white),
                    label: const Text('Send to WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _resetForm();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
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
    _notesController.clear();
    _selectedPaymentMethod = null;
    _selectedProduct = null;
    _calculatedTotal = 0.0;
    _hasWhatsApp = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF5F7FA),
              Colors.white,
              const Color(0xFFF0F2F5),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2C5F7C), Color(0xFF1A3D52)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2C5F7C).withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shopping_cart_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order Form',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Create a new order',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Form Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Party Information Section
                        _buildSectionHeader('Party Information', Icons.business_outlined),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _partyNameController,
                          label: 'Party Name *',
                          icon: Icons.business_outlined,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter party name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _stationController,
                          label: 'Station *',
                          icon: Icons.location_city_outlined,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter station';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),
                        // Customer Information Section
                        _buildSectionHeader('Customer Information', Icons.person_outline_rounded),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _customerNameController,
                          label: 'Customer Name *',
                          icon: Icons.person_outline_rounded,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter customer name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _customerPhoneController,
                          label: 'Phone Number *',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          suffixIcon: _hasWhatsApp
                              ? const Icon(Icons.chat, color: Color(0xFF25D366))
                              : null,
                          onChanged: (value) => _checkWhatsApp(value),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter phone number';
                            }
                            if (value.length < 10) {
                              return 'Please enter a valid phone number';
                            }
                            return null;
                          },
                        ),
                        if (_hasWhatsApp)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF25D366), size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'WhatsApp available',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _customerEmailController,
                          label: 'Email (Optional)',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _customerAddressController,
                          label: 'Address (Optional)',
                          icon: Icons.location_on_outlined,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 32),
                        // Product Information Section
                        _buildSectionHeader('Product Information', Icons.inventory_2_outlined),
                        const SizedBox(height: 16),
                        TypeAheadField<Product>(
                          textFieldConfiguration: TextFieldConfiguration(
                            controller: _productSearchController,
                            decoration: InputDecoration(
                              labelText: 'Search Product *',
                              prefixIcon: const Icon(Icons.search_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF2C5F7C), width: 2),
                              ),
                            ),
                          ),
                          suggestionsCallback: (pattern) async {
                            return await _searchProducts(pattern);
                          },
                          itemBuilder: (context, Product product) {
                            return ListTile(
                              leading: const Icon(Icons.inventory_2_outlined, color: Color(0xFF2C5F7C)),
                              title: Text(product.name ?? 'Product'),
                              subtitle: Text('ID: ${product.externalId ?? 'N/A'}'),
                            );
                          },
                          onSuggestionSelected: (Product product) {
                            _selectProduct(product);
                          },
                        ),
                        if (_selectedProduct != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C5F7C).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF2C5F7C).withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF2C5F7C)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _selectedProduct!.name ?? 'Product',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _sizeTextController,
                                label: 'Size',
                                icon: Icons.straighten_outlined,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTextField(
                                controller: _quantityController,
                                label: 'Quantity *',
                                icon: Icons.numbers_outlined,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => _calculateTotal(),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Required';
                                  }
                                  if (int.tryParse(value) == null || int.parse(value) < 1) {
                                    return 'Invalid';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _unitPriceController,
                          label: 'Unit Price *',
                          icon: Icons.currency_rupee_rounded,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => _calculateTotal(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter unit price';
                            }
                            if (double.tryParse(value) == null || double.parse(value) <= 0) {
                              return 'Please enter a valid price';
                            }
                            return null;
                          },
                        ),
                        if (_calculatedTotal > 0) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2C5F7C), Color(0xFF1A3D52)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total Amount:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '₹${_calculatedTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                        // Payment Section
                        _buildSectionHeader('Payment Information', Icons.payment_outlined),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedPaymentMethod,
                          decoration: InputDecoration(
                            labelText: 'Payment Method',
                            prefixIcon: const Icon(Icons.payment_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: ['Cash', 'Card', 'UPI', 'Bank Transfer', 'Other']
                              .map((method) => DropdownMenuItem(
                                    value: method,
                                    child: Text(method),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedPaymentMethod = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _notesController,
                          label: 'Notes (Optional)',
                          icon: Icons.note_outlined,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 32),
                        // Submit Button
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2C5F7C).withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submitOrder,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2C5F7C),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline, size: 24),
                                      SizedBox(width: 12),
                                      Text(
                                        'Submit Order',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
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
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2C5F7C).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF2C5F7C), size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
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
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey.shade100,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2C5F7C), width: 2),
        ),
      ),
    );
  }
}
