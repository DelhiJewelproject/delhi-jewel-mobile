import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../models/challan.dart';
import '../models/product.dart';
import '../models/product_size.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import 'item_info_challan_screen.dart';

class ChallanProductSelectionScreen extends StatefulWidget {
  final Challan challan;
  final List<ChallanItem>? initialStoredItems;

  const ChallanProductSelectionScreen({
    super.key,
    required this.challan,
    this.initialStoredItems,
  });

  @override
  State<ChallanProductSelectionScreen> createState() =>
      _ChallanProductSelectionScreenState();
}

class _ChallanProductSelectionScreenState
    extends State<ChallanProductSelectionScreen> {
  final TextEditingController _productController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<Product> _products = [];
  Product? _selectedProduct;
  bool _isLoadingProducts = false;
  String _currentSearchQuery = '';
  List<ChallanItem> _storedItems = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialStoredItems != null) {
      _storedItems = widget.initialStoredItems!.map((item) => item.copyWith()).toList();
    }
    _loadProducts();
  }

  @override
  void dispose() {
    _productController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final products = await ApiService.getAllProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _isLoadingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingProducts = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load products: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  List<Product> _getFilteredProducts(String searchQuery) {
    if (searchQuery.isEmpty) {
      return _products;
    }
    final search = searchQuery.toLowerCase();
    return _products
        .where((product) {
          final name = (product.name ?? '').toLowerCase();
          final externalId = product.externalId?.toString().toLowerCase() ?? '';
          final categoryName = (product.categoryName ?? '').toLowerCase();
          return name.contains(search) ||
              externalId.contains(search) ||
              categoryName.contains(search);
        })
        .toList();
  }

  // Helper function to get price based on price category
  double? _getPriceByCategory(ProductSize? size) {
    if (size == null) return null;
    
    // If no price category is selected, use minPrice as fallback
    if (widget.challan.priceCategory == null || widget.challan.priceCategory!.isEmpty) {
      return size.minPrice;
    }
    
    // Map price category to price tier
    final category = widget.challan.priceCategory!.toUpperCase().trim();
    switch (category) {
      case 'A':
        return size.priceA;
      case 'B':
        return size.priceB;
      case 'C':
        return size.priceC;
      case 'D':
        return size.priceD;
      case 'E':
        return size.priceE;
      case 'R':
        return size.priceR;
      default:
        // If category doesn't match, try to find it in the category string
        if (category.contains('A')) return size.priceA;
        if (category.contains('B')) return size.priceB;
        if (category.contains('C')) return size.priceC;
        if (category.contains('D')) return size.priceD;
        if (category.contains('E')) return size.priceE;
        if (category.contains('R')) return size.priceR;
        // Fallback to minPrice if category doesn't match
        return size.minPrice;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

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
          'Select Product',
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
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                // Challan Info Card
                Container(
                  padding: const EdgeInsets.all(20),
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
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFB8860B).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: Color(0xFFB8860B),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Selected Challan',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.challan.challanNumber,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                if (widget.challan.id != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID: ${widget.challan.id}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Product Selection Card
                Container(
                  padding: const EdgeInsets.all(20),
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
                            Icons.inventory_2_outlined,
                            color: Color(0xFFB8860B),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Select Product',
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
                      _isLoadingProducts
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFFB8860B),
                                  ),
                                ),
                              ),
                            )
                          : TypeAheadField<Product>(
                              controller: _productController,
                              builder: (context, controller, focusNode) {
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  onChanged: (value) {
                                    setState(() {
                                      _currentSearchQuery = value;
                                    });
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Search by name, ID, or category',
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
                                                _currentSearchQuery = '';
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
                              suggestionsCallback: (pattern) async {
                                setState(() {
                                  _currentSearchQuery = pattern;
                                });
                                if (pattern.isEmpty) {
                                  return _products.take(20).toList();
                                }
                                final search = pattern.toLowerCase();
                                final filtered = _products
                                    .where((product) {
                                      final name =
                                          (product.name ?? '').toLowerCase();
                                      final externalId = product.externalId
                                              ?.toString()
                                              .toLowerCase() ??
                                          '';
                                      final categoryName = (product.categoryName ?? '')
                                          .toLowerCase();
                                      return name.contains(search) ||
                                          externalId.contains(search) ||
                                          categoryName.contains(search);
                                    })
                                    .toList();
                                
                                // Return first 20 results
                                return filtered.take(20).toList();
                              },
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
                              hideOnEmpty: false,
                              hideOnError: false,
                              hideOnLoading: false,
                              debounceDuration: const Duration(milliseconds: 300),
                            ),
                    ],
                  ),
                ),
                    ],
                  ),
                ),
              ),
            ),
            // Next Button (fixed at bottom)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: ElevatedButton(
                  onPressed: (_selectedProduct != null || _currentSearchQuery.isNotEmpty) 
                      ? _handleNext 
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB8860B),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _selectedProduct != null 
                            ? 'Next' 
                            : _currentSearchQuery.isNotEmpty 
                                ? 'Next (${_getFilteredProducts(_currentSearchQuery).length} products)' 
                                : 'Next',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleNext() async {
    // Clear the text field and selected product
    setState(() {
      _productController.clear();
      _currentSearchQuery = '';
    });
    
    List<ChallanItem> challanItems = [];

    // If product is selected, create items for ALL sizes
    if (_selectedProduct != null) {
      if (_selectedProduct!.sizes != null && _selectedProduct!.sizes!.isNotEmpty) {
        // Create an item for each size
        for (var size in _selectedProduct!.sizes!) {
          final defaultPrice = _getPriceByCategory(size) ?? size.minPrice ?? 0;
      final challanItem = ChallanItem(
        productId: _selectedProduct!.id,
        productName: _selectedProduct!.name ?? 'Product',
            sizeId: size.id,
            sizeText: size.sizeText,
        quantity: 0,
        unitPrice: defaultPrice,
      );
      challanItems.add(challanItem);
        }
      } else {
        // If no sizes, create a single item
        final challanItem = ChallanItem(
          productId: _selectedProduct!.id,
          productName: _selectedProduct!.name ?? 'Product',
          sizeId: null,
          sizeText: null,
          quantity: 0,
          unitPrice: 0.0,
        );
        challanItems.add(challanItem);
      }
    } 
    // If search query exists but no product selected, create items for all matching products
    else if (_currentSearchQuery.isNotEmpty) {
      final filteredProducts = _getFilteredProducts(_currentSearchQuery);
      
      if (filteredProducts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No products found matching your search'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Create ChallanItems for ALL sizes of each matching product
      for (var product in filteredProducts) {
        if (product.sizes != null && product.sizes!.isNotEmpty) {
          // Create an item for each size
          for (var size in product.sizes!) {
            final defaultPrice = _getPriceByCategory(size) ?? size.minPrice ?? 0;
        final challanItem = ChallanItem(
          productId: product.id,
          productName: product.name ?? 'Product',
              sizeId: size.id,
              sizeText: size.sizeText,
          quantity: 0,
          unitPrice: defaultPrice,
        );
        challanItems.add(challanItem);
          }
        } else {
          // If no sizes, create a single item
          final challanItem = ChallanItem(
            productId: product.id,
            productName: product.name ?? 'Product',
            sizeId: null,
            sizeText: null,
            quantity: 0,
            unitPrice: 0.0,
          );
          challanItems.add(challanItem);
        }
      }
    } 
    // Otherwise, show error
    else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please search for a product or select one from the list'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check for existing draft challan number based on party/station/transport
    String? existingDraftNumber;
    try {
      final draftChallans = await LocalStorageService.getDraftChallans();
      final existingDraft = draftChallans.firstWhere(
        (c) =>
            c.partyName == widget.challan.partyName &&
            c.stationName == widget.challan.stationName &&
            (c.transportName ?? '') == (widget.challan.transportName ?? '') &&
            c.status == 'draft',
        orElse: () => Challan(
          id: null,
          challanNumber: '',
          partyName: '',
          stationName: '',
        ),
      );
      if (existingDraft.challanNumber.isNotEmpty) {
        existingDraftNumber = existingDraft.challanNumber;
      }
    } catch (e) {
      // Ignore errors
    }

    // Navigate to item info challan screen with all items (both new items and stored items)
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemInfoChallanScreen(
          partyName: widget.challan.partyName,
          stationName: widget.challan.stationName,
          transportName: widget.challan.transportName ?? '',
          priceCategory: widget.challan.priceCategory,
          initialItems: challanItems,
          initialStoredItems: _storedItems.isNotEmpty ? _storedItems : null,
          challanId: widget.challan.id,
          challanNumber: widget.challan.challanNumber,
          draftChallanNumber: existingDraftNumber, // Fallback for backward compatibility
        ),
      ),
    );
    
    // If stored items are returned from NEXT button, update stored items and allow user to add more
    if (result != null && result is List<ChallanItem> && mounted) {
      setState(() {
        _storedItems = (result as List<ChallanItem>).map((item) => item.copyWith()).toList();
        _selectedProduct = null;
        _productController.clear();
        _currentSearchQuery = '';
      });
      // User can now select another product to add more items
    }
  }
}

