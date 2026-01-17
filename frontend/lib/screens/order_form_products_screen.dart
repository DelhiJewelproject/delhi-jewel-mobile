import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../services/api_service.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/product_size.dart';
import '../models/challan.dart';
import 'order_form_screen.dart';
import 'order_form_add_quantity_screen.dart' show OrderFormAddQuantityScreen, OrderFormReturnData;

class OrderFormProductsScreen extends StatefulWidget {
  final String partyName;
  final String orderNumber;
  final Map<String, dynamic> orderData;
  final List<Product>? initialProducts; // Products from order_form_add_quantity_screen
  final List<dynamic>? initialStoredItems; // Stored items from order_form_add_quantity_screen
  final Map<String, Map<String, int>>? initialDesignAllocations; // Design allocations from order_form_add_quantity_screen

  const OrderFormProductsScreen({
    super.key,
    required this.partyName,
    required this.orderNumber,
    required this.orderData,
    this.initialProducts,
    this.initialStoredItems,
    this.initialDesignAllocations,
  });

  @override
  State<OrderFormProductsScreen> createState() => _OrderFormProductsScreenState();
}

class _OrderFormProductsScreenState extends State<OrderFormProductsScreen> with WidgetsBindingObserver {
  final MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  final TextEditingController _productIdController = TextEditingController();

  bool isScanning = false;
  String? lastScannedCode;
  bool cameraInitialized = false;
  int _cameraKey = 0;
  Product? _selectedProduct;
  ProductSize? _selectedSize;
  List<Product> _allProducts = [];
  List<Product> _selectedProducts = []; // Store selected products
  List<ChallanItem> _storedItems = []; // Store items from add quantity screen
  Map<String, Map<String, int>> _designAllocations = {}; // Store design allocations from add quantity screen
  bool _isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _loadAllProducts();
    // Initialize with products from order_form_add_quantity_screen if provided
    if (widget.initialProducts != null) {
      _selectedProducts = List<Product>.from(widget.initialProducts!);
    }
    // Initialize with stored items from order_form_add_quantity_screen if provided
    if (widget.initialStoredItems != null) {
      _storedItems = widget.initialStoredItems!.map((item) => item as ChallanItem).toList();
    }
    // Initialize with design allocations from order_form_add_quantity_screen if provided
    if (widget.initialDesignAllocations != null) {
      _designAllocations = Map<String, Map<String, int>>.from(
        widget.initialDesignAllocations!.map(
          (key, value) => MapEntry(key, Map<String, int>.from(value))
        )
      );
    }
  }

  Future<void> _loadAllProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final products = await ApiService.getAllProducts();
      if (!mounted) return;
      setState(() {
        _allProducts = products;
        _isLoadingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingProducts = false);
    }
  }

  List<Product> _getFilteredProducts(String searchQuery) {
    if (searchQuery.isEmpty) {
      return _allProducts.take(30).toList();
    }
    final search = searchQuery.toLowerCase();
    return _allProducts
        .where((product) {
          final name = (product.name ?? '').toLowerCase();
          final externalId = product.externalId?.toString().toLowerCase() ?? '';
          final categoryName = (product.categoryName ?? '').toLowerCase();
          return name.contains(search) ||
              externalId.contains(search) ||
              categoryName.contains(search);
        })
        .take(30)
        .toList();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && cameraInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _resumeCamera();
        }
      });
    }
  }

  Future<void> _initializeCamera() async {
    if (kIsWeb) return;
    if (!mounted) return;

    try {
      final status = await Permission.camera.status;
      
      if (status.isDenied) {
        final newStatus = await Permission.camera.request();
        if (newStatus.isDenied || newStatus.isPermanentlyDenied) {
          if (mounted) {
            setState(() => cameraInitialized = false);
          }
          return;
        }
      }

      if (status.isPermanentlyDenied) {
        if (mounted) {
          setState(() => cameraInitialized = false);
        }
        return;
      }

      if (mounted) {
        setState(() => cameraInitialized = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && cameraInitialized) {
            try {
              cameraController.start();
            } catch (e) {
              // Camera might already be starting
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => cameraInitialized = false);
      }
    }
  }

  Future<void> _resumeCamera() async {
    if (kIsWeb) return;
    if (!mounted) return;
    if (!cameraInitialized) {
      await _initializeCamera();
      return;
    }

    try {
      try {
        await cameraController.stop();
      } catch (e) {
        // Ignore stop errors
      }
      
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (mounted) {
        setState(() {
          _cameraKey++;
        });
      }
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        try {
          await cameraController.start();
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          if (mounted) {
            try {
              await cameraController.stop();
              await Future.delayed(const Duration(milliseconds: 200));
              await cameraController.start();
            } catch (e2) {
              if (mounted) {
                setState(() {
                  cameraInitialized = false;
                });
                await _initializeCamera();
              }
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          cameraInitialized = false;
        });
        await _initializeCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cameraController.dispose();
    _productIdController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture barcodeCapture) async {
    if (isScanning) return;

    final barcodes = barcodeCapture.barcodes;
    if (barcodes.isEmpty) return;

    final String? barcode = barcodes.first.rawValue;
    if (barcode == null || barcode.isEmpty) return;

    if (lastScannedCode == barcode) return;
    lastScannedCode = barcode;

    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 100);
    }

    setState(() => isScanning = true);

    try {
      final product = await ApiService.getProductByBarcode(barcode);
      
      if (mounted) {
        Product? fullProduct = product;
        if (product.id != null) {
          try {
            fullProduct = await ApiService.getProductById(product.id!);
          } catch (e) {
            // Use the product from barcode if getById fails
          }
        }
        
        FocusScope.of(context).unfocus();
        
        setState(() {
          _selectedProduct = fullProduct;
          _selectedSize = fullProduct?.sizes?.isNotEmpty == true ? fullProduct!.sizes!.first : null;
          isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isScanning = false);
      }
    }
  }

  Future<void> _selectProductFromSearch(Product product) async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 50);
    }

    setState(() => isScanning = true);

    try {
      Product? fullProduct = product;
      if (product.id != null) {
        try {
          fullProduct = await ApiService.getProductById(product.id!);
        } catch (e) {
          // Use the product from search if getById fails
        }
      }
      
      if (mounted) {
        FocusScope.of(context).unfocus();
        
        setState(() {
          _selectedProduct = fullProduct;
          _selectedSize = fullProduct?.sizes?.isNotEmpty == true ? fullProduct!.sizes!.first : null;
          isScanning = false;
        });
        
        _productIdController.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() => isScanning = false);
      }
    }
  }

  Future<void> _searchProductById(String productId) async {
    if (productId.isEmpty) return;

    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 50);
    }

    setState(() => isScanning = true);

    try {
      final search = productId.trim().toLowerCase();
      final foundProduct = _allProducts.firstWhere(
        (product) {
          final externalId = product.externalId?.toString().toLowerCase() ?? '';
          return externalId == search;
        },
        orElse: () => Product(),
      );

      Product? fullProduct;
      if (foundProduct.id != null) {
        try {
          fullProduct = await ApiService.getProductById(foundProduct.id!);
        } catch (e) {
          fullProduct = foundProduct;
        }
      } else {
        try {
          final product = await ApiService.getProductByBarcode(productId.trim());
          if (product.id != null) {
            try {
              fullProduct = await ApiService.getProductById(product.id!);
            } catch (e) {
              fullProduct = product;
            }
          } else {
            fullProduct = product;
          }
        } catch (e) {
          throw Exception('Product not found');
        }
      }
      
      if (mounted && fullProduct != null && fullProduct.id != null) {
        FocusScope.of(context).unfocus();
        
        setState(() {
          _selectedProduct = fullProduct;
          _selectedSize = fullProduct?.sizes?.isNotEmpty == true ? fullProduct!.sizes!.first : null;
          isScanning = false;
        });
        
        _productIdController.clear();
      } else {
        throw Exception('Product not found');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isScanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    
    if (kIsWeb) {
      return _buildWebLayout();
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content Area
            Column(
              children: [
                // Header with Party Name and Order Number (Tabular)
                _buildHeader(),
                
                // Main Content
                Expanded(
                  child: _buildScannerTab(isLargeScreen),
                ),
                
                // Spacer for bottom navigation
                SizedBox(
                  height: 76,
                ),
              ],
            ),
            
            // Bottom Navigation - Fixed at bottom of screen
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomNavigation(),
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

  Widget _buildScannerTab(bool isLargeScreen) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        final hasKeyboard = keyboardHeight > 0;
        final bottomNavHeight = hasKeyboard ? 0 : 76.0;
        
        return Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // QR Scanner Section
            if (!hasKeyboard)
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 15,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        cameraInitialized
                            ? MobileScanner(
                                key: ValueKey('camera_$_cameraKey'),
                                controller: cameraController,
                                onDetect: _handleBarcode,
                              )
                            : Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.grey,
                                      Colors.white,
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const CircularProgressIndicator(
                                        color: Color(0xFFB8860B),
                                        strokeWidth: 2,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Initializing...',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                        if (cameraInitialized)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: ScannerOverlayPainter(isScanning: isScanning),
                            ),
                          ),

                        if (cameraInitialized)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: IconButton(
                              icon: const Icon(Icons.flash_on, color: Colors.white, size: 20),
                              onPressed: () => cameraController.toggleTorch(),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black.withOpacity(0.5),
                                padding: const EdgeInsets.all(6),
                              ),
                            ),
                          ),
                        if (cameraInitialized)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 20),
                              onPressed: () => cameraController.switchCamera(),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black.withOpacity(0.5),
                                padding: const EdgeInsets.all(6),
                              ),
                            ),
                          ),

                        if (isScanning)
                          Container(
                            color: Colors.black.withOpacity(0.4),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFFB8860B),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Processing...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // Search Section
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final isDark = theme.brightness == Brightness.dark;
                final textColor = isDark ? Colors.white : const Color(0xFF000000);
                final hintColor = isDark ? Colors.grey.shade400 : const Color(0xFF999999);
                final containerColor = isDark ? Colors.grey.shade800 : Colors.white;
                final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
                final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
                final hasKeyboard = keyboardHeight > 0;
                
                return Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: hasKeyboard ? 0 : 8,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: hasKeyboard ? 4 : 8,
                  ),
                  decoration: BoxDecoration(
                    color: containerColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderColor,
                      width: 1,
                    ),
                  ),
                  child: _isLoadingProducts
                      ? Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB8860B)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Loading products...',
                              style: TextStyle(
                                color: isDark ? Colors.grey.shade300 : const Color(0xFF666666),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        )
                      : TypeAheadField<Product>(
                          controller: _productIdController,
                          builder: (context, controller, focusNode) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                hintText: 'Search by Name, ID or Barcode',
                                hintStyle: TextStyle(color: hintColor),
                                border: InputBorder.none,
                                prefixIcon: const Icon(Icons.search, color: Color(0xFFB8860B)),
                              ),
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                              onSubmitted: (value) {
                                if (value.isNotEmpty && _selectedProduct == null) {
                                  _searchProductById(value);
                                }
                              },
                            );
                          },
                          suggestionsCallback: (pattern) async {
                            if (pattern.isEmpty) {
                              return _allProducts.take(30).toList();
                            }
                            return _getFilteredProducts(pattern);
                          },
                          itemBuilder: (context, Product suggestion) {
                            final suggestionBgColor = isDark ? Colors.grey.shade900 : Colors.white;
                            final suggestionTextColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
                            final suggestionSubtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
                            final suggestionBorderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade200;
                            
                            return Container(
                              decoration: BoxDecoration(
                                color: suggestionBgColor,
                                border: Border(
                                  bottom: BorderSide(
                                    color: suggestionBorderColor,
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
                                    color: const Color(0xFFB8860B).withOpacity(0.1),
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
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: suggestionTextColor,
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
                                    color: suggestionSubtitleColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                tileColor: suggestionBgColor,
                              ),
                            );
                          },
                          onSelected: (Product product) {
                            FocusScope.of(context).unfocus();
                            _productIdController.clear();
                            _selectProductFromSearch(product);
                          },
                          hideOnEmpty: false,
                          hideOnError: false,
                          hideOnLoading: false,
                          debounceDuration: const Duration(milliseconds: 300),
                        ),
                );
              },
            ),

            SizedBox(height: hasKeyboard ? 0 : 8),

            // Product Details Section
            if (_selectedProduct != null)
              Flexible(
                fit: FlexFit.loose,
                child: LayoutBuilder(
                  builder: (context, productConstraints) {
                    final availableHeight = hasKeyboard 
                        ? (constraints.maxHeight - keyboardHeight - bottomNavHeight).clamp(0.0, 200.0)
                        : (constraints.maxHeight - bottomNavHeight).clamp(0.0, double.infinity);
                    
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: availableHeight,
                      ),
                      child: _buildProductDetails(),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildProductDetails() {
    final product = _selectedProduct!;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final hasKeyboard = keyboardHeight > 0;
    
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: hasKeyboard ? 0 : 4,
      ),
      padding: EdgeInsets.all(hasKeyboard ? 4 : 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 4,
              vertical: hasKeyboard ? 0 : 4,
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2, color: Color(0xFFB8860B), size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    product.name ?? 'Product',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: hasKeyboard ? 2 : 8),
          if (product.sizes != null && product.sizes!.isNotEmpty) ...[
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: hasKeyboard ? 4 : 8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFB8860B).withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Size',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Price (A)',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: product.sizes!.length,
                itemBuilder: (context, index) {
                  final sizeItem = product.sizes![index];
                  final priceA = sizeItem.priceA ?? 0.0;
                  final isSelected = sizeItem.id == _selectedSize?.id;
                  final isLast = index == product.sizes!.length - 1;
                  
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedSize = sizeItem;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? const Color(0xFFB8860B).withOpacity(0.1)
                            : Colors.white,
                        border: Border(
                          bottom: isLast 
                              ? BorderSide.none
                              : BorderSide(color: Colors.grey.shade200, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Row(
                              children: [
                                Text(
                                  sizeItem.sizeText ?? 'N/A',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: const Color(0xFF1A1A1A),
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFFB8860B),
                                    size: 16,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '₹${priceA.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFB8860B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text(
                'No sizes available',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF666666),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildTextButton(
            label: 'Back',
            onTap: () {
              // Return the selected products, stored items, and design allocations when going back
              Navigator.pop(
                context,
                OrderFormReturnData(
                  products: _selectedProducts,
                  storedItems: _storedItems,
                  designAllocations: _designAllocations,
                ),
              );
            },
            isHighlighted: true,
          ),
          _buildTextButton(
            label: 'Add Quantity',
            onTap: _selectedProduct != null ? () async {
              // Add selected product to the list if not already present
              if (_selectedProduct != null && _selectedProduct!.id != null) {
                final productId = _selectedProduct!.id!;
                if (!_selectedProducts.any((p) => p.id == productId)) {
                  setState(() {
                    _selectedProducts.add(_selectedProduct!);
                  });
                }
              }
              
              // Navigate to add quantity screen - send all sizes like challan_product_selection_screen
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OrderFormAddQuantityScreen(
                    partyName: widget.partyName,
                    orderNumber: widget.orderNumber,
                    orderData: widget.orderData,
                    selectedProduct: _selectedProduct!,
                    selectedSize: _selectedSize, // Optional - we'll use all sizes anyway
                    initialProducts: _selectedProducts, // Pass current selected products
                    initialStoredItems: _storedItems, // Pass stored items to preserve them
                    initialDesignAllocations: _designAllocations, // Pass design allocations to preserve them
                  ),
                ),
              );
              
              // Update selected products, stored items, and design allocations if returned from add quantity screen
              if (result != null && mounted) {
                // Check if result is OrderFormReturnData (new format) or List<Product> (old format for backward compatibility)
                if (result is OrderFormReturnData) {
                  setState(() {
                    _selectedProducts = result.products;
                    _storedItems = result.storedItems.map((item) => item.copyWith()).toList();
                    _designAllocations.clear();
                    _designAllocations.addAll(
                      result.designAllocations.map(
                        (key, value) => MapEntry(key, Map<String, int>.from(value))
                      )
                    );
                    print('Updated stored items from OrderFormAddQuantityScreen: ${_storedItems.length} items');
                  });
                } else if (result is List<Product>) {
                  // Backward compatibility: if it's just a list of products
                  setState(() {
                    _selectedProducts = result;
                  });
                }
              }
            } : null,
            isHighlighted: _selectedProduct != null,
          ),
        ],
      ),
    );
  }

  Widget _buildTextButton({
    required String label,
    VoidCallback? onTap,
    bool isHighlighted = false,
  }) {
    final isEnabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isEnabled && isHighlighted ? const Color(0xFFB8860B) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEnabled && isHighlighted ? const Color(0xFFB8860B) : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isEnabled && isHighlighted ? Colors.white : Colors.grey.shade500,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              Expanded(
                child: _buildScannerTab(false),
              ),
              const SizedBox(height: 24),
              // Bottom Navigation Buttons for Web
              _buildBottomNavigation(),
            ],
          ),
        ),
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  final bool isScanning;

  ScannerOverlayPainter({required this.isScanning});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isScanning ? const Color(0xFF10B981) : const Color(0xFFB8860B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final center = Offset(size.width / 2, size.height / 2);
    final scannerSize = size.width * 0.8;

    final scannerRect = Rect.fromCenter(
      center: center,
      width: scannerSize,
      height: scannerSize,
    );
    canvas.drawRect(scannerRect, paint);

    final cornerPaint = Paint()
      ..color = isScanning ? const Color(0xFF10B981) : const Color(0xFFB8860B)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final cornerLength = scannerSize * 0.15;
    final cornerOffset = scannerSize / 2;

    // Top left
    canvas.drawLine(
      center + Offset(-cornerOffset, -cornerOffset),
      center + Offset(-cornerOffset + cornerLength, -cornerOffset),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(-cornerOffset, -cornerOffset),
      center + Offset(-cornerOffset, -cornerOffset + cornerLength),
      cornerPaint,
    );

    // Top right
    canvas.drawLine(
      center + Offset(cornerOffset, -cornerOffset),
      center + Offset(cornerOffset - cornerLength, -cornerOffset),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(cornerOffset, -cornerOffset),
      center + Offset(cornerOffset, -cornerOffset + cornerLength),
      cornerPaint,
    );

    // Bottom left
    canvas.drawLine(
      center + Offset(-cornerOffset, cornerOffset),
      center + Offset(-cornerOffset + cornerLength, cornerOffset),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(-cornerOffset, cornerOffset),
      center + Offset(-cornerOffset, cornerOffset - cornerLength),
      cornerPaint,
    );

    // Bottom right
    canvas.drawLine(
      center + Offset(cornerOffset, cornerOffset),
      center + Offset(cornerOffset - cornerLength, cornerOffset),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(cornerOffset, cornerOffset),
      center + Offset(cornerOffset, cornerOffset - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

