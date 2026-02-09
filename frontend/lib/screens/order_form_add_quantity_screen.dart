import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../models/challan.dart';
import '../models/product.dart';
import '../models/product_size.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import 'order_challan_success_screen.dart';
import 'order_form_products_screen.dart';

// Wrapper class to return both products and stored items
class OrderFormReturnData {
  final List<Product> products;
  final List<ChallanItem> storedItems;
  final Map<String, Map<String, int>> designAllocations;

  OrderFormReturnData({
    required this.products,
    required this.storedItems,
    required this.designAllocations,
  });
}

class OrderFormAddQuantityScreen extends StatefulWidget {
  final String partyName;
  final String orderNumber;
  final Map<String, dynamic> orderData;
  final Product selectedProduct;
  final ProductSize? selectedSize;
  final List<Product>? initialProducts; // Products from order_form_products_screen
  final List<ChallanItem>? initialStoredItems; // Previously stored items from previous screen instance
  final Map<String, Map<String, int>>? initialDesignAllocations; // Design allocations from previous screen instance

  const OrderFormAddQuantityScreen({
    super.key,
    required this.partyName,
    required this.orderNumber,
    required this.orderData,
    required this.selectedProduct,
    this.selectedSize,
    this.initialProducts,
    this.initialStoredItems,
    this.initialDesignAllocations,
  });

  @override
  State<OrderFormAddQuantityScreen> createState() => _OrderFormAddQuantityScreenState();
}

class _OrderFormAddQuantityScreenState extends State<OrderFormAddQuantityScreen> {
  final List<ChallanItem> _items = [];
  List<ChallanItem> _storedItems = []; // Previously saved items when clicking NEXT
  List<Product> _catalog = []; // Products from order_form_products_screen
  bool _isSubmitting = false;
  final Map<int, TextEditingController> _quantityControllers = {};
  
  // Image selection state
  Set<int> _selectedProductIds = {}; // Track selected product IDs
  String _currentSection = 'A'; // 'A' for all products, 'B' for selected only
  int? _lastTappedProductId;
  DateTime? _lastTapTime;
  int? _selectedSizeId; // Track selected size for filtering
  
  // Design selection state for Melody product
  bool _isOptionA = false; // Default to Option B (manual selection) - Option A/B selector is hidden
  final List<String> _staticDesigns = ['D1', 'D2', 'D3']; // Static designs shown when product has no designs
  // Map<sizeKey, Map<design, quantity>> - temporary memory for each size
  final Map<String, Map<String, int>> _sizeDesignAllocations = {};
  // Map<sizeKey, Map<design, quantity>> - current UI state for each size
  final Map<String, Map<String, int>> _currentSizeDesignSelections = {};
  // Track which size is currently being edited (by item index)
  int? _currentlyEditingSizeIndex;
  // Map<sizeKey, TextEditingController> for design quantity inputs
  final Map<String, Map<String, TextEditingController>> _designQuantityControllers = {};
  
  // Debounce timers to avoid setState on every keystroke (reduces lag)
  Timer? _quantityDebounceTimer;
  int? _quantityDebounceIndex;
  Timer? _designQuantityDebounceTimer;
  String? _designDebounceSizeKey;
  String? _designDebounceDesign;
  
  // Flag to prevent multiple auto-restorations in build()
  bool _hasAutoRestoredInBuild = false;
  
  // Track which items are new (current session) vs previous (stored)
  // New items are those in _items that are NOT in _storedItems
  List<ChallanItem> get _newItems {
    if (_storedItems.isEmpty) return _items;
    final storedKeys = _storedItems.map((item) => _getItemKey(item)).toSet();
    return _items.where((item) => !storedKeys.contains(_getItemKey(item))).toList();
  }
  
  // Get previous items (stored items)
  List<ChallanItem> get _previousItems => _storedItems;

  @override
  void initState() {
    super.initState();
    // Initialize stored items from widget parameter
    if (widget.initialStoredItems != null) {
      _storedItems = widget.initialStoredItems!.map((item) => item.copyWith()).toList();
      print('=== INIT: Loaded ${_storedItems.length} stored items from parameter ===');
      for (var item in _storedItems) {
        print('Loaded stored: ${item.productName} - ${item.sizeText} - Qty: ${item.quantity}');
      }
    }
    
    // Initialize design allocations from widget parameter
    if (widget.initialDesignAllocations != null) {
      _sizeDesignAllocations.clear();
      _sizeDesignAllocations.addAll(
        widget.initialDesignAllocations!.map(
          (key, value) => MapEntry(key, Map<String, int>.from(value))
        )
      );
      print('=== INIT: Loaded ${_sizeDesignAllocations.length} design allocations from parameter ===');
      for (var entry in _sizeDesignAllocations.entries) {
        print('Loaded design allocations for ${entry.key}: ${entry.value}');
      }
    }
    
    // Initialize catalog with products from order_form_products_screen
    _catalog = widget.initialProducts ?? [widget.selectedProduct];
    // Ensure selected product is in catalog
    if (!_catalog.any((p) => p.id == widget.selectedProduct.id)) {
      _catalog.add(widget.selectedProduct);
    }
    _initializeItems();
    
    // Restore stored items after initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _storedItems.isNotEmpty) {
        _restoreStoredItemsToItems();
      }
    });
  }
  
  // Helper method to restore stored items to _items
  void _restoreStoredItemsToItems() {
    if (_storedItems.isEmpty) {
      print('No stored items to restore');
      return;
    }
    
    print('=== RESTORING STORED ITEMS IN INIT ===');
    print('Stored items count: ${_storedItems.length}');
    print('Current items count: ${_items.length}');
    
    setState(() {
      final storedKeys = _storedItems.map((item) => _getItemKey(item)).toSet();
      final currentKeys = _items.map((item) => _getItemKey(item)).toSet();
      final missingKeys = storedKeys.difference(currentKeys);
      
      print('Stored keys: $storedKeys');
      print('Current keys: $currentKeys');
      print('Missing keys: $missingKeys');
      
      if (missingKeys.isNotEmpty) {
        print('Found ${missingKeys.length} missing stored items - ADDING THEM');
        // Add missing stored items
        for (var storedItem in _storedItems) {
          final key = _getItemKey(storedItem);
          if (missingKeys.contains(key)) {
            _items.add(storedItem.copyWith());
            final index = _items.length - 1;
            if (!_quantityControllers.containsKey(index)) {
              _quantityControllers[index] = TextEditingController(
                text: storedItem.quantity > 0 ? storedItem.quantity.toStringAsFixed(2) : '',
              );
            }
            // Restore design allocations for this item if they exist
            final sizeKey = key;
            if (_sizeDesignAllocations.containsKey(sizeKey)) {
              _restoreSizeDesignAllocations(sizeKey);
              print('✓ Restored design allocations for $sizeKey: ${_sizeDesignAllocations[sizeKey]}');
            }
            
            print('✓ Restored: ${storedItem.productName} - ${storedItem.sizeText} - Qty: ${storedItem.quantity}');
          }
        }
        print('Total items after restoration: ${_items.length}');
      } else {
        print('All stored items already present in _items (${_items.length} items)');
        // Even if items are already present, restore design allocations
        for (var storedItem in _storedItems) {
          final key = _getItemKey(storedItem);
          final sizeKey = key;
          if (_sizeDesignAllocations.containsKey(sizeKey)) {
            _restoreSizeDesignAllocations(sizeKey);
            print('✓ Restored design allocations for existing item $sizeKey: ${_sizeDesignAllocations[sizeKey]}');
          }
        }
        // Double-check: verify all stored items have quantity > 0
        for (var storedItem in _storedItems) {
          final key = _getItemKey(storedItem);
          final existingItem = _items.firstWhere(
            (item) => _getItemKey(item) == key,
            orElse: () => ChallanItem(productName: 'NOT FOUND', quantity: 0),
          );
          if (existingItem.productName == 'NOT FOUND') {
            print('ERROR: Stored item not found in _items: ${storedItem.productName}');
          } else {
            print('✓ Verified: ${existingItem.productName} - ${existingItem.sizeText} - Qty: ${existingItem.quantity}');
          }
        }
      }
    });
  }

  // Helper function to get price based on price category
  double? _getPriceByCategory(ProductSize? size) {
    if (size == null) return null;
    
    final priceCategory = widget.orderData['price_category'] as String?;
    if (priceCategory == null || priceCategory.isEmpty) {
      return size.minPrice;
    }
    
    final category = priceCategory.toUpperCase().trim();
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
        if (category.contains('A')) return size.priceA;
        if (category.contains('B')) return size.priceB;
        if (category.contains('C')) return size.priceC;
        if (category.contains('D')) return size.priceD;
        if (category.contains('E')) return size.priceE;
        if (category.contains('R')) return size.priceR;
        return size.minPrice;
    }
  }

  // Get filtered products based on current tab and selected size
  List<Product> _getFilteredProducts() {
    List<Product> products;
    
    if (_currentSection == 'A') {
      // Tab A: Show all products
      products = _catalog;
    } else {
      // Tab B: Show only selected products
      products = _catalog.where((p) {
        final productId = p.id;
        return productId != null && _selectedProductIds.contains(productId);
      }).toList();
    }
    
    // Filter by selected size if any
    if (_selectedSizeId != null) {
      products = products.where((product) {
        return product.sizes?.any((size) => size.id == _selectedSizeId) ?? false;
      }).toList();
    }
    
    return products;
  }

  void _initializeItems() {
    // Convert selected product to ChallanItems - create one for EACH size (like challan_product_selection_screen)
    final product = widget.selectedProduct;
    
    // Add initial product to selected products
    if (product.id != null) {
      _selectedProductIds.add(product.id!);
    }
    
    // If product has sizes, create ChallanItem for each size
    if (product.sizes != null && product.sizes!.isNotEmpty) {
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
        
        _items.add(challanItem);
        _quantityControllers[_items.length - 1] = TextEditingController(text: '');
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
      
      _items.add(challanItem);
      _quantityControllers[0] = TextEditingController(text: '');
    }
  }
  
  // Toggle product selection on double click
  void _toggleProductSelection(Product product) {
    final productId = product.id;
    if (productId == null) return;
    
    setState(() {
      if (_selectedProductIds.contains(productId)) {
        _selectedProductIds.remove(productId);
        // Remove items for this product from _items
        _items.removeWhere((item) => item.productId == productId);
        // Rebuild controllers map
        _rebuildControllers();
      } else {
        _selectedProductIds.add(productId);
        // Add items for this product
        _addProductToItems(product);
      }
    });
  }
  
  // Add product to items list
  void _addProductToItems(Product product) {
    // Check if items for this product already exist (including stored items)
    final existingItems = _items.where((item) => item.productId == product.id).toList();
    if (existingItems.isNotEmpty) {
      // Items already exist, don't add duplicates
      return;
    }
    
    // Check if this product exists in stored items - if so, restore it instead of creating new
    final storedItemsForProduct = _storedItems.where((item) => item.productId == product.id).toList();
    if (storedItemsForProduct.isNotEmpty) {
      // Restore stored items for this product
      for (var storedItem in storedItemsForProduct) {
        final key = _getItemKey(storedItem);
        final exists = _items.any((item) => _getItemKey(item) == key);
        if (!exists) {
          _items.add(storedItem.copyWith());
          final index = _items.length - 1;
          _quantityControllers[index] = TextEditingController(
            text: storedItem.quantity > 0 ? storedItem.quantity.toStringAsFixed(2) : '',
          );
        }
      }
      return;
    }
    
    // Create new items for this product
    if (product.sizes != null && product.sizes!.isNotEmpty) {
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
        
        _items.add(challanItem);
        _quantityControllers[_items.length - 1] = TextEditingController(text: '');
      }
    } else {
      final challanItem = ChallanItem(
        productId: product.id,
        productName: product.name ?? 'Product',
        sizeId: null,
        sizeText: null,
        quantity: 0,
        unitPrice: 0.0,
      );
      
      _items.add(challanItem);
      _quantityControllers[_items.length - 1] = TextEditingController(text: '');
    }
    
    // Ensure stored items are still visible after adding new product
    _ensureStoredItemsVisible();
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
  
  // Open full screen image view
  void _showFullScreenImage(Product product) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                    ? Image.network(
                        product.imageUrl!,
                        fit: BoxFit.contain,
                        cacheWidth: 1024,
                        cacheHeight: 1024,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildFullScreenDemoImage(product);
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            padding: const EdgeInsets.all(32),
                            color: Colors.grey.shade800,
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          );
                        },
                      )
                    : _buildFullScreenDemoImage(product),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Build full-screen demo image (no text overlay)
  Widget _buildFullScreenDemoImage(Product product) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: _GeometricFabricPainter(),
        child: Container(),
      ),
    );
  }

  // Check if a product has its own designs (from product.designs field)
  bool _productHasDesigns(int? productId) {
    if (productId == null) return false;
    
    // First try to find in catalog
    try {
      final product = _catalog.firstWhere((p) => p.id == productId);
      return product.designs != null && product.designs!.isNotEmpty;
    } catch (e) {
      // If not in catalog, try to find in items
      try {
        final item = _items.firstWhere((item) => item.productId == productId);
        // Try to find product in catalog by name
        try {
          final product = _catalog.firstWhere((p) => p.name == item.productName);
          return product.designs != null && product.designs!.isNotEmpty;
        } catch (e) {
          return false;
        }
      } catch (e) {
        // Product not found, default to no designs
        return false;
      }
    }
  }
  
  // Get actual designs for a product
  List<String> _getProductDesigns(int? productId) {
    if (productId == null) return [];
    
    try {
      final product = _catalog.firstWhere((p) => p.id == productId);
      if (product.designs != null && product.designs!.isNotEmpty) {
        print('✓ Found ${product.designs!.length} designs for product ${productId}: ${product.designs!.join(", ")}');
        return product.designs!;
      } else {
        print('⚠ Product ${productId} has no designs (designs: ${product.designs})');
      }
    } catch (e) {
      print('⚠ Error finding product ${productId} in catalog: $e');
      // If not in catalog, try to find in items
      try {
        final item = _items.firstWhere((item) => item.productId == productId);
        // Try to find product in catalog by name
        try {
          final product = _catalog.firstWhere((p) => p.name == item.productName);
          if (product.designs != null && product.designs!.isNotEmpty) {
            print('✓ Found ${product.designs!.length} designs for product by name: ${product.designs!.join(", ")}');
            return product.designs!;
          }
        } catch (e) {
          print('⚠ Error finding product by name: $e');
          return [];
        }
      } catch (e) {
        print('⚠ Error finding item: $e');
        return [];
      }
    }
    return [];
  }
  
  // Get designs to show for a specific product
  // If product has designs, show those actual designs
  // Otherwise, show static designs (D1, D2, D3)
  List<String> _getDesignsToShow({int? productId}) {
    // If productId is provided, check that specific product
    // Otherwise, check the selected product (for backward compatibility)
    int? idToCheck = productId ?? widget.selectedProduct.id;
    
    if (idToCheck != null) {
      final productDesigns = _getProductDesigns(idToCheck);
      if (productDesigns.isNotEmpty) {
        // Product has its own designs - show those actual designs
        return productDesigns;
      }
    }
    
    // Product doesn't have its own designs - show static designs only (D1, D2, D3)
    return _staticDesigns;
  }
  
  // Get size key for a given item index
  String _getSizeKey(int itemIndex) {
    if (itemIndex >= _items.length) return '';
    final item = _items[itemIndex];
    return '${item.productId}_${item.sizeId ?? 'no_size'}';
  }
  
  // Initialize design controllers for a size
  void _initializeDesignControllersForSize(String sizeKey) {
    if (!_designQuantityControllers.containsKey(sizeKey)) {
      _designQuantityControllers[sizeKey] = {};
    }
    // Extract productId from sizeKey (format: "productId_sizeId")
    final productId = _extractProductIdFromSizeKey(sizeKey);
    final designsToShow = _getDesignsToShow(productId: productId);
    for (var design in designsToShow) {
      if (!_designQuantityControllers[sizeKey]!.containsKey(design)) {
        // Initialize with value from selections if it exists
        final currentQty = _currentSizeDesignSelections[sizeKey]?[design] ?? 0;
        _designQuantityControllers[sizeKey]![design] = TextEditingController(
          text: currentQty > 0 ? currentQty.toString() : '',
        );
      } else {
        // Update controller text if value exists in selections but controller is empty
        final currentQty = _currentSizeDesignSelections[sizeKey]?[design] ?? 0;
        final controller = _designQuantityControllers[sizeKey]![design]!;
        if (currentQty > 0 && (controller.text.isEmpty || controller.text == '0')) {
          controller.text = currentQty.toString();
        }
      }
    }
    // Initialize current selections if not exists
    if (!_currentSizeDesignSelections.containsKey(sizeKey)) {
      _currentSizeDesignSelections[sizeKey] = {};
    }
  }
  
  // Get or create design controller with proper initialization
  TextEditingController _getDesignController(String sizeKey, String design) {
    if (!_designQuantityControllers.containsKey(sizeKey)) {
      _designQuantityControllers[sizeKey] = {};
    }
    if (!_designQuantityControllers[sizeKey]!.containsKey(design)) {
      final currentQty = _currentSizeDesignSelections[sizeKey]?[design] ?? 0;
      _designQuantityControllers[sizeKey]![design] = TextEditingController(
        text: currentQty > 0 ? currentQty.toString() : '',
      );
    } else {
      // Sync controller with current selections
      final currentQty = _currentSizeDesignSelections[sizeKey]?[design] ?? 0;
      final controller = _designQuantityControllers[sizeKey]![design]!;
      // Only update if controller is empty or has different value
      final controllerValue = int.tryParse(controller.text) ?? 0;
      if (currentQty != controllerValue) {
        controller.text = currentQty > 0 ? currentQty.toString() : '';
      }
    }
    return _designQuantityControllers[sizeKey]![design]!;
  }
  
  // Extract productId from sizeKey (format: "productId_sizeId")
  int? _extractProductIdFromSizeKey(String sizeKey) {
    final parts = sizeKey.split('_');
    if (parts.isNotEmpty) {
      return int.tryParse(parts[0]);
    }
    return null;
  }
  
  // Initialize product-specific designs evenly for a size
  void _initializeProductDesignsForSize(String sizeKey, double totalQuantity) {
    if (totalQuantity <= 0) return;
    
    // Only initialize if product has its own designs
    final productId = _extractProductIdFromSizeKey(sizeKey);
    if (productId == null || !_productHasDesigns(productId)) return;
    
    // Only initialize if no designs are already set for this size
    final currentSelections = _currentSizeDesignSelections[sizeKey];
    if (currentSelections != null && currentSelections.isNotEmpty) {
      // Already has designs, don't override
      return;
    }
    
    // Get product-specific designs (excluding static designs)
    final designsToInitialize = _getDesignsToShow(productId: productId);
    if (designsToInitialize.isEmpty) return;
    
    final numDesigns = designsToInitialize.length;
    final quantityPerDesign = (totalQuantity / numDesigns).floor();
    final remainder = totalQuantity.toInt() % numDesigns;
    
    setState(() {
      _initializeDesignControllersForSize(sizeKey);
      
      for (int i = 0; i < designsToInitialize.length; i++) {
        final design = designsToInitialize[i];
        // Distribute quantity evenly:
        // - If remainder is 0: all get quantityPerDesign
        // - Otherwise: first 'remainder' designs get +1
        int extra = (i < remainder) ? 1 : 0;
        final qty = quantityPerDesign + extra;
        
        if (qty > 0) {
          _currentSizeDesignSelections[sizeKey]![design] = qty;
          final controller = _designQuantityControllers[sizeKey]?[design];
          if (controller != null) {
            controller.text = qty.toString();
          }
        }
      }
    });
  }
  
  // Initialize 3 designs with static data for a size
  void _initializeStaticDesignsForSize(String sizeKey, double totalQuantity) {
    if (totalQuantity <= 0) return;
    
    // Don't initialize static designs if product has its own designs
    final productId = _extractProductIdFromSizeKey(sizeKey);
    if (productId != null && _productHasDesigns(productId)) return;
    
    // Only initialize if no designs are already set for this size
    final currentSelections = _currentSizeDesignSelections[sizeKey];
    if (currentSelections != null && currentSelections.isNotEmpty) {
      // Already has designs, don't override
      return;
    }
    
    // Initialize with static designs (D1, D2, D3), distributing quantity evenly
    final designsToInitialize = _staticDesigns; // D1, D2, D3
    final quantityPerDesign = (totalQuantity / 3).floor();
    final remainder = totalQuantity.toInt() % 3;
    
    setState(() {
      _initializeDesignControllersForSize(sizeKey);
      
      for (int i = 0; i < designsToInitialize.length; i++) {
        final design = designsToInitialize[i];
        // Distribute quantity evenly:
        // - If remainder is 0: all get quantityPerDesign
        // - If remainder is 1: first design gets +1
        // - If remainder is 2: first and second designs get +1 each
        int extra = 0;
        if (remainder == 1 && i == 0) {
          extra = 1;
        } else if (remainder == 2) {
          if (i == 0 || i == 1) {
            extra = 1;
          }
        }
        final qty = quantityPerDesign + extra;
        
        if (qty > 0) {
          _currentSizeDesignSelections[sizeKey]![design] = qty;
          final controller = _designQuantityControllers[sizeKey]?[design];
          if (controller != null) {
            controller.text = qty.toString();
          }
        }
      }
    });
  }
  
  // Dispose design controllers for a size
  void _disposeDesignControllersForSize(String sizeKey) {
    final controllers = _designQuantityControllers[sizeKey];
    if (controllers != null) {
      for (var controller in controllers.values) {
        controller.dispose();
      }
      _designQuantityControllers.remove(sizeKey);
    }
  }
  
  // Save current design selections for a size to temporary memory
  void _saveSizeDesignAllocations(String sizeKey) {
    final currentSelections = _currentSizeDesignSelections[sizeKey];
    if (currentSelections != null) {
      // Filter out zero quantities
      final allocations = <String, int>{};
      currentSelections.forEach((design, qty) {
        if (qty > 0) {
          allocations[design] = qty;
        }
      });
      if (allocations.isNotEmpty) {
        _sizeDesignAllocations[sizeKey] = allocations;
      } else {
        _sizeDesignAllocations.remove(sizeKey);
      }
    }
  }
  
  // Restore saved design allocations for a size
  void _restoreSizeDesignAllocations(String sizeKey) {
    final saved = _sizeDesignAllocations[sizeKey];
    if (saved != null && saved.isNotEmpty) {
      // Initialize controllers first
      _initializeDesignControllersForSize(sizeKey);
      // Restore selections
      _currentSizeDesignSelections[sizeKey] = Map<String, int>.from(saved);
      // Update controllers with saved values
      saved.forEach((design, qty) {
        final controller = _designQuantityControllers[sizeKey]?[design];
        if (controller != null) {
          controller.text = qty.toString();
        } else {
          // If controller doesn't exist, create it
          if (!_designQuantityControllers.containsKey(sizeKey)) {
            _designQuantityControllers[sizeKey] = {};
          }
          _designQuantityControllers[sizeKey]![design] = TextEditingController(text: qty.toString());
        }
      });
      print('Restored design allocations for $sizeKey: $saved');
    } else {
      // Clear current selections
      _currentSizeDesignSelections[sizeKey] = {};
      _initializeDesignControllersForSize(sizeKey);
      // Clear all controllers
      final controllers = _designQuantityControllers[sizeKey];
      if (controllers != null) {
        for (var controller in controllers.values) {
          controller.text = '';
        }
      }
    }
  }
  
  // Clear current design selections for a size (but keep saved allocations)
  void _clearCurrentSizeDesignSelections(String sizeKey) {
    _currentSizeDesignSelections[sizeKey] = {};
    final controllers = _designQuantityControllers[sizeKey];
    if (controllers != null) {
      for (var controller in controllers.values) {
        controller.text = '';
      }
    }
  }
  
  // Check if design buttons should be enabled for a size
  bool _areDesignsEnabledForSize(int itemIndex) {
    if (itemIndex >= _items.length) return false;
    
    // Only enable in Tab B
    if (_currentSection != 'B') return false;
    
    // Designs are always enabled in Tab B (Option A/B selector is hidden, defaulting to manual selection)
    
    final item = _items[itemIndex];
    // Enable if quantity > 0 and this size is currently being edited
    return item.quantity > 0 && (_currentlyEditingSizeIndex == itemIndex || _currentlyEditingSizeIndex == null);
  }
  
  // Get total design quantity for a size
  int _getTotalDesignQuantityForSize(String sizeKey) {
    final selections = _currentSizeDesignSelections[sizeKey];
    if (selections == null) return 0;
    return selections.values.fold(0, (sum, qty) => sum + qty);
  }
  
  // Get total quantity (item quantity) for a given size key
  int _getTotalQuantityForSize(String sizeKey) {
    // Find the item with this size key
    final item = _items.firstWhere(
      (item) => _getItemKey(item) == sizeKey,
      orElse: () => ChallanItem(productName: 'Unknown', quantity: 0),
    );
    return item.quantity.toInt();
  }
  
  // Get unique key for an item
  String _getItemKey(ChallanItem item) {
    return '${item.productId ?? 'null'}_${item.sizeId ?? 'null'}';
  }
  
  // Ensure all stored items are visible in _items
  void _ensureStoredItemsVisible() {
    if (_storedItems.isEmpty) return;
    
    for (var storedItem in _storedItems) {
      final key = _getItemKey(storedItem);
      final exists = _items.any((item) => _getItemKey(item) == key);
      
      if (!exists) {
        // Add stored item to _items (create a copy to avoid reference issues)
        _items.add(storedItem.copyWith());
        final index = _items.length - 1;
        // Initialize controller if not exists
        if (!_quantityControllers.containsKey(index)) {
          _quantityControllers[index] = TextEditingController(
            text: storedItem.quantity > 0 ? storedItem.quantity.toStringAsFixed(2) : '',
          );
        }
      } else {
        // If exists, make sure quantity matches stored item
        final existingIndex = _items.indexWhere((item) => _getItemKey(item) == key);
        if (existingIndex != -1 && _items[existingIndex].quantity != storedItem.quantity) {
          _items[existingIndex] = storedItem.copyWith();
          if (_quantityControllers.containsKey(existingIndex)) {
            _quantityControllers[existingIndex]!.text = 
                storedItem.quantity > 0 ? storedItem.quantity.toStringAsFixed(2) : '';
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _quantityDebounceTimer?.cancel();
    _designQuantityDebounceTimer?.cancel();
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    // Dispose design controllers
    for (var sizeControllers in _designQuantityControllers.values) {
      for (var controller in sizeControllers.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  /// Debounced quantity update - avoids full rebuild on every keystroke.
  void _scheduleQuantityUpdate(int index, String value) {
    _quantityDebounceTimer?.cancel();
    _quantityDebounceIndex = index;
    _quantityDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final i = _quantityDebounceIndex;
      if (i == null) return;
      final currentValue = _quantityControllers[i]?.text ?? '';
      _updateQuantity(i, currentValue);
      _quantityDebounceTimer = null;
      _quantityDebounceIndex = null;
    });
  }

  /// Debounced design quantity update - avoids full rebuild on every keystroke.
  void _scheduleDesignQuantityUpdate(String sizeKey, String design, String value) {
    // Empty or would exceed total: update immediately (revert/snackbar or clear)
    if (value.isEmpty) {
      _updateDesignQuantity(sizeKey, design, value);
      return;
    }
    final qty = int.tryParse(value) ?? 0;
    if (qty > 0) {
      final totalQuantity = _getTotalQuantityForSize(sizeKey);
      final currentSelections = _currentSizeDesignSelections[sizeKey] ?? {};
      final currentSum = currentSelections.entries
          .where((entry) => entry.key != design)
          .fold(0, (sum, entry) => sum + entry.value);
      if ((currentSum + qty) > totalQuantity) {
        _updateDesignQuantity(sizeKey, design, value);
        return;
      }
    }
    _designQuantityDebounceTimer?.cancel();
    _designDebounceSizeKey = sizeKey;
    _designDebounceDesign = design;
    _designQuantityDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final sk = _designDebounceSizeKey;
      final d = _designDebounceDesign;
      if (sk == null || d == null) return;
      final currentValue = _designQuantityControllers[sk]?[d]?.text ?? '';
      _updateDesignQuantity(sk, d, currentValue);
      _designQuantityDebounceTimer = null;
      _designDebounceSizeKey = null;
      _designDebounceDesign = null;
    });
  }

  // Handle NEXT button - store current items and navigate to add more products
  Future<void> _handleNext() async {
    // Save all current design allocations before storing items
    _saveAllDesignAllocations();
    
    // Get only new items (not in stored items) with quantity > 0
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
      // Debug: Print stored items count
      print('Stored items count: ${_storedItems.length}');
      for (var item in _storedItems) {
        print('Stored: ${item.productName} - ${item.sizeText} - Qty: ${item.quantity}');
      }
      // Debug: Print design allocations
      print('Design allocations count: ${_sizeDesignAllocations.length}');
      for (var entry in _sizeDesignAllocations.entries) {
        print('Design allocations for $entry.key: $entry.value');
      }
    });
    
    // Save to local storage
    await _saveDraftOrderToLocalStorage();
    
    // Navigate to products screen to add more items
    await _updateCatalogFromProductsScreen();
  }
  
  // Update catalog when returning from order_form_products_screen
  Future<void> _updateCatalogFromProductsScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderFormProductsScreen(
          partyName: widget.partyName,
          orderNumber: widget.orderNumber,
          orderData: widget.orderData,
          initialProducts: _catalog, // Pass current products
          initialStoredItems: _storedItems, // Pass stored items to preserve them
          initialDesignAllocations: _sizeDesignAllocations, // Pass design allocations to preserve them
        ),
      ),
    );

    // Always restore stored items when returning, even if result is null
    print('=== NAVIGATION RETURNED ===');
    print('Result is null: ${result == null}');
    print('Stored items count: ${_storedItems.length}');
    print('Mounted: $mounted');
    
    // Force restoration even if mounted check fails
    if (!mounted) {
      print('WARNING: Widget not mounted, but attempting restoration anyway');
    }
    
    if (mounted) {
      setState(() {
        // Debug: Print stored items before restoration
        print('=== BEFORE RESTORATION ===');
        print('Stored items count: ${_storedItems.length}');
        print('Current items count: ${_items.length}');
        for (var stored in _storedItems) {
          print('Stored: ${stored.productName} - ${stored.sizeText} - Qty: ${stored.quantity}');
        }
        
        // Update catalog, stored items, and design allocations if returned
        if (result != null && result is OrderFormReturnData) {
          _catalog = result.products;
          _storedItems = result.storedItems.map((item) => item.copyWith()).toList();
          _sizeDesignAllocations.clear();
          _sizeDesignAllocations.addAll(
            result.designAllocations.map(
              (key, value) => MapEntry(key, Map<String, int>.from(value))
            )
          );
          print('Catalog updated with ${result.products.length} products');
          print('Stored items updated: ${_storedItems.length} items');
          print('Design allocations updated: ${_sizeDesignAllocations.length} entries');
        }
        
        // CRITICAL: Preserve quantities from current items before merging
        final currentItemQuantities = <String, double>{};
        for (var item in _items) {
          final key = _getItemKey(item);
          if (item.quantity > 0) {
            currentItemQuantities[key] = item.quantity;
          }
        }
        
        // Also preserve quantities from controllers (in case they're not synced to items yet)
        for (var entry in _quantityControllers.entries) {
          if (entry.key < _items.length) {
            final item = _items[entry.key];
            final key = _getItemKey(item);
            final controllerText = entry.value.text.trim();
            if (controllerText.isNotEmpty) {
              final quantity = double.tryParse(controllerText) ?? 0;
              if (quantity > 0) {
                currentItemQuantities[key] = quantity;
              }
            }
          }
        }
        
        // CRITICAL: Start with stored items - they take priority
        final itemsToRestore = <ChallanItem>[];
        final addedKeys = <String>{};
        
        // FIRST: Add all stored items (these have quantities and should be visible)
        for (var storedItem in _storedItems) {
          final key = _getItemKey(storedItem);
          if (!addedKeys.contains(key)) {
            itemsToRestore.add(storedItem.copyWith());
            addedKeys.add(key);
            print('Added stored item: ${storedItem.productName} - ${storedItem.sizeText} - Qty: ${storedItem.quantity}');
          }
        }
        
        // SECOND: Add current items that are NOT in stored items, preserving their quantities
        for (var item in _items) {
          final key = _getItemKey(item);
          if (!addedKeys.contains(key)) {
            // Preserve quantity if it exists in currentItemQuantities
            final preservedQuantity = currentItemQuantities[key] ?? item.quantity;
            final itemToAdd = preservedQuantity > 0 
                ? item.copyWith(quantity: preservedQuantity)
                : item;
            itemsToRestore.add(itemToAdd);
            addedKeys.add(key);
            print('Added current item: ${itemToAdd.productName} - ${itemToAdd.sizeText} - Qty: ${itemToAdd.quantity}');
          }
        }
        
        // Replace _items completely with restored list
        _items.clear();
        _items.addAll(itemsToRestore);
        
        // Rebuild ALL controllers from scratch, preserving quantities
        // Dispose old controllers first
        for (var controller in _quantityControllers.values) {
          controller.dispose();
        }
        _quantityControllers.clear();
        
        // Create new controllers for all items, using preserved quantities
        for (int i = 0; i < _items.length; i++) {
          final item = _items[i];
          final key = _getItemKey(item);
          
          // Check if we have a preserved quantity for this item
          double quantity = item.quantity;
          if (currentItemQuantities.containsKey(key)) {
            quantity = currentItemQuantities[key]!;
            // Update the item's quantity as well
            _items[i] = item.copyWith(quantity: quantity);
          }
          
          _quantityControllers[i] = TextEditingController(
            text: quantity > 0 ? quantity.toStringAsFixed(2) : '',
          );
          
          // Restore design allocations for this item if they exist
          final sizeKey = key;
          if (_sizeDesignAllocations.containsKey(sizeKey)) {
            _restoreSizeDesignAllocations(sizeKey);
            print('✓ Restored design allocations for $sizeKey: ${_sizeDesignAllocations[sizeKey]}');
          }
        }
        
        // Update selected product IDs based on items
        _selectedProductIds.clear();
        for (var item in _items) {
          if (item.productId != null) {
            _selectedProductIds.add(item.productId!);
          }
        }
        
        // Reset auto-restore flag to allow re-checking after navigation
        _hasAutoRestoredInBuild = false;
        
        // Debug: Print after restoration
        print('=== AFTER RESTORATION ===');
        print('Items count: ${_items.length}');
        for (var item in _items) {
          print('Item: ${item.productName} - ${item.sizeText} - Qty: ${item.quantity}');
        }
        print('========================');
      });
    } else {
      print('Widget not mounted, skipping restoration');
    }
  }

  void _updateQuantity(int index, String value) async {
    final quantity = double.tryParse(value) ?? 0;
    final sizeKey = _getSizeKey(index);
    final oldQuantity = _items[index].quantity;
    
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
      
      // Initialize design controllers when quantity > 0
      // Designs are always enabled (Option A/B selector is hidden)
      final shouldInitialize = quantity > 0;
      
      if (shouldInitialize) {
        _initializeDesignControllersForSize(sizeKey);
        if (!_currentSizeDesignSelections.containsKey(sizeKey)) {
          _currentSizeDesignSelections[sizeKey] = {};
        }
        
        // Always redistribute when quantity changes (if designs exist) or initialize if they don't
        final hasExistingDesigns = _currentSizeDesignSelections[sizeKey]?.isNotEmpty ?? false;
        if (hasExistingDesigns) {
          // Always redistribute when quantity changes, even if it's the same
          _redistributeDesignsForSize(sizeKey, quantity);
        } else {
          // Initialize designs for this size (only if no designs exist)
          final productId = item.productId;
          if (productId != null && _productHasDesigns(productId)) {
            // Product has its own designs - initialize them evenly
            _initializeProductDesignsForSize(sizeKey, quantity);
          } else {
            // Product doesn't have designs - initialize static designs
            _initializeStaticDesignsForSize(sizeKey, quantity);
          }
        }
      } else if (quantity == 0) {
        // Clear designs if quantity is set to 0
        _clearCurrentSizeDesignSelections(sizeKey);
      }
    });
    
    // Save to local storage after quantity update (debounced)
    Future.delayed(const Duration(milliseconds: 500), () {
      _saveDraftOrderToLocalStorage();
    });
  }
  
  // Redistribute designs evenly when total quantity changes
  void _redistributeDesignsForSize(String sizeKey, double totalQuantity) {
    if (totalQuantity <= 0) {
      _clearCurrentSizeDesignSelections(sizeKey);
      return;
    }
    
    // Extract productId from sizeKey (format: "productId_sizeId")
    final productId = _extractProductIdFromSizeKey(sizeKey);
    final designsToShow = _getDesignsToShow(productId: productId);
    if (designsToShow.isEmpty) return;
    
    // Use the designs that should be shown (not static designs if product has its own)
    final designsToRedistribute = designsToShow;
    
    // Ensure controllers are initialized for all designs
    _initializeDesignControllersForSize(sizeKey);
    
    // Clear existing selections and redistribute evenly
    _currentSizeDesignSelections[sizeKey] = {};
    
    final numDesigns = designsToRedistribute.length;
    if (numDesigns == 0) return;
    
    final quantityPerDesign = (totalQuantity / numDesigns).floor();
    final remainder = totalQuantity.toInt() % numDesigns;
    
    // Redistribute evenly:
    // - If remainder is 0: all get quantityPerDesign
    // - Otherwise: first 'remainder' designs get +1
    for (int i = 0; i < designsToRedistribute.length; i++) {
      final design = designsToRedistribute[i];
      int extra = (i < remainder) ? 1 : 0;
      final qty = quantityPerDesign + extra;
      
      if (qty > 0) {
        _currentSizeDesignSelections[sizeKey]![design] = qty;
        final controller = _designQuantityControllers[sizeKey]?[design];
        if (controller != null) {
          controller.text = qty.toString();
        }
      } else {
        _currentSizeDesignSelections[sizeKey]!.remove(design);
        final controller = _designQuantityControllers[sizeKey]?[design];
        if (controller != null) {
          controller.text = '';
        }
      }
    }
  }
  
  // Handle focus change on quantity field
  void _onQuantityFieldFocusChange(int index, bool hasFocus) {
    // Only enable design selection in Tab B
    if (_currentSection != 'B') return;
    
    // Designs are always enabled in Tab B (Option A/B selector is hidden)
    
    final sizeKey = _getSizeKey(index);
    final item = _items[index];
    
    if (!hasFocus) {
      // Lost focus - save current allocations and clear UI
      if (_currentlyEditingSizeIndex == index) {
        _saveSizeDesignAllocations(sizeKey);
        _clearCurrentSizeDesignSelections(sizeKey);
        _currentlyEditingSizeIndex = null;
      }
    } else {
      // Gained focus - initialize designs if quantity > 0
      if (item.quantity > 0) {
        _initializeDesignControllersForSize(sizeKey);
        if (!_currentSizeDesignSelections.containsKey(sizeKey)) {
          _currentSizeDesignSelections[sizeKey] = {};
        }
      }
      
      // Save previous size if any, then restore this size
      if (_currentlyEditingSizeIndex != null && _currentlyEditingSizeIndex != index) {
        final prevSizeKey = _getSizeKey(_currentlyEditingSizeIndex!);
        _saveSizeDesignAllocations(prevSizeKey);
        _clearCurrentSizeDesignSelections(prevSizeKey);
      }
      _currentlyEditingSizeIndex = index;
      
      // Restore allocations if quantity > 0
      if (item.quantity > 0) {
        _restoreSizeDesignAllocations(sizeKey);
      }
      
      // Trigger rebuild to show design selection
      setState(() {});
    }
  }
  
  // Check if a design quantity would exceed the total (for real-time validation)
  bool _wouldExceedTotal(String sizeKey, String design, int qty) {
    final totalQuantity = _getTotalQuantityForSize(sizeKey);
    final currentSelections = _currentSizeDesignSelections[sizeKey] ?? {};
    final currentSum = currentSelections.entries
        .where((entry) => entry.key != design)
        .fold(0, (sum, entry) => sum + entry.value);
    return (currentSum + qty) > totalQuantity;
  }
  
  // Get maximum allowed quantity for a design
  int _getMaxAllowedQuantity(String sizeKey, String design) {
    final totalQuantity = _getTotalQuantityForSize(sizeKey);
    final currentSelections = _currentSizeDesignSelections[sizeKey] ?? {};
    final currentSum = currentSelections.entries
        .where((entry) => entry.key != design)
        .fold(0, (sum, entry) => sum + entry.value);
    return totalQuantity - currentSum;
  }
  
  // Update design quantity for a specific size and design (called on each keystroke)
  void _updateDesignQuantity(String sizeKey, String design, String value) {
    // Only allow editing in Tab B
    if (_currentSection != 'B') return;
    
    final qty = int.tryParse(value) ?? 0;
    final totalQuantity = _getTotalQuantityForSize(sizeKey);
    
    // If value is empty, allow it (user is clearing)
    if (value.isEmpty) {
      setState(() {
        if (!_currentSizeDesignSelections.containsKey(sizeKey)) {
          _currentSizeDesignSelections[sizeKey] = {};
        }
        _currentSizeDesignSelections[sizeKey]!.remove(design);
      });
      return;
    }
    
    // Check if this would exceed the total
    final currentSelections = _currentSizeDesignSelections[sizeKey] ?? {};
    final currentSum = currentSelections.entries
        .where((entry) => entry.key != design)
        .fold(0, (sum, entry) => sum + entry.value);
    final wouldExceed = (currentSum + qty) > totalQuantity;
    
    if (wouldExceed && qty > 0) {
      // Don't allow values that exceed total - show error immediately
      final maxAllowed = totalQuantity - currentSum;
      final controller = _designQuantityControllers[sizeKey]?[design];
      
      // Revert to previous valid value or max allowed
      final previousQty = currentSelections[design] ?? 0;
      final revertValue = previousQty > maxAllowed ? maxAllowed : previousQty;
      
      if (controller != null) {
        // Revert the controller text to the previous valid value
        controller.text = revertValue > 0 ? revertValue.toString() : '';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot exceed total quantity! Maximum allowed: $maxAllowed (Total: $totalQuantity)'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 2),
        ),
      );
      
      // Update state with the reverted value
      setState(() {
        if (!_currentSizeDesignSelections.containsKey(sizeKey)) {
          _currentSizeDesignSelections[sizeKey] = {};
        }
        if (revertValue > 0) {
          _currentSizeDesignSelections[sizeKey]![design] = revertValue;
        } else {
          _currentSizeDesignSelections[sizeKey]!.remove(design);
        }
      });
      return;
    }
    
    setState(() {
      if (!_currentSizeDesignSelections.containsKey(sizeKey)) {
        _currentSizeDesignSelections[sizeKey] = {};
      }
      if (qty > 0) {
        _currentSizeDesignSelections[sizeKey]![design] = qty;
      } else {
        _currentSizeDesignSelections[sizeKey]!.remove(design);
      }
    });
  }
  
  // Validate and cap design quantity when field loses focus
  void _validateDesignQuantity(String sizeKey, String design) {
    final controller = _designQuantityControllers[sizeKey]?[design];
    if (controller == null) return;
    
    final value = controller.text.trim();
    if (value.isEmpty) {
      setState(() {
        _currentSizeDesignSelections[sizeKey]?.remove(design);
      });
      return;
    }
    
    final qty = int.tryParse(value) ?? 0;
    final totalQuantity = _getTotalQuantityForSize(sizeKey);
    
    // Calculate current sum of all other designs (excluding the one being validated)
    final currentSelections = _currentSizeDesignSelections[sizeKey] ?? {};
    final currentSum = currentSelections.entries
        .where((entry) => entry.key != design)
        .fold(0, (sum, entry) => sum + entry.value);
    
    // Calculate maximum allowed quantity for this design
    final maxAllowed = totalQuantity - currentSum;
    
    // Cap the quantity at the maximum allowed
    final finalQty = qty > maxAllowed ? maxAllowed : (qty < 0 ? 0 : qty);
    
    setState(() {
      if (finalQty > 0) {
        _currentSizeDesignSelections[sizeKey]![design] = finalQty;
        // Update controller text if it was capped
        if (qty > maxAllowed) {
          controller.text = finalQty.toString();
          // Show a snackbar warning
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Maximum allowed quantity for this design is $maxAllowed (Total: $totalQuantity)'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        _currentSizeDesignSelections[sizeKey]!.remove(design);
        controller.text = '';
      }
    });
  }

  Future<void> _openItemDialog({ChallanItem? item, int? index}) async {
    final result = await showDialog<ChallanItem>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _ChallanItemDialog(
          catalog: _catalog,
          initialItem: item,
          priceCategory: widget.orderData['price_category'] as String?,
        );
      },
    );

    if (result != null) {
      setState(() {
        if (index != null) {
          _items[index] = result;
          // Update controller for existing item
          if (_quantityControllers.containsKey(index)) {
            _quantityControllers[index]!.text = 
                result.quantity > 0 ? result.quantity.toStringAsFixed(2) : '';
          } else {
            _quantityControllers[index] = TextEditingController(
              text: result.quantity > 0 ? result.quantity.toStringAsFixed(2) : '',
            );
          }
        } else {
          final newIndex = _items.length;
          _items.add(result);
          // Initialize controller for new item
          _quantityControllers[newIndex] = TextEditingController(
            text: result.quantity > 0 ? result.quantity.toStringAsFixed(2) : '',
          );
        }
      });
    }
  }

  double get _totalAmount {
    // Calculate from current items (which should include stored items)
    return _items.fold(0, (sum, item) => sum + item.totalPrice);
  }

  double get _totalQuantity {
    // Calculate from current items (which should include stored items)
    return _items.fold(0, (sum, item) => sum + item.quantity);
  }

  // Save all design allocations before submitting
  // Save draft order to local storage
  Future<void> _saveDraftOrderToLocalStorage() async {
    try {
      // Get all items with quantity > 0 (both current and stored)
      final allItemsWithQuantity = <ChallanItem>[];
      final addedKeys = <String>{};
      
      // Add current items with quantity > 0
      for (var item in _items) {
        if (item.quantity > 0) {
          final key = _getItemKey(item);
          if (!addedKeys.contains(key)) {
            allItemsWithQuantity.add(item);
            addedKeys.add(key);
          }
        }
      }
      
      // Add stored items that are not already in current items
      for (var storedItem in _storedItems) {
        if (storedItem.quantity > 0) {
          final key = _getItemKey(storedItem);
          if (!addedKeys.contains(key)) {
            allItemsWithQuantity.add(storedItem);
            addedKeys.add(key);
          }
        }
      }
      
      // Save to local storage
      await LocalStorageService.saveDraftOrder(
        orderNumber: widget.orderNumber,
        orderData: widget.orderData,
        storedItems: allItemsWithQuantity,
        designAllocations: _sizeDesignAllocations,
      );
      
      print('=== DRAFT ORDER SAVED TO LOCAL STORAGE ===');
      print('Order Number: ${widget.orderNumber}');
      print('Items count: ${allItemsWithQuantity.length}');
    } catch (e) {
      print('Error saving draft order to local storage: $e');
    }
  }

  void _saveAllDesignAllocations() {
    // Save current editing size if any
    if (_currentlyEditingSizeIndex != null) {
      final sizeKey = _getSizeKey(_currentlyEditingSizeIndex!);
      _saveSizeDesignAllocations(sizeKey);
    }
    
    // Save all sizes that have current selections
    for (var entry in _currentSizeDesignSelections.entries) {
      if (entry.value.isNotEmpty) {
        _saveSizeDesignAllocations(entry.key);
      }
    }
    
    // Save to local storage after design allocations are saved
    _saveDraftOrderToLocalStorage();
  }
  
  // Get all saved design allocations with product and size info
  List<Map<String, dynamic>> _getAllSavedDesignAllocations() {
    final allocations = <Map<String, dynamic>>[];
    
    for (var entry in _sizeDesignAllocations.entries) {
      final sizeKey = entry.key;
      final designMap = entry.value;
      
      // Find the item for this size key
      final item = _items.firstWhere(
        (item) => _getItemKey(item) == sizeKey,
        orElse: () => ChallanItem(productName: 'Unknown', quantity: 0),
      );
      
      if (item.productName != 'Unknown' && designMap.isNotEmpty) {
        allocations.add({
          'productName': item.productName,
          'sizeText': item.sizeText ?? 'N/A',
          'sizeId': item.sizeId,
          'productId': item.productId,
          'totalQuantity': item.quantity,
          'designs': designMap,
        });
      }
    }
    
    return allocations;
  }
  
  // Handle OK button click
  Future<void> _handleOk() async {
    await _showDesignAllocationsModal();
  }
  
  // Show modal with all saved design allocations
  Future<void> _showDesignAllocationsModal() async {
    // Save all current allocations first
    _saveAllDesignAllocations();
    
    // Check if we have items with quantity
    final hasItems = _items.any((item) => item.quantity > 0) || 
                     _storedItems.any((item) => item.quantity > 0);
    
    if (!hasItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_currentSection == 'A' 
            ? 'Please enter quantity greater than 0'
            : 'Please select products and enter quantity greater than 0'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final allocations = _getAllSavedDesignAllocations();
    
    // Get all items with quantity > 0
    final itemsWithQuantity = _items.where((item) => item.quantity > 0).toList();
    
    // Show modal with allocations (even if empty, to confirm submission)
    final shouldProceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _DesignAllocationsModal(
          allocations: allocations,
          items: itemsWithQuantity,
        );
      },
    );
    
    if (shouldProceed == true && mounted) {
      await _submitOrder();
    }
  }
  
  // Submit order (extracted from _handleOk)
  Future<void> _submitOrder() async {
    // First, update all items with quantities from controllers
    // This ensures we have the latest values from the text fields
    for (var entry in _quantityControllers.entries) {
      if (entry.key < _items.length) {
        final controllerText = entry.value.text.trim();
        if (controllerText.isNotEmpty) {
          final quantity = double.tryParse(controllerText) ?? 0;
          if (quantity > 0) {
            final item = _items[entry.key];
            _items[entry.key] = item.copyWith(quantity: quantity);
          }
        }
      }
    }
    
    // Filter items based on current tab
    List<ChallanItem> itemsWithQuantity;
    
    if (_currentSection == 'A') {
      // Tab A: Send all items with quantity > 0 (mixed designs)
      itemsWithQuantity = _items.where((item) => item.quantity > 0).toList();
    } else {
      // Tab B: Send only items from selected products with quantity > 0
      itemsWithQuantity = _items.where((item) => 
        item.quantity > 0 && 
        item.productId != null && 
        _selectedProductIds.contains(item.productId)
      ).toList();
    }
    
    // Include stored items that are not in current items
    // Merge stored items with current items, avoiding duplicates
    final allItems = <ChallanItem>[];
    final addedKeys = <String>{};
    
    // Add current items first
    for (var item in itemsWithQuantity) {
      final key = _getItemKey(item);
      if (!addedKeys.contains(key)) {
        allItems.add(item);
        addedKeys.add(key);
      }
    }
    
    // Add stored items that are not already in current items
    for (var storedItem in _storedItems) {
      final key = _getItemKey(storedItem);
      if (!addedKeys.contains(key)) {
        allItems.add(storedItem);
        addedKeys.add(key);
      }
    }
    
    if (allItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_currentSection == 'A' 
            ? 'Please enter quantity greater than 0'
            : 'Please select products and enter quantity greater than 0'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Use allItems instead of itemsWithQuantity for submission
    itemsWithQuantity = allItems;

    if (!mounted) return;
    setState(() => _isSubmitting = true);
    try {
      String actualOrderNumber = widget.orderNumber;
      
      // Prepare order items from challan items
      // Filter out items with null productId - these cannot be processed by backend
      final validItems = itemsWithQuantity.where((item) => 
        item.productId != null && 
        item.quantity > 0 &&
        item.unitPrice > 0
      ).toList();
      
      if (validItems.isEmpty) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please ensure all items have valid product information and quantity > 0'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final orderItems = validItems.map((item) {
        // Prefer sending the real external_id from catalog, so backend can resolve correctly
        int? externalId;
        if (item.productId != null && _catalog.isNotEmpty) {
          try {
            final product = _catalog.firstWhere((p) => p.id == item.productId);
            externalId = product.externalId;
            print('Found externalId for product ${item.productId}: $externalId');
          } catch (e) {
            print('Warning: Product ${item.productId} not found in catalog (${_catalog.length} products available)');
            externalId = null;
          }
        }
        // Only send externalId if it's numeric, otherwise let backend use name lookup
        final externalIdValue = (externalId != null) ? externalId : null;
        return {
          'product_id': item.productId,
          'product_external_id': externalIdValue, // Send null if not available, backend will use name
          'product_name': item.productName,
          'size_id': item.sizeId,
          'size_text': item.sizeText ?? '',
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
        };
      }).toList();
      
      // Debug logging
      print('=== SUBMITTING ORDER ===');
      print('Valid items count: ${validItems.length}');
      for (var item in validItems) {
        print('Item: ${item.productName} - productId: ${item.productId}, sizeId: ${item.sizeId}, quantity: ${item.quantity}, unitPrice: ${item.unitPrice}');
      }
      print('Order items to send: $orderItems');
      
      // Always send items to backend - if order exists, items will be added to it
      // If order doesn't exist (PENDING), a new order will be created
      final orderData = {
        ...widget.orderData,
        'items': orderItems,
      };
      
      // If order number is not PENDING, include it so backend can add items to existing order
      if (widget.orderNumber != 'PENDING') {
        orderData['order_number'] = widget.orderNumber;
      }
      
      print('Full order data being sent: $orderData');
      
      final orderResult = await ApiService.createOrderWithMultipleItems(orderData);
      actualOrderNumber = (orderResult['order_number'] ?? widget.orderNumber).toString();
      
      // Save all design allocations before submitting
      _saveAllDesignAllocations();
      
      // Order created successfully - no challan is created with orders
      print('=== ORDER CREATED - NO CHALLAN WILL BE CREATED ===');
      print('Order Number: $actualOrderNumber');
      
      // Clear draft order from local storage since order is successfully submitted
      await LocalStorageService.removeDraftOrder();
      
      if (!mounted) return;

      // Navigate to success screen (without challan)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => OrderChallanSuccessScreen(
            challan: null, // No challan created with order
            partyName: widget.partyName,
            orderNumber: actualOrderNumber,
            items: itemsWithQuantity,
            totalAmount: _totalAmount,
            designAllocations: _sizeDesignAllocations,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create order: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    // Ensure stored items are always visible in _items
    // This is a safety check to ensure stored items don't get lost
    // Only run once to prevent duplicate additions
    if (_storedItems.isNotEmpty && !_hasAutoRestoredInBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasAutoRestoredInBuild) {
          // Check if stored items are missing from _items
          final storedKeys = _storedItems.map((item) => _getItemKey(item)).toSet();
          final currentKeys = _items.map((item) => _getItemKey(item)).toSet();
          final missingKeys = storedKeys.difference(currentKeys);
          
          if (missingKeys.isNotEmpty) {
            print('=== AUTO-RESTORING STORED ITEMS IN BUILD ===');
            print('Stored items: ${_storedItems.length}, Current items: ${_items.length}');
            print('Missing ${missingKeys.length} stored items, restoring...');
            setState(() {
              // Mark as restored to prevent duplicate runs
              _hasAutoRestoredInBuild = true;
              
              // Add missing stored items
              for (var storedItem in _storedItems) {
                final key = _getItemKey(storedItem);
                if (missingKeys.contains(key)) {
                  // Double-check the item doesn't already exist (race condition protection)
                  final alreadyExists = _items.any((item) => _getItemKey(item) == key);
                  if (!alreadyExists) {
                    _items.add(storedItem.copyWith());
                    final index = _items.length - 1;
                    if (!_quantityControllers.containsKey(index)) {
                      _quantityControllers[index] = TextEditingController(
                        text: storedItem.quantity > 0 ? storedItem.quantity.toStringAsFixed(2) : '',
                      );
                    }
                    print('Auto-restored: ${storedItem.productName} - ${storedItem.sizeText} - Qty: ${storedItem.quantity}');
                  }
                }
              }
              print('After auto-restore: ${_items.length} items');
            });
          } else {
            print('All stored items already present in _items (${_items.length} items)');
            _hasAutoRestoredInBuild = true; // Mark as checked even if nothing was missing
          }
        }
      });
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      resizeToAvoidBottomInset: true, // Resize so keyboard does not overlap content; footer stays above keyboard
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content
            Column(
              children: [
                // Header with Party Name and Order Number (Tabular)
                _buildHeader(),
                // Scrollable: Design section + Table section
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 100, // Add padding for fixed footer buttons
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildImageSelectionSection(),
                        _buildTableSection(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            // Fixed Bottom Navigation with OK Button
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildFooterButtons(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            children: [
              TableCell(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Party Name',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.partyName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TableCell(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order Number',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.orderNumber,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
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
    );
  }
  
  Widget _buildOptionSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selection Mode',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildOptionButton('A', 'Option A (Random/Mixed)', _isOptionA),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOptionButton('B', 'Option B (Manual Selection)', !_isOptionA),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildOptionButton(String option, String label, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          if (option == 'A') {
            _isOptionA = true;
            // Clear current selections when switching to A
            _currentSizeDesignSelections.clear();
            // Save any pending allocations before clearing
            if (_currentlyEditingSizeIndex != null) {
              final sizeKey = _getSizeKey(_currentlyEditingSizeIndex!);
              _saveSizeDesignAllocations(sizeKey);
              _clearCurrentSizeDesignSelections(sizeKey);
              _currentlyEditingSizeIndex = null;
            }
          } else {
            _isOptionA = false;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFB8860B) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFB8860B) : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(
              option,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white : Colors.grey.shade600,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSelectionSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A/B Selector Tabs
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildSectionTab('A', 'A'),
                ),
                Expanded(
                  child: _buildSectionTab('B', 'B'),
                ),
              ],
            ),
          ),
          // Image Grid or Design Selection based on Tab
          Container(
            height: 250,
            child: _buildDesignSelectionInImageGrid(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSectionTab(String section, String label) {
    final isSelected = _currentSection == section;
    return InkWell(
      onTap: () {
        setState(() {
          _currentSection = section;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(12),
            bottom: Radius.zero,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFFB8860B) : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
  
  Widget _buildImageGrid(List<Product> products) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentSection == 'A' ? Icons.image_outlined : Icons.check_circle_outline,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              _currentSection == 'A' 
                  ? 'No products available' 
                  : 'No products selected',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final productId = product.id;
              final isSelected = productId != null && _selectedProductIds.contains(productId);
              
              return _buildImageItem(product, isSelected);
            },
          ),
        ),
        // Scroll indicator
        if (products.length > 8)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Scrolling for more designs',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
  
  // Build demo image widget (styled placeholder with geometric fabric pattern)
  Widget _buildDemoImage(Product product) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
      ),
      child: Stack(
        children: [
          // Geometric fabric pattern
          CustomPaint(
            painter: _GeometricFabricPainter(),
            child: Container(),
          ),
          // Product info overlay
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DECO JEWEL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'REAL WORTH FOR MONEY',
                  style: TextStyle(
                    fontSize: 7,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.name?.toUpperCase() ?? 'PRODUCT',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (product.categoryName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${product.categoryName?.toUpperCase()} | SIZE',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey.shade700,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildImageItem(Product product, bool isSelected) {
    return GestureDetector(
      onTap: () {
        // In tab A, only allow single tap to view full screen (no selection)
        if (_currentSection == 'A') {
          _showFullScreenImage(product);
          return;
        }
        
        // In tab B, allow double tap for selection
        final now = DateTime.now();
        final productId = product.id;
        
        // Check if this is a double tap
        if (productId != null && 
            _lastTappedProductId == productId && 
            _lastTapTime != null &&
            now.difference(_lastTapTime!) < const Duration(milliseconds: 400)) {
          // Double tap detected - toggle selection
          _toggleProductSelection(product);
          _lastTappedProductId = null;
          _lastTapTime = null;
        } else {
          // Single tap - open full screen after delay
          _lastTappedProductId = productId;
          _lastTapTime = now;
          Future.delayed(const Duration(milliseconds: 400), () {
            if (_lastTappedProductId == productId && _lastTapTime == now) {
              _showFullScreenImage(product);
              _lastTappedProductId = null;
              _lastTapTime = null;
            }
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (isSelected && _currentSection == 'B') 
              ? const Color(0xFFB8860B) 
              : Colors.grey.shade300,
            width: (isSelected && _currentSection == 'B') ? 3 : 1,
          ),
        ),
        child: Stack(
          children: [
            // Product Image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                  ? Image.network(
                      product.imageUrl!,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      cacheHeight: 400,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.shade200,
                          child: const Icon(
                            Icons.broken_image,
                            size: 32,
                            color: Colors.grey,
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB8860B)),
                            ),
                          ),
                        );
                      },
                    )
                  : _buildDemoImage(product),
            ),
            // Selection Indicator (only show in Tab B)
            if (isSelected && _currentSection == 'B')
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFB8860B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            // Product Code/Name Overlay (showing externalId or name)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(8),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Show externalId if available, otherwise show name
                    Text(
                      product.externalId != null 
                        ? product.externalId.toString() 
                        : (product.name ?? 'Product'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    // Show product name below if externalId is shown
                    if (product.externalId != null && product.name != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.name!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableSection() {
    // Get only new items (not stored items) to show in table
    final newItems = _newItems;
    
    // Debug: Print items when building table
    print('=== BUILDING TABLE ===');
    print('Total items count: ${_items.length}');
    print('New items count: ${newItems.length}');
    print('Stored items count: ${_storedItems.length}');
    for (var item in newItems) {
      print('New item in table: ${item.productName} - ${item.sizeText} - Qty: ${item.quantity}');
    }
    
    if (newItems.isEmpty && _previousItems.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
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
            color: Colors.black.withOpacity(0.05),
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
          // Table Rows - Only show new items
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
                      'Click "Previous" button to view stored items',
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
  
  // Show popup with previous items
  void _showPreviousItemsPopup() {
    showDialog(
      context: context,
      builder: (context) => _PreviousItemsDialog(
        previousItems: _previousItems,
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
    
    // Initialize design controllers for all products when quantity > 0
    final sizeKey = _getSizeKey(index);
    if (item.quantity > 0) {
      _initializeDesignControllersForSize(sizeKey);
    }

    final designsEnabled = _areDesignsEnabledForSize(index);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
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
                // Product Name (with size if available) - Make size clickable for filtering/design selection
                Expanded(
                  flex: 3,
                  child: InkWell(
                    onTap: item.sizeId != null ? () {
                      setState(() {
                        if (_currentSection == 'B' && item.quantity > 0) {
                          // In Tab B, clicking size activates design selection for that size
                          final sizeKey = _getSizeKey(index);
                          _initializeDesignControllersForSize(sizeKey);
                          if (!_currentSizeDesignSelections.containsKey(sizeKey)) {
                            _currentSizeDesignSelections[sizeKey] = {};
                          }
                          
                          // Save previous size if any
                          if (_currentlyEditingSizeIndex != null && _currentlyEditingSizeIndex != index) {
                            final prevSizeKey = _getSizeKey(_currentlyEditingSizeIndex!);
                            _saveSizeDesignAllocations(prevSizeKey);
                            _clearCurrentSizeDesignSelections(prevSizeKey);
                          }
                          
                          _currentlyEditingSizeIndex = index;
                          _restoreSizeDesignAllocations(sizeKey);
                        } else {
                          // In Tab A, toggle size filter
                          if (_selectedSizeId == item.sizeId) {
                            _selectedSizeId = null;
                          } else {
                            _selectedSizeId = item.sizeId;
                          }
                        }
                      });
                    } : null,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.sizeText != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Size: ${item.sizeText}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _selectedSizeId == item.sizeId 
                                      ? const Color(0xFFB8860B)
                                      : Colors.grey.shade600,
                                    fontWeight: _selectedSizeId == item.sizeId 
                                      ? FontWeight.bold 
                                      : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              if (_selectedSizeId == item.sizeId) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.filter_alt,
                                  size: 14,
                                  color: Color(0xFFB8860B),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
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
                      child: Focus(
                        onFocusChange: (hasFocus) {
                          _onQuantityFieldFocusChange(index, hasFocus);
                        },
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
                            _scheduleQuantityUpdate(index, value);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Build design selection section in image grid area for Tab B
  Widget _buildDesignSelectionInImageGrid() {
    // Get all items with quantity > 0
    final itemsWithQuantity = _items.where((item) => item.quantity > 0).toList();
    
    if (itemsWithQuantity.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.palette_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'No items with quantity',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add quantity to items to select designs',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFB8860B).withOpacity(0.1),
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.shade200,
                width: 1,
              ),
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.palette_outlined,
                color: Color(0xFFB8860B),
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Design Selection',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
        // Scrollable design selection for each item
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: itemsWithQuantity.asMap().entries.map((entry) {
                final index = _items.indexOf(entry.value);
                final item = entry.value;
                final sizeKey = _getSizeKey(index);
                final designsEnabled = _areDesignsEnabledForSize(index);
                
                return _buildDesignSelectionForItem(
                  item: item,
                  itemIndex: index,
                  sizeKey: sizeKey,
                  designsEnabled: designsEnabled,
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
  
  // Build design selection section for Tab B - shows all items with quantity > 0
  Widget _buildDesignSelectionSectionForTabB() {
    // Get all items with quantity > 0
    final itemsWithQuantity = _items.where((item) => item.quantity > 0).toList();
    
    if (itemsWithQuantity.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFB8860B).withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  color: Color(0xFFB8860B),
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Design Selection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          ),
          // Design selection for each item
          ...itemsWithQuantity.asMap().entries.map((entry) {
            final index = _items.indexOf(entry.value);
            final item = entry.value;
            final sizeKey = _getSizeKey(index);
            final designsEnabled = _areDesignsEnabledForSize(index);
            
            return _buildDesignSelectionForItem(
              item: item,
              itemIndex: index,
              sizeKey: sizeKey,
              designsEnabled: designsEnabled,
            );
          }),
        ],
      ),
    );
  }
  
  // Build design selection for a single item
  Widget _buildDesignSelectionForItem({
    required ChallanItem item,
    required int itemIndex,
    required String sizeKey,
    required bool designsEnabled,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product and Size info
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.sizeText != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Size: ${item.sizeText}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Total Quantity: ${item.quantity.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB8860B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Design chips
          Builder(
            builder: (context) {
              final designsToShow = _getDesignsToShow(productId: item.productId);
              print('Building design chips for ${item.productName} (ID: ${item.productId}): ${designsToShow.length} designs');
              
              if (designsToShow.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No designs available',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }
              
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: designsToShow.map((design) {
                  final controller = _getDesignController(sizeKey, design);
                  final currentQty = _currentSizeDesignSelections[sizeKey]?[design] ?? 0;
                  final isSelected = currentQty > 0;
                  
                  return _buildDesignChip(
                    design: design,
                    sizeKey: sizeKey,
                    controller: controller,
                    isEnabled: designsEnabled,
                    isSelected: isSelected,
                  );
                }).toList(),
              );
            },
          ),
          if (designsEnabled && _currentlyEditingSizeIndex == itemIndex) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final totalDesignQty = _getTotalDesignQuantityForSize(sizeKey);
                final totalItemQty = _getTotalQuantityForSize(sizeKey);
                final exceedsTotal = totalDesignQty > totalItemQty;
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Design Qty: $totalDesignQty / $totalItemQty',
                      style: TextStyle(
                        fontSize: 11,
                        color: exceedsTotal ? Colors.red : Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                        fontWeight: exceedsTotal ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (exceedsTotal) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠ Design quantity exceeds item quantity!',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildDesignSelectionSection(int itemIndex, String sizeKey, bool designsEnabled) {
    // Extract productId from sizeKey
    final productId = _extractProductIdFromSizeKey(sizeKey);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          top: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Design Selection:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _getDesignsToShow(productId: productId).map((design) {
              final controller = _getDesignController(sizeKey, design);
              final currentQty = _currentSizeDesignSelections[sizeKey]?[design] ?? 0;
              final isSelected = currentQty > 0;
              
              return _buildDesignChip(
                design: design,
                sizeKey: sizeKey,
                controller: controller,
                isEnabled: designsEnabled,
                isSelected: isSelected,
              );
            }).toList(),
          ),
          if (designsEnabled && _currentlyEditingSizeIndex == itemIndex) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final totalDesignQty = _getTotalDesignQuantityForSize(sizeKey);
                final totalItemQty = _getTotalQuantityForSize(sizeKey);
                final exceedsTotal = totalDesignQty > totalItemQty;
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Design Qty: $totalDesignQty / $totalItemQty',
                      style: TextStyle(
                        fontSize: 11,
                        color: exceedsTotal ? Colors.red : Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                        fontWeight: exceedsTotal ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (exceedsTotal) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠ Design quantity exceeds item quantity!',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildDesignChip({
    required String design,
    required String sizeKey,
    required TextEditingController controller,
    required bool isEnabled,
    required bool isSelected,
  }) {
    // Check if this is a static design (D1, D2, D3) to show image
    final isStaticDesign = _staticDesigns.contains(design);
    
    return Container(
      constraints: const BoxConstraints(maxWidth: 90),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Design label button/chip with image for static designs
          InkWell(
            onTap: isEnabled ? () {
              // Toggle selection
              setState(() {
                if (!_currentSizeDesignSelections.containsKey(sizeKey)) {
                  _currentSizeDesignSelections[sizeKey] = {};
                }
                if (isSelected) {
                  _currentSizeDesignSelections[sizeKey]!.remove(design);
                  controller.text = '';
                }
                // If not selected, user can directly type in quantity field
              });
            } : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 55, maxHeight: 55),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: isEnabled
                    ? (isSelected ? const Color(0xFFB8860B).withOpacity(0.2) : Colors.transparent)
                    : Colors.grey.shade200,
                border: Border.all(
                  color: isEnabled
                      ? (isSelected ? const Color(0xFFB8860B) : Colors.grey.shade400)
                      : Colors.grey.shade300,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: isStaticDesign
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Static image placeholder for D1, D2, D3
                        Container(
                          width: 35,
                          height: 25,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Icon(
                            Icons.image_outlined,
                            size: 18,
                            color: isEnabled
                                ? (isSelected ? const Color(0xFFB8860B) : Colors.grey.shade600)
                                : Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          design,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isEnabled
                                ? (isSelected ? const Color(0xFFB8860B) : Colors.grey.shade800)
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      design,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isEnabled
                            ? (isSelected ? const Color(0xFFB8860B) : Colors.grey.shade800)
                            : Colors.grey.shade500,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 3),
          // Quantity input for this design
          Builder(
            builder: (context) {
              // Check if total design quantity exceeds item quantity
              final totalDesignQty = _getTotalDesignQuantityForSize(sizeKey);
              final totalItemQty = _getTotalQuantityForSize(sizeKey);
              final currentQty = _currentSizeDesignSelections[sizeKey]?[design] ?? 0;
              final hasError = totalDesignQty > totalItemQty && currentQty > 0;
              
              return SizedBox(
                width: 70,
                height: 32,
                child: Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      // Validate and cap when focus is lost
                      _validateDesignQuantity(sizeKey, design);
                    }
                  },
                  child: TextField(
                    controller: controller,
                    enabled: isEnabled,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: 'Qty',
                      hintStyle: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                      ),
                      filled: true,
                      fillColor: isEnabled 
                          ? (hasError ? Colors.red.shade50 : Colors.white)
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: hasError ? Colors.red.shade600 : Colors.grey.shade300,
                          width: hasError ? 2 : 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: hasError ? Colors.red.shade600 : Colors.grey.shade300,
                          width: hasError ? 2 : 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: hasError ? Colors.red.shade600 : const Color(0xFFB8860B),
                          width: hasError ? 2 : 1.5,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: Colors.red.shade600,
                          width: 2,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: Colors.red.shade600,
                          width: 2,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      isDense: true,
                      constraints: const BoxConstraints(maxHeight: 30),
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isEnabled 
                          ? (hasError ? Colors.red.shade700 : const Color(0xFF1A1A1A))
                          : Colors.grey.shade400,
                    ),
                    onChanged: (value) {
                      // Debounced to reduce lag; exceed check still runs immediately
                      _scheduleDesignQuantityUpdate(sizeKey, design, value);
                    },
                    onEditingComplete: () {
                      // Validate when user presses done/enter
                      _validateDesignQuantity(sizeKey, design);
                    },
                  ),
                ),
              );
            },
          ),
        ],
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
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back Button
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                // Save all design allocations before going back
                _saveAllDesignAllocations();
                // Return products, stored items, and design allocations when going back
                Navigator.pop(
                  context,
                  OrderFormReturnData(
                    products: _catalog,
                    storedItems: _storedItems,
                    designAllocations: _sizeDesignAllocations,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Back',
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
          // END Button
          Expanded(
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handleOk,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB8860B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'END',
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
}

// Custom painter for geometric fabric pattern (inspired by tablecloth patterns)
class _GeometricFabricPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Base background
    final backgroundPaint = Paint()
      ..color = Colors.grey.shade50
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // Create geometric pattern with triangles and diamonds
    final patternSize = 24.0;
    final darkPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.fill;
    final lightPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;
    final mediumPaint = Paint()
      ..color = Colors.grey.shade500
      ..style = PaintingStyle.fill;

    // Draw tessellating geometric pattern
    for (double y = 0; y < size.height + patternSize; y += patternSize) {
      for (double x = 0; x < size.width + patternSize; x += patternSize) {
        final offsetX = (y / patternSize).floor() % 2 == 0 ? 0 : patternSize / 2;
        final currentX = x + offsetX;
        
        // Draw diamond/triangle shapes
        final path1 = Path()
          ..moveTo(currentX, y)
          ..lineTo(currentX + patternSize / 2, y + patternSize / 2)
          ..lineTo(currentX, y + patternSize)
          ..lineTo(currentX - patternSize / 2, y + patternSize / 2)
          ..close();
        
        final path2 = Path()
          ..moveTo(currentX + patternSize / 2, y + patternSize / 2)
          ..lineTo(currentX + patternSize, y)
          ..lineTo(currentX + patternSize, y + patternSize)
          ..lineTo(currentX + patternSize / 2, y + patternSize / 2)
          ..close();

        // Alternate colors for depth
        if ((x / patternSize + y / patternSize).floor() % 3 == 0) {
          canvas.drawPath(path1, darkPaint);
          canvas.drawPath(path2, lightPaint);
        } else if ((x / patternSize + y / patternSize).floor() % 3 == 1) {
          canvas.drawPath(path1, mediumPaint);
          canvas.drawPath(path2, darkPaint);
        } else {
          canvas.drawPath(path1, lightPaint);
          canvas.drawPath(path2, mediumPaint);
        }
      }
    }

    // Add subtle border pattern
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    // Bottom border
    canvas.drawLine(
      Offset(0, size.height - 4),
      Offset(size.width, size.height - 4),
      borderPaint,
    );
    
    // Right border
    canvas.drawLine(
      Offset(size.width - 4, 0),
      Offset(size.width - 4, size.height),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChallanItemDialog extends StatefulWidget {
  final List<Product> catalog;
  final ChallanItem? initialItem;
  final String? priceCategory;

  const _ChallanItemDialog({
    required this.catalog,
    this.initialItem,
    this.priceCategory,
  });

  @override
  State<_ChallanItemDialog> createState() => _ChallanItemDialogState();
}

class _ChallanItemDialogState extends State<_ChallanItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _productController = TextEditingController();
  final TextEditingController _quantityController =
      TextEditingController(text: '1');
  final TextEditingController _priceController = TextEditingController();

  Product? _selectedProduct;
  ProductSize? _selectedSize;

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

  @override
  void initState() {
    super.initState();
    if (widget.initialItem != null) {
      final item = widget.initialItem!;
      _quantityController.text = item.quantity.toString();
      _priceController.text = item.unitPrice.toStringAsFixed(2);
      _productController.text = item.productName;
      _selectedProduct = widget.catalog.firstWhere(
        (product) => product.id == item.productId,
        orElse: () => Product(name: item.productName),
      );
      final productSizes = _selectedProduct?.sizes ?? [];
      if (productSizes.isNotEmpty) {
        _selectedSize = productSizes.firstWhere(
          (size) => size.id == item.sizeId,
          orElse: () => productSizes.first,
        );
        final defaultPrice = _getPriceByCategory(_selectedSize) ?? 0;
        if (defaultPrice > 0 && (_priceController.text.isEmpty)) {
          _priceController.text = defaultPrice.toStringAsFixed(2);
        }
      }
    }
  }

  @override
  void dispose() {
    _productController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  List<Product> _suggestions(String pattern) {
    final query = pattern.toLowerCase();
    return widget.catalog
        .where((product) {
          final name = (product.name ?? '').toLowerCase();
          final externalId = product.externalId?.toString() ?? '';
          return query.isEmpty ||
              name.contains(query) ||
              externalId.contains(query);
        })
        .take(15)
        .toList();
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _productController.text = product.name ?? 'Product';
      _selectedSize =
          product.sizes?.isNotEmpty == true ? product.sizes!.first : null;
      final defaultPrice = _getPriceByCategory(_selectedSize) ?? 0;
      if (defaultPrice > 0) {
        _priceController.text = defaultPrice.toStringAsFixed(2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add Product'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TypeAheadField<Product>(
                controller: _productController,
                builder: (context, textController, focusNode) {
                  return TextFormField(
                    controller: textController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Product *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if ((value ?? '').isEmpty) return 'Select a product';
                      if (_selectedProduct == null) {
                        return 'Please pick an item from the list';
                      }
                      return null;
                    },
                  );
                },
                suggestionsCallback: (pattern) async => _suggestions(pattern),
                itemBuilder: (_, suggestion) => ListTile(
                  title: Text(suggestion.name ?? 'Product'),
                  subtitle: Text(suggestion.categoryName ?? ''),
                ),
                onSelected: (suggestion) {
                  _selectProduct(suggestion);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ProductSize>(
                value: _selectedSize,
                decoration: const InputDecoration(
                  labelText: 'Size / Variant',
                  border: OutlineInputBorder(),
                ),
                items: (_selectedProduct?.sizes ?? [])
                    .map(
                      (size) => DropdownMenuItem(
                        value: size,
                        child: Text(size.sizeText ?? 'Size'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedSize = value;
                    final defaultPrice = _getPriceByCategory(value) ?? 0;
                    if (defaultPrice > 0) {
                      _priceController.text = defaultPrice.toStringAsFixed(2);
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final quantity = double.tryParse(value ?? '');
                  if (quantity == null || quantity <= 0) {
                    return 'Enter a valid quantity';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Unit Price *',
                  border: OutlineInputBorder(),
                  prefixText: '₹ ',
                ),
                validator: (value) {
                  final price = double.tryParse(value ?? '');
                  if (price == null || price < 0) {
                    return 'Enter valid price';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            final quantity = double.parse(_quantityController.text);
            final price = double.parse(_priceController.text);
            final product = _selectedProduct!;

            final newItem = ChallanItem(
              productId: product.id,
              productName: product.name ?? 'Product',
              sizeId: _selectedSize?.id,
              sizeText: _selectedSize?.sizeText,
              quantity: quantity,
              unitPrice: price,
            );
            Navigator.pop(context, newItem);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFB8860B),
          ),
          child: const Text('ADD'),
        ),
      ],
    );
  }
}

// Modal to show all saved design allocations
class _DesignAllocationsModal extends StatelessWidget {
  final List<Map<String, dynamic>> allocations;
  final List<ChallanItem> items;
  
  const _DesignAllocationsModal({
    required this.allocations,
    required this.items,
  });
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: const Text(
                    'Order Summary',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF1A1A1A)),
                  onPressed: () => Navigator.pop(context, false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            // Content - Items Table
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No items found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Items Table
                          const Row(
                            children: [
                              Icon(
                                Icons.list_alt_rounded,
                                color: Color(0xFFB8860B),
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Items',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A1A),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 35,
                                  child: Text(
                                    'S.N.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'Name',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Price',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Quantity',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Table Rows
                          ...items.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index < items.length - 1 ? 10 : 0,
                              ),
                              child: _buildItemTableRow(item, index + 1),
                            );
                          }),
                          // Design Allocations Section
                          // if (allocations.isNotEmpty) ...[
                          //   const SizedBox(height: 24),
                          //   const Divider(),
                          //   const SizedBox(height: 16),
                          //   const Row(
                          //     children: [
                          //       Icon(
                          //         Icons.palette_outlined,
                          //         color: Color(0xFFB8860B),
                          //         size: 18,
                          //       ),
                          //       SizedBox(width: 8),
                          //       Text(
                          //         'Design Allocations',
                          //         style: TextStyle(
                          //           fontSize: 15,
                          //           fontWeight: FontWeight.bold,
                          //           color: Color(0xFF1A1A1A),
                          //           letterSpacing: 0.3,
                          //         ),
                          //       ),
                          //     ],
                          //   ),
                          //   const SizedBox(height: 12),
                          //   ...allocations.map((allocation) {
                          //     final productName = allocation['productName'] as String;
                          //     final sizeText = allocation['sizeText'] as String;
                          //     final totalQuantity = allocation['totalQuantity'] as double;
                          //     final designs = allocation['designs'] as Map<String, int>;
                              
                          //     return Container(
                          //       margin: const EdgeInsets.only(bottom: 12),
                          //       padding: const EdgeInsets.all(12),
                          //       decoration: BoxDecoration(
                          //         color: Colors.grey.shade50,
                          //         borderRadius: BorderRadius.circular(8),
                          //         border: Border.all(
                          //           color: Colors.grey.shade200,
                          //           width: 1,
                          //         ),
                          //       ),
                          //       child: Column(
                          //         crossAxisAlignment: CrossAxisAlignment.start,
                          //         children: [
                          //           Text(
                          //             '$productName - $sizeText',
                          //             style: const TextStyle(
                          //               fontSize: 13,
                          //               fontWeight: FontWeight.bold,
                          //               color: Color(0xFF1A1A1A),
                          //             ),
                          //           ),
                          //           const SizedBox(height: 4),
                          //           Text(
                          //             'Total Quantity: ${totalQuantity.toStringAsFixed(0)}',
                          //             style: const TextStyle(
                          //               fontSize: 12,
                          //               fontWeight: FontWeight.w600,
                          //               color: Color(0xFFB8860B),
                          //             ),
                          //           ),
                          //           const SizedBox(height: 8),
                          //           Wrap(
                          //             spacing: 8,
                          //             runSpacing: 6,
                          //             children: designs.entries.map((entry) {
                          //               final design = entry.key;
                          //               final qty = entry.value;
                          //               final isStaticDesign = ['D1', 'D2', 'D3'].contains(design);
                                        
                          //               return Container(
                          //                 padding: const EdgeInsets.symmetric(
                          //                   horizontal: 10,
                          //                   vertical: 6,
                          //                 ),
                          //                 decoration: BoxDecoration(
                          //                   color: const Color(0xFFB8860B).withOpacity(0.1),
                          //                   border: Border.all(
                          //                     color: const Color(0xFFB8860B),
                          //                     width: 1,
                          //                   ),
                          //                   borderRadius: BorderRadius.circular(6),
                          //                 ),
                          //                 child: Row(
                          //                   mainAxisSize: MainAxisSize.min,
                          //                   children: [
                          //                     if (isStaticDesign) ...[
                          //                       Container(
                          //                         width: 20,
                          //                         height: 15,
                          //                         decoration: BoxDecoration(
                          //                           color: Colors.grey.shade100,
                          //                           borderRadius: BorderRadius.circular(3),
                          //                           border: Border.all(
                          //                             color: Colors.grey.shade300,
                          //                           ),
                          //                         ),
                          //                         child: Icon(
                          //                           Icons.image_outlined,
                          //                           size: 12,
                          //                           color: Colors.grey.shade600,
                          //                         ),
                          //                       ),
                          //                       const SizedBox(width: 4),
                          //                     ],
                          //                     Text(
                          //                       design,
                          //                       style: const TextStyle(
                          //                         fontSize: 12,
                          //                         fontWeight: FontWeight.w600,
                          //                         color: Color(0xFF1A1A1A),
                          //                       ),
                          //                     ),
                          //                     const SizedBox(width: 4),
                          //                     Text(
                          //                       ': $qty',
                          //                       style: const TextStyle(
                          //                         fontSize: 12,
                          //                         fontWeight: FontWeight.bold,
                          //                         color: Color(0xFFB8860B),
                          //                       ),
                          //                     ),
                          //                   ],
                          //                 ),
                          //               );
                          //             }).toList(),
                          //           ),
                          //         ],
                          //       ),
                          //     );
                          //   }),
                          // ],
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey.shade300),
            const SizedBox(height: 16),
            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                  ),
                  child: const Text('CANCEL'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB8860B),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('SUBMIT'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildItemTableRow(ChallanItem item, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Serial Number
          SizedBox(
            width: 35,
            child: Text(
              index.toString(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          // Product Name
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.sizeText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.sizeText!,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          // Quantity
          Expanded(
            flex: 2,
            child: Text(
              item.quantity.toStringAsFixed(0),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Dialog to show previous items
class _PreviousItemsDialog extends StatelessWidget {
  final List<ChallanItem> previousItems;
  
  const _PreviousItemsDialog({
    required this.previousItems,
  });
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.history,
                      color: Color(0xFFB8860B),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Previous Items',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB8860B).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${previousItems.length}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB8860B),
                        ),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF1A1A1A)),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            // Items List
            Expanded(
              child: previousItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No previous items',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    'S.N.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'Name',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Price',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'Quantity',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Table Rows
                          ...previousItems.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            return Container(
                              margin: EdgeInsets.only(
                                bottom: index < previousItems.length - 1 ? 8 : 0,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.grey.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.productName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1A1A1A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (item.sizeText != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Size: ${item.sizeText}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '₹${item.unitPrice.toStringAsFixed(0)}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A1A1A),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      item.quantity.toStringAsFixed(0),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFB8860B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey.shade300),
            const SizedBox(height: 16),
            // Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
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
                  child: const Text('CLOSE'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

