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
  // Key = _getItemKey(item) so we can edit both stored and new items
  final Map<String, TextEditingController> _quantityControllers = {};
  final Map<String, FocusNode> _quantityFocusNodes = {};
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
    
    // Note: We keep stored items' quantities intact (they're preserved)
    // Items in _items that match stored items will show empty in the input field
    // but the stored quantity will be added when OK is clicked
    
    // Use provided draft challan number or find existing one or create new
    _draftChallanNumber = widget.draftChallanNumber;
    _initializeDraftChallanNumber();
    // Initialize quantity controllers for all items shown in table (stored + new)
    // IMPORTANT: Items from _items that match stored items should show EMPTY, not the stored quantity
    final storedKeysForControllers = _storedItems.map((item) => _getItemKey(item)).toSet();
    final itemKeys = _items.map((item) => _getItemKey(item)).toSet();
    
    // For stored items: show their quantities ONLY if they don't match any item in _items
    // (If they match, the item from _items will be shown with empty quantity instead)
    for (var item in _storedItems) {
      final key = _getItemKey(item);
      // Only create controller for stored items that DON'T match items in _items
      if (!itemKeys.contains(key) && !_quantityControllers.containsKey(key)) {
        _quantityControllers[key] = TextEditingController(
          text: item.quantity > 0 ? item.quantity.toStringAsFixed(2) : '',
        );
        _quantityFocusNodes[key] = FocusNode();
      }
    }
    
    // For new items (_items): if same product/size exists in stored items, start EMPTY (don't pre-fill)
    // Otherwise, show their quantity (usually 0 for new items)
    for (var item in _items) {
      final key = _getItemKey(item);
      final isSameAsStored = storedKeysForControllers.contains(key);
      
      // Always create/override controller for items in _items
      // If it matches a stored item, set to empty (user can add more)
      // Otherwise, use the item's quantity
      if (_quantityControllers.containsKey(key)) {
        // Controller exists (maybe from stored item) - override to empty if matches stored item
        if (isSameAsStored) {
          _quantityControllers[key]!.text = '';
        }
      } else {
        // Create new controller - empty if matches stored item, otherwise use item's quantity
        _quantityControllers[key] = TextEditingController(
          text: isSameAsStored ? '' : (item.quantity > 0 ? item.quantity.toStringAsFixed(2) : ''),
        );
        _quantityFocusNodes[key] = FocusNode();
      }
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
  
  // Get previous items (stored items) – shown in table with new items
  List<ChallanItem> get _previousItems => _storedItems;

  // All items (stored + new) for totals and submit
  List<ChallanItem> get _allDisplayItems => [..._previousItems, ..._newItems];

  // Product names currently in the new-items batch (for same-product filter)
  // Use _items directly to get all product names, not just _newItems
  Set<String> get _newItemsProductNames {
    final names = <String>{};
    for (final item in _items) {
      final n = item.productName.trim();
      if (n.isNotEmpty) names.add(n);
    }
    return names;
  }

  // Stored items that belong to the same product(s) as the current new items only
  List<ChallanItem> get _storedItemsSameProduct {
    if (_newItemsProductNames.isEmpty) return [];
    return _storedItems
        .where((s) => _newItemsProductNames.contains(s.productName.trim()))
        .toList();
  }

  // Table shows only same-product list: previous selected items for current product(s) + new items (no other products)
  // BUT: if a stored item matches an item in _items (same product+size), exclude the stored item so user can enter fresh quantity
  // Use _items directly (not _newItems) so all items are visible, but exclude stored items that match
  // Also: hide any rows whose price is 0 or less (don't show zero-price sizes in the table)
  List<ChallanItem> get _tableDisplayItems {
    final itemKeys = _items.map((item) => _getItemKey(item)).toSet();
    // Only include stored items that DON'T match any item in _items (by product+size)
    // This way, if same product+size is selected again, we show the item from _items (with empty qty) instead of stored item
    final filteredStoredItems = _storedItemsSameProduct
        .where((s) => !itemKeys.contains(_getItemKey(s)))
        .toList();
    // Use _items directly (all items from current selection) instead of _newItems
    final combined = [...filteredStoredItems, ..._items];
    // Filter out any items with zero or negative price from the table
    return combined.where((item) => (item.unitPrice) > 0).toList();
  }

  // Group by product name – same-product items only (stored + new for current product(s))
  Map<String, List<ChallanItem>> get _groupedDisplayItems {
    final map = <String, List<ChallanItem>>{};
    for (final item in _tableDisplayItems) {
      final name = item.productName.trim().isEmpty ? 'Other' : item.productName;
      map.putIfAbsent(name, () => []).add(item);
    }
    return map;
  }

  // Flat list for ListView.builder: section headers and rows, grouped by product category
  List<({bool isHeader, String? categoryName, ChallanItem? item, int serial, String? itemKey})> get _tableEntries {
    final list = <({bool isHeader, String? categoryName, ChallanItem? item, int serial, String? itemKey})>[];
    int serial = 0;
    for (final entry in _groupedDisplayItems.entries) {
      list.add((isHeader: true, categoryName: entry.key, item: null, serial: 0, itemKey: null));
      for (final item in entry.value) {
        serial++;
        list.add((isHeader: false, categoryName: null, item: item, serial: serial, itemKey: _getItemKey(item)));
      }
    }
    return list;
  }

  void _mergeStoredItems() {
    // Stored items are shown in table together with new items
  }

  @override
  void dispose() {
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    for (var node in _quantityFocusNodes.values) {
      node.dispose();
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
      _allDisplayItems.fold(0, (sum, item) => sum + item.totalPrice);

  double get _totalQuantity =>
      _allDisplayItems.fold(0, (sum, item) => sum + item.quantity);

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

  void _updateQuantityByKey(String itemKey, String value) {
    final quantity = double.tryParse(value) ?? 0;
    setState(() {
      // Check if this key exists in _items (current selection)
      // If it does, update _items only (don't update stored items)
      // This preserves original stored quantities
      final itemsIndex = _items.indexWhere((i) => _getItemKey(i) == itemKey);
      if (itemsIndex >= 0) {
        // Item exists in _items - update it (this is the current selection)
        final item = _items[itemsIndex];
        _items[itemsIndex] = ChallanItem(
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
      } else {
        // Item doesn't exist in _items - check stored items
        // Only update stored items if they're NOT in the current selection
        final storedIndex = _storedItems.indexWhere((i) => _getItemKey(i) == itemKey);
        if (storedIndex >= 0) {
          final item = _storedItems[storedIndex];
          _storedItems[storedIndex] = ChallanItem(
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
        }
      }
    });
  }


  // Handle NEXT button - store current items and navigate back to add more products
  Future<void> _handleNext() async {
    // Read quantities from controllers (user's actual input) for ALL displayed items
    // This ensures we capture what the user typed, regardless of whether it's in _storedItems or _items
    final controllerQuantities = <String, double>{};
    for (var entry in _quantityControllers.entries) {
      final key = entry.key;
      final controller = entry.value;
      final qtyText = controller.text.trim();
      final qty = double.tryParse(qtyText) ?? 0;
      if (qty > 0) {
        controllerQuantities[key] = qty;
      }
    }
    
    // Require at least one item with quantity > 0
    if (controllerQuantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter quantity greater than 0 before proceeding'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Start with existing stored items (preserve them)
    final mergedStoredItems = <ChallanItem>[];
    mergedStoredItems.addAll(_storedItems);

    // Add controller quantities as NEW separate items only when key is in _items (current product selection)
    // This ensures each entry becomes a separate line item, even if product+size matches stored items
    final itemKeysInCurrentSelection = _items.map((item) => _getItemKey(item)).toSet();
    for (var entry in controllerQuantities.entries) {
      final key = entry.key;
      final controllerQty = entry.value;
      final itemIndex = _items.indexWhere((i) => _getItemKey(i) == key);
      if (itemIndex >= 0) {
        // Key is in current product's _items – add as NEW separate item (don't update existing)
        final item = _items[itemIndex];
        mergedStoredItems.add(ChallanItem(
          id: item.id,
          challanId: item.challanId,
          productId: item.productId,
          productName: item.productName,
          sizeId: item.sizeId,
          sizeText: item.sizeText,
          quantity: controllerQty,
          unitPrice: item.unitPrice,
          qrCode: item.qrCode,
        ));
      }
      // If key is only in stored (not in _items), skip – stored items already added above
    }
    
    setState(() {
      _storedItems = mergedStoredItems;
      // Remove items from _items that were added to stored (by key matching controller entries)
      final addedKeys = controllerQuantities.keys.where((key) => itemKeysInCurrentSelection.contains(key)).toSet();
      _items.removeWhere((item) => addedKeys.contains(_getItemKey(item)));
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
  
  // Rebuild controllers and focus nodes: keep only for keys still in table (stored + new)
  void _rebuildControllers() {
    final currentKeys = _tableDisplayItems.map((item) => _getItemKey(item)).toSet();
    for (var key in _quantityControllers.keys.toList()) {
      if (!currentKeys.contains(key)) {
        _quantityControllers[key]?.dispose();
        _quantityControllers.remove(key);
        _quantityFocusNodes[key]?.dispose();
        _quantityFocusNodes.remove(key);
      }
    }
    for (var item in _tableDisplayItems) {
      final key = _getItemKey(item);
      if (!_quantityControllers.containsKey(key)) {
        _quantityControllers[key] = TextEditingController(
          text: item.quantity > 0 ? item.quantity.toStringAsFixed(2) : '',
        );
      }
      if (!_quantityFocusNodes.containsKey(key)) {
        _quantityFocusNodes[key] = FocusNode();
      }
    }
  }

  Future<void> _handleOk() async {
    // Read quantities from controllers (user's actual input) for ALL displayed items
    // This ensures we capture what the user typed, regardless of whether it's in _storedItems or _items
    final controllerQuantities = <String, double>{};
    for (var entry in _quantityControllers.entries) {
      final key = entry.key;
      final controller = entry.value;
      final qtyText = controller.text.trim();
      final qty = double.tryParse(qtyText) ?? 0;
      if (qty > 0) {
        controllerQuantities[key] = qty;
      }
    }
    
    // Get all items - create SEPARATE items for each entry (don't merge)
    // Strategy: Add stored items FIRST (oldest first), then new items from controller (so view shows serial order: 1st added 1st, 2nd added 2nd)
    final allItems = <ChallanItem>[];
    
    // Use original stored items from widget (preserve original quantities)
    // Don't use _storedItems as it may have been modified by _updateQuantityByKey
    final originalStoredItems = widget.initialStoredItems ?? [];
    
    // Track which keys have stored items (for logging)
    final storedItemKeys = originalStoredItems.map((s) => _getItemKey(s)).toSet();
    
    // FIRST: Add all stored items with their ORIGINAL quantities (never replace)
    // Order: 1st added = 1st, 2nd added = 2nd, etc.
    for (var storedItem in originalStoredItems) {
      allItems.add(storedItem);
    }
    
    // SECOND: Add controller quantities as NEW items only when key is in _items (current product)
    // When key is only in stored (different product screen), do NOT add again – would duplicate stored lines.
    for (var entry in controllerQuantities.entries) {
      final key = entry.key;
      final controllerQty = entry.value;
      final itemIndex = _items.indexWhere((i) => _getItemKey(i) == key);
      if (itemIndex >= 0) {
        // Key is in current product's _items – add as new item (same or different product/size)
        final item = _items[itemIndex];
        allItems.add(ChallanItem(
          id: item.id,
          challanId: item.challanId,
          productId: item.productId,
          productName: item.productName,
          sizeId: item.sizeId,
          sizeText: item.sizeText,
          quantity: controllerQty,
          unitPrice: item.unitPrice,
          qrCode: item.qrCode,
        ));
      }
      // If key is only in storedItemKeys (not in _items), skip – stored items already added above; adding again would duplicate.
    }

    // Filter out items with zero or no quantity
    final itemsWithQuantity = allItems.where((item) => item.quantity > 0).toList();

    // Save to local storage before navigating (full item list so draft shows all items in Old Challans)
    final draftChallan = Challan(
      id: widget.challanId,
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
          'DecoJewels',
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
            if (_isLoadingCatalog)
              LinearProgressIndicator(
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFB8860B)),
              ),
            Expanded(
              child: RepaintBoundary(
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: _buildBrandCategorySection(),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),
                          if (_tableDisplayItems.isEmpty)
                            SliverToBoxAdapter(child: _buildEmptyTableState())
                          else ...[
                            SliverToBoxAdapter(child: _buildTableSectionHeader()),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final entries = _tableEntries;
                                  if (index >= entries.length) return null;
                                  final e = entries[index];
                                  if (e.isHeader) {
                                    return _buildCategoryHeader(e.categoryName!);
                                  }
                                  final nextKey = index + 1 < entries.length && !entries[index + 1].isHeader
                                      ? entries[index + 1].itemKey
                                      : null;
                                  return RepaintBoundary(
                                    child: _buildTableRow(e.serial, e.item!, e.itemKey!, nextItemKey: nextKey),
                                  );
                                },
                                childCount: _tableEntries.length,
                              ),
                            ),
                          ],
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

  Widget _buildEmptyTableState() {
    final hasPrevious = _previousItems.isNotEmpty;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            hasPrevious ? 'No new products in this step' : 'No products added yet',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          if (hasPrevious) ...[
            const SizedBox(height: 8),
            Text(
              'Previous items are saved. Add more products above or tap OK to continue.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableSectionHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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
    );
  }

  Widget _buildCategoryHeader(String categoryName) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFB8860B).withOpacity(0.08),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.category_outlined, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Text(
            categoryName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(int serialNumber, ChallanItem item, String itemKey, {String? nextItemKey}) {
    // Controllers should already be initialized in initState
    // Just ensure focus node exists
    if (!_quantityFocusNodes.containsKey(itemKey)) {
      _quantityFocusNodes[itemKey] = FocusNode();
    }
    
    // Ensure controller exists as fallback (shouldn't happen, but safety check)
    if (!_quantityControllers.containsKey(itemKey)) {
      final storedKeys = _storedItems.map((s) => _getItemKey(s)).toSet();
      final isSameAsStored = storedKeys.contains(itemKey);
      _quantityControllers[itemKey] = TextEditingController(
        text: isSameAsStored ? '' : (item.quantity > 0 ? item.quantity.toStringAsFixed(2) : ''),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
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
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.sizeText != null && item.sizeText!.isNotEmpty)
                    Text(
                      item.sizeText!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1A1A1A),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      'No size',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
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
            Expanded(
              flex: 2,
              child: Center(
                child: SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _quantityControllers[itemKey] ?? TextEditingController(),
                    focusNode: _quantityFocusNodes[itemKey] ?? FocusNode(),
                    keyboardType: TextInputType.number,
                    textInputAction: nextItemKey != null ? TextInputAction.next : TextInputAction.done,
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
                      _updateQuantityByKey(itemKey, value);
                    },
                    onSubmitted: (_) {
                      if (nextItemKey != null && _quantityFocusNodes.containsKey(nextItemKey)) {
                        _quantityFocusNodes[nextItemKey]!.requestFocus();
                      } else {
                        FocusScope.of(context).unfocus();
                      }
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
