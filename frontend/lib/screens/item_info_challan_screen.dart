import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../models/challan.dart';
import '../models/product.dart';
import '../models/product_size.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import 'view_challan_screen.dart';
import 'challan_summary_screen.dart';

class ItemInfoChallanScreen extends StatefulWidget {
  final String partyName;
  final String stationName;
  final String transportName;
  final String? priceCategory;
  final List<ChallanItem> initialItems;
  final List<ChallanItem>? initialStoredItems;
  final String? draftChallanNumber; // Pass existing draft challan number (for backward compatibility)
  final int? challanId; // Real challan ID from database
  final String? challanNumber; // Real challan number from database

  const ItemInfoChallanScreen({
    super.key,
    required this.partyName,
    required this.stationName,
    required this.transportName,
    this.priceCategory,
    this.initialItems = const [],
    this.initialStoredItems,
    this.draftChallanNumber,
    this.challanId,
    this.challanNumber,
  });

  @override
  State<ItemInfoChallanScreen> createState() => _ItemInfoChallanScreenState();
}

class _ItemInfoChallanScreenState extends State<ItemInfoChallanScreen> {
  final List<ChallanItem> _items = [];
  List<ChallanItem> _storedItems = [];
  List<Product> _catalog = [];
  bool _isLoadingCatalog = false;
  bool _isSubmitting = false;
  final Map<int, TextEditingController> _quantityControllers = {};
  String? _draftChallanNumber;

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.initialItems);
    // Initialize stored items if provided
    if (widget.initialStoredItems != null) {
      _storedItems = widget.initialStoredItems!.map((item) => item.copyWith()).toList();
    }
    // Merge stored items with current items
    _mergeStoredItems();
    // Use provided draft challan number or find existing one or create new
    _draftChallanNumber = widget.draftChallanNumber;
    _initializeDraftChallanNumber();
    // Initialize quantity controllers for existing items
    for (var i = 0; i < _items.length; i++) {
      _quantityControllers[i] = TextEditingController(
        text: _items[i].quantity > 0 ? _items[i].quantity.toStringAsFixed(2) : '',
      );
    }
    _loadCatalog();
  }

  Future<void> _initializeDraftChallanNumber() async {
    // If real challan ID and number are provided, use them (priority)
    if (widget.challanId != null && widget.challanNumber != null) {
      if (mounted) {
        setState(() {
          _draftChallanNumber = widget.challanNumber;
        });
      }
      return;
    }
    
    // If draft challan number is already set (from widget), use it
    if (_draftChallanNumber != null && _draftChallanNumber!.isNotEmpty) {
      return;
    }

    // If no challan ID/number provided, create a real challan via API instead of draft
    try {
      final challanData = {
        'party_name': widget.partyName,
        'station_name': widget.stationName,
        'transport_name': widget.transportName,
        'price_category': widget.priceCategory,
        'status': 'draft',
        'items': [], // No items yet
      };

      final challan = await ApiService.createChallan(challanData);
      
        if (mounted) {
          setState(() {
          _draftChallanNumber = challan.challanNumber;
          });
      }
    } catch (e) {
      // If API call fails, show error but don't create draft
      print('Error creating challan: $e');
      if (mounted) {
        // Still need a fallback, but this should rarely happen
        setState(() {
          _draftChallanNumber = 'ERROR-${DateTime.now().millisecondsSinceEpoch}';
        });
      }
    }
  }

  // Helper function to get unique key for an item
  String _getItemKey(ChallanItem item) {
    return '${item.productId ?? 'null'}_${item.sizeId ?? 'null'}';
  }

  // Get new items (items in _items that are NOT in _storedItems)
  List<ChallanItem> get _newItems {
    if (_storedItems.isEmpty) return _items;
    final storedKeys = _storedItems.map((item) => _getItemKey(item)).toSet();
    return _items.where((item) => !storedKeys.contains(_getItemKey(item))).toList();
  }
  
  // Get previous items (stored items)
  List<ChallanItem> get _previousItems => _storedItems;

  // Don't merge stored items with current items - keep them separate
  // Stored items are preserved but not shown in the table (only new items are shown)
  void _mergeStoredItems() {
    // Do nothing - keep stored items separate from _items
    // This allows us to show only new items in the table
  }

  @override
  void dispose() {
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() => _isLoadingCatalog = true);
    try {
      final products = await ApiService.getAllProducts();
      if (!mounted) return;
      setState(() {
        _catalog = products;
        // Update prices for all items based on price category
        _updateItemPrices();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load catalogue: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingCatalog = false);
      }
    }
  }

  void _updateItemPrices() {
    // Update prices for all items based on the price category
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final product = _getProductForItem(item);
      if (product != null && product.sizes != null && product.sizes!.isNotEmpty) {
        ProductSize? size;
        if (item.sizeId != null) {
          try {
            size = product.sizes!.firstWhere(
              (s) => s.id == item.sizeId,
            );
          } catch (e) {
            size = product.sizes!.first;
          }
        } else {
          size = product.sizes!.first;
        }
        
        if (size != null) {
          final categoryPrice = _getPriceByCategory(size);
          final newPrice = categoryPrice ?? size.minPrice ?? item.unitPrice;
          if ((newPrice != item.unitPrice) && newPrice > 0) {
            _items[i] = ChallanItem(
              id: item.id,
              challanId: item.challanId,
              productId: item.productId,
              productName: item.productName,
              sizeId: size.id ?? item.sizeId,
              sizeText: size.sizeText ?? item.sizeText,
              quantity: item.quantity,
              unitPrice: newPrice,
              qrCode: item.qrCode,
            );
          }
        }
      }
    }
  }

  double get _totalAmount =>
      _items.fold(0, (sum, item) => sum + item.totalPrice);

  double get _totalQuantity =>
      _items.fold(0, (sum, item) => sum + item.quantity);

  String _getProductName() {
    if (_items.isEmpty) return 'Product';
    // Get product name from first item, extract base name
    final firstItem = _items.first;
    final productName = firstItem.productName;
    // Extract base product name (e.g., "MELODY T/C" from "MELODY T/C 40x60 in")
    final parts = productName.split(' ');
    if (parts.length >= 2) {
      return '${parts[0]} ${parts[1]}';
    }
    return productName;
  }

  String? _getProductCategory() {
    if (_items.isEmpty) return null;
    final firstItem = _items.first;
    if (firstItem.productId == null) return null;
    final product = _catalog.firstWhere(
      (p) => p.id == firstItem.productId,
      orElse: () => Product(),
    );
    return product.categoryName;
  }

  Product? _getProductForItem(ChallanItem item) {
    if (item.productId == null) return null;
    try {
      return _catalog.firstWhere(
        (p) => p.id == item.productId,
      );
    } catch (e) {
      return null;
    }
  }

  // Helper function to get price based on price category
  double? _getPriceByCategory(ProductSize? size) {
    if (size == null) return null;
    
    // If no price category is selected, use minPrice as fallback
    if (widget.priceCategory == null || widget.priceCategory!.isEmpty) {
      return size.minPrice;
    }
    
    // Map price category to price tier
    final category = widget.priceCategory!.toUpperCase().trim();
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

  void _updateQuantity(int index, String value) {
    final quantity = double.tryParse(value) ?? 0;
    setState(() {
      final item = _items[index];
      _items[index] = ChallanItem(
        id: item.id,
        challanId: item.challanId,
        productId: item.productId,
        productName: item.productName,
        sizeId: item.sizeId,
        sizeText: item.sizeText,
        quantity: quantity,
        unitPrice: item.unitPrice,
        qrCode: item.qrCode,
      );
    });
  }


  // Handle NEXT button - store current items and navigate back to add more products
  Future<void> _handleNext() async {
    // Get only new items (not stored items) with quantity > 0
    final newItemsWithQuantity = _newItems.where((item) => item.quantity > 0).toList();
    
    if (newItemsWithQuantity.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter quantity greater than 0 before proceeding'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Save new items to stored items - create deep copies to avoid reference issues
    // Also merge with existing stored items to preserve previously stored items
    final newStoredItems = newItemsWithQuantity.map((item) => item.copyWith()).toList();
    final existingStoredKeys = _storedItems.map((item) => _getItemKey(item)).toSet();
    
    // Add new items to stored items, but don't overwrite existing stored items
    final mergedStoredItems = <ChallanItem>[];
    mergedStoredItems.addAll(_storedItems);
    
    for (var newItem in newStoredItems) {
      final key = _getItemKey(newItem);
      if (!existingStoredKeys.contains(key)) {
        mergedStoredItems.add(newItem);
      } else {
        // Update existing stored item with new quantity
        final index = mergedStoredItems.indexWhere((item) => _getItemKey(item) == key);
        if (index != -1) {
          mergedStoredItems[index] = newItem;
        }
      }
    }
    
    setState(() {
      _storedItems = mergedStoredItems;
      // Remove new items from _items (they are now stored, so they won't show in table)
      final newItemKeys = newItemsWithQuantity.map((item) => _getItemKey(item)).toSet();
      _items.removeWhere((item) => newItemKeys.contains(_getItemKey(item)));
      // Rebuild controllers after removing items
      _rebuildControllers();
    });
    
    // Ensure draft challan number is initialized
    if (_draftChallanNumber == null || _draftChallanNumber!.isEmpty) {
      await _initializeDraftChallanNumber();
    }
    
    // Save draft challan to local storage before navigating
    if (_draftChallanNumber != null && _draftChallanNumber!.isNotEmpty) {
      final draftChallan = Challan(
        id: null,
        challanNumber: _draftChallanNumber!,
        partyName: widget.partyName,
        stationName: widget.stationName,
        transportName: widget.transportName,
        priceCategory: widget.priceCategory,
        status: 'draft',
        items: mergedStoredItems,
      );
      await LocalStorageService.saveDraftChallan(draftChallan);
    }
    
    // Navigate back to product selection screen with stored items
    if (!mounted) return;
    Navigator.pop(context, mergedStoredItems);
  }
  
  // Rebuild controllers map after removing items
  void _rebuildControllers() {
    final newControllers = <int, TextEditingController>{};
    for (int i = 0; i < _items.length; i++) {
      final oldController = _quantityControllers[i];
      if (oldController != null) {
        newControllers[i] = oldController;
      } else {
        newControllers[i] = TextEditingController(
          text: _items[i].quantity > 0 ? _items[i].quantity.toStringAsFixed(2) : '',
        );
      }
    }
    // Dispose removed controllers
    for (var entry in _quantityControllers.entries) {
      if (!newControllers.containsKey(entry.key)) {
        entry.value.dispose();
      }
    }
    _quantityControllers.clear();
    _quantityControllers.addAll(newControllers);
  }

  Future<void> _handleOk() async {
    // Get all items (including stored items)
    final allItems = <ChallanItem>[];
    allItems.addAll(_items);
    
    // Merge with stored items that aren't already in _items
    final currentKeys = _items.map((item) => _getItemKey(item)).toSet();
    for (var storedItem in _storedItems) {
      final key = _getItemKey(storedItem);
      if (!currentKeys.contains(key)) {
        allItems.add(storedItem);
      }
    }

    // Filter out items with zero or no quantity
    final itemsWithQuantity = allItems.where((item) => item.quantity > 0).toList();

    // Save to local storage before navigating (only items with quantity)
    final draftChallan = Challan(
      id: null,
      challanNumber: _draftChallanNumber!,
      partyName: widget.partyName,
      stationName: widget.stationName,
      transportName: widget.transportName,
      priceCategory: widget.priceCategory,
      status: 'draft',
      items: itemsWithQuantity,
    );
    await LocalStorageService.saveDraftChallan(draftChallan);

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChallanSummaryScreen(
          partyName: widget.partyName,
          stationName: widget.stationName,
          transportName: widget.transportName,
          priceCategory: widget.priceCategory,
          items: itemsWithQuantity, // Only send items with quantity > 0
          challanNumber: widget.challanNumber ?? _draftChallanNumber,
          challanId: widget.challanId,
        ),
      ),
    );
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
          'Deco Jewel',
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
        child: _isLoadingCatalog
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
                      'Loading product catalog...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBrandCategorySection(),
                          const SizedBox(height: 16),
                          _buildTableSection(),
                        ],
                      ),
                    ),
                  ),
                  _buildFooterButtons(),
                ],
              ),
      ),
    );
  }

  Widget _buildBrandCategorySection() {
    final challanNumber = widget.challanNumber ?? _draftChallanNumber ?? 'Not assigned';
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with title
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: Color(0xFFB8860B),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Challan Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: 0.3,
                ),
              ),
            ],
                ),
          const SizedBox(height: 20),
          
          // Vertical list with rows
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
                children: [
                _buildDetailRow('Challan Number', challanNumber),
                const SizedBox(height: 16),
                _buildDetailRow('Party Name', widget.partyName.isNotEmpty ? widget.partyName : 'Not specified'),
                const SizedBox(height: 16),
                _buildDetailRow('Station Name', widget.stationName),
                const SizedBox(height: 16),
                _buildDetailRow('Transport Name', widget.transportName.isNotEmpty ? widget.transportName : 'Not specified'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method for row with heading and data (matching view_challan_screen format)
  Widget _buildDetailRow(String heading, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              heading,
                    style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF666666),
              ),
                    ),
                  ),
          const SizedBox(width: 20),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: heading == 'Challan Number' 
                    ? const Color(0xFFB8860B)
                    : const Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableSection() {
    // Get only new items (not stored items) to show in table
    final newItems = _newItems;
    
    if (newItems.isEmpty && _previousItems.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No products added yet',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: Text(
                    'S.N.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Price',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Quantity',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Table Rows - Only show new items (not stored items)
          if (newItems.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.add_shopping_cart_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No new items added',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (_previousItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Previous items are stored and will be included when you click OK',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            ...newItems.asMap().entries.map((entry) {
            final item = entry.value;
              // Find the actual index in _items for this item
              final actualIndex = _items.indexWhere((i) => _getItemKey(i) == _getItemKey(item));
              return _buildTableRow(entry.key + 1, item, actualIndex >= 0 ? actualIndex : entry.key);
          }),
        ],
      ),
    );
  }

  Widget _buildTableRow(int serialNumber, ChallanItem item, int index) {
    // Initialize controller if not exists
    if (!_quantityControllers.containsKey(index)) {
      _quantityControllers[index] = TextEditingController(
        text: item.quantity > 0 ? item.quantity.toStringAsFixed(2) : '',
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            // Serial Number
            SizedBox(
              width: 50,
              child: Text(
                '$serialNumber',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            // Product Name with Size below
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                item.productName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A1A),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                  ),
                  if (item.sizeText != null && item.sizeText!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Size: ${item.sizeText}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Price
            Expanded(
              flex: 2,
              child: Text(
                '₹${item.unitPrice.toStringAsFixed(0)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
            // Quantity Input
            Expanded(
              flex: 2,
              child: Center(
                child: SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _quantityControllers[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: 'Enter Qnty',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(
                          color: Color(0xFFB8860B),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                    ),
                    onChanged: (value) {
                      _updateQuantity(index, value);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterButtons() {
    return Container(
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
      child: Row(
        children: [
          // CANCEL Button
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // NEXT Button
          Expanded(
            child: ElevatedButton(
              onPressed: _handleNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'NEXT',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // OK Button
          Expanded(
            child: ElevatedButton(
              onPressed: _handleOk,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB8860B), // App primary color
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFDF4E3),
                ),
                child: const Icon(
                  Icons.directions_bus_filled_rounded,
                  color: Color(0xFFB8860B),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Challan Header',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.business_rounded,
            'Party Name',
            widget.partyName.isNotEmpty ? widget.partyName : 'Not specified',
          ),
          _buildInfoRow(
            Icons.location_on_rounded,
            'Station',
            widget.stationName.isNotEmpty ? widget.stationName : 'Not specified',
          ),
          _buildInfoRow(
            Icons.local_shipping_rounded,
            'Transport',
            widget.transportName.isNotEmpty
                ? widget.transportName
                : 'Not specified',
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: Colors.grey.shade700,
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
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSummaryTile(
              'Total Items', _items.length.toString(), Icons.list),
          _buildSummaryTile(
            'Quantity',
            _totalQuantity.toStringAsFixed(2),
            Icons.scale_outlined,
          ),
          _buildSummaryTile(
            'Amount',
            '₹${_totalAmount.toStringAsFixed(2)}',
            Icons.currency_rupee,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTile(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF4E3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFFB8860B)),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildItemsSection() {
    if (_items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
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
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No products added yet',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the “Add Product” button to include items in this challan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Container(
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
        children: _items
            .asMap()
            .entries
            .map((entry) => _buildItemTile(entry.key, entry.value))
            .toList(),
      ),
    );
  }

  Widget _buildItemTile(int index, ChallanItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () {
                  setState(() {
                    _items.removeAt(index);
                  });
                },
              ),
            ],
          ),
          if (item.sizeText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                'Variant: ${item.sizeText}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Qty: ${item.quantity.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Rate: ₹${item.unitPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Total: ₹${item.totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB8860B),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
