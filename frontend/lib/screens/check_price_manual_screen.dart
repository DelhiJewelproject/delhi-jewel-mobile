import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import 'product_details_screen.dart';

class CheckPriceManualScreen extends StatefulWidget {
  final String? initialPriceCategory;
  
  const CheckPriceManualScreen({super.key, this.initialPriceCategory});

  @override
  State<CheckPriceManualScreen> createState() => _CheckPriceManualScreenState();
}

class _CheckPriceManualScreenState extends State<CheckPriceManualScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _productController = TextEditingController();

  List<Product> _products = [];
  List<String> _categories = [];
  String? _selectedCategory; // Product category for filtering
  String? _selectedPriceCategory; // Price category (A, B, C, D, E, R)
  Product? _selectedProduct;
  bool _isLoadingProducts = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPriceCategory != null) {
      _selectedPriceCategory = widget.initialPriceCategory;
    }
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoadingProducts = true;
    });
    try {
      final result = await ApiService.getAllProducts();
      final categories = result
          .map((product) => product.categoryName ?? '')
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _products = result;
        _categories = categories;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load products: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProducts = false;
        });
      }
    }
  }

  // Check if product has a price for the selected price category
  bool _productHasPriceCategory(Product product, String? priceCategory) {
    if (priceCategory == null || priceCategory.isEmpty) {
      return true; // Show all products if no price category selected
    }
    
    final sizes = product.sizes ?? [];
    if (sizes.isEmpty) return false;
    
    // Check if any size has a price for the selected price category
    return sizes.any((size) {
      switch (priceCategory.toUpperCase()) {
        case 'A':
          return size.priceA != null;
        case 'B':
          return size.priceB != null;
        case 'C':
          return size.priceC != null;
        case 'D':
          return size.priceD != null;
        case 'E':
          return size.priceE != null;
        case 'R':
          return size.priceR != null;
        default:
          return true;
      }
    });
  }

  List<Product> _productSuggestions(String pattern) {
    final search = pattern.toLowerCase();
    return _products
        .where((product) {
          // Filter by product category (if selected)
          final matchesCategory = _selectedCategory == null ||
              (_selectedCategory?.isEmpty ?? true) ||
              product.categoryName == _selectedCategory;
          
          // Filter by price category (if selected)
          final matchesPriceCategory = _productHasPriceCategory(product, _selectedPriceCategory);
          
          // Filter by search text
          final name = (product.name ?? '').toLowerCase();
          final externalId = product.externalId?.toString() ?? '';
          final matchesSearch = search.isEmpty ||
              name.contains(search) ||
              externalId.contains(search);
          
          return matchesCategory && matchesPriceCategory && matchesSearch;
        })
        .take(20)
        .toList();
  }

  Future<void> _openProductDetails() async {
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
      _isNavigating = true;
    });
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(
          product: _selectedProduct!,
          partyName: null,
          stationName: null,
          transportName: null,
          priceCategory: _selectedPriceCategory,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _isNavigating = false;
      });
    }
  }

  @override
  void dispose() {
    _productController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    final isLargeScreen = screenSize.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Check Price',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey.shade200,
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoadingProducts
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB8860B)),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Loading product catalogue...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isLargeScreen
                      ? (screenSize.width - 600) / 2
                      : isTablet
                          ? 48
                          : 20,
                  vertical: 24,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFB8860B),
                              Color(0xFFD4AF37),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFB8860B).withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.currency_rupee_rounded,
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
                                        'Instant Product Lookup',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Search live catalogue and view pricing',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Search Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.filter_list_rounded,
                                  color: Color(0xFFB8860B),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Filter by Category',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String?>(
                              value: _selectedCategory,
                              decoration: InputDecoration(
                                hintText: 'All Categories',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1.5,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFB8860B),
                                    width: 2,
                                  ),
                                ),
                                prefixIcon: Icon(
                                  Icons.category_outlined,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              isExpanded: true,
                              dropdownColor: Colors.white,
                              icon: Icon(
                                Icons.arrow_drop_down_rounded,
                                color: Colors.grey.shade600,
                                size: 28,
                              ),
                              iconSize: 28,
                              style: TextStyle(
                                fontSize: 15,
                                color: _selectedCategory == null
                                    ? Colors.grey.shade700
                                    : const Color(0xFF1A1A1A),
                                fontWeight: FontWeight.w500,
                              ),
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.category_outlined,
                                        size: 18,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'All Categories',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 15,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ..._categories.map(
                                  (category) => DropdownMenuItem<String?>(
                                    value: category,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.category_outlined,
                                          size: 18,
                                          color: const Color(0xFFB8860B),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            category,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF1A1A1A),
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedCategory = value;
                                  _selectedProduct = null;
                                  _productController.clear();
                                });
                              },
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                const Icon(
                                  Icons.search_rounded,
                                  color: Color(0xFFB8860B),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Search Product',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  '*',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TypeAheadField<Product>(
                              key: ValueKey('product_typeahead_${_selectedCategory ?? 'all'}_${_selectedPriceCategory ?? 'all'}'),
                              controller: _productController,
                              builder: (context, controller, focusNode) {
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  decoration: InputDecoration(
                                    hintText: 'Enter product name or ID',
                                    hintStyle: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 15,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                        width: 1.5,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                        width: 1.5,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFB8860B),
                                        width: 2,
                                      ),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.red.shade300,
                                        width: 1.5,
                                      ),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: Colors.red,
                                        width: 2,
                                      ),
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search_rounded,
                                      color: Colors.grey.shade600,
                                    ),
                                    suffixIcon: controller.text.isNotEmpty
                                        ? IconButton(
                                            icon: Icon(
                                              Icons.clear,
                                              size: 20,
                                              color: Colors.grey.shade400,
                                            ),
                                            onPressed: () {
                                              controller.clear();
                                              setState(() {
                                                _selectedProduct = null;
                                              });
                                            },
                                          )
                                        : null,
                                  ),
                                  validator: (value) {
                                    if ((value ?? '').isEmpty) {
                                      return 'Please select a product';
                                    }
                                    if (_selectedProduct == null) {
                                      return 'Please select from the suggestions';
                                    }
                                    return null;
                                  },
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                );
                              },
                              suggestionsCallback: (pattern) async =>
                                  _productSuggestions(pattern),
                              itemBuilder: (context, Product suggestion) {
                                return Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade200,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFB8860B)
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.inventory_2_outlined,
                                        size: 20,
                                        color: Color(0xFFB8860B),
                                      ),
                                    ),
                                    title: Text(
                                      suggestion.name ?? 'Unnamed Product',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A1A1A),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    subtitle: Text(
                                      [
                                        if (suggestion.categoryName != null)
                                          suggestion.categoryName,
                                        if (suggestion.externalId != null)
                                          'ID: ${suggestion.externalId}',
                                      ].whereType<String>().join(' • '),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    trailing: const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                      color: Color(0xFFB8860B),
                                    ),
                                    tileColor: Colors.white,
                                  ),
                                );
                              },
                              onSelected: (Product suggestion) {
                                setState(() {
                                  _selectedProduct = suggestion;
                                  _productController.text =
                                      suggestion.name ?? 'Product';
                                });
                              },
                              emptyBuilder: (context) => Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 48,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _products.isEmpty
                                          ? 'Catalogue is still loading...'
                                          : 'No products match your search',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                              hideOnEmpty: false,
                              hideOnError: false,
                              hideOnLoading: false,
                              debounceDuration: const Duration(milliseconds: 300),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed:
                                    _isNavigating ? null : _openProductDetails,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFB8860B),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  shadowColor: const Color(0xFFB8860B)
                                      .withValues(alpha: 0.3),
                                ),
                                child: _isNavigating
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'View Product Details',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDF4E3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFB8860B).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: const Color(0xFFB8860B),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Search by product name or external ID. Use category filter to narrow down results.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
