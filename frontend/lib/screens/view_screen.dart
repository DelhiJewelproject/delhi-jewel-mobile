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
import 'order_form_screen.dart';
import 'main_screen.dart';

class ViewScreen extends StatefulWidget {
  const ViewScreen({super.key});

  @override
  State<ViewScreen> createState() => _ViewScreenState();
}

class _ViewScreenState extends State<ViewScreen> with WidgetsBindingObserver {
  final MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _productIdController = TextEditingController();

  bool isScanning = false;
  String? lastScannedCode;
  List<CartItem> cartItems = [];
  bool cameraInitialized = false;
  int _cameraKey = 0; // Key to force camera rebuild
  List<String> _priceCategories = [];
  bool _isLoadingPriceCategories = false;
  Product? _selectedProduct; // Store selected product for display
  ProductSize? _selectedSize; // Store selected size
  List<Product> _allProducts = []; // Store all products for search
  bool _isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _loadPriceCategories();
    _loadAllProducts();
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
    // Resume camera when app comes back to foreground
    if (state == AppLifecycleState.resumed && cameraInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _resumeCamera();
        }
      });
    }
  }

  Future<void> _loadPriceCategories() async {
    setState(() => _isLoadingPriceCategories = true);
    try {
      final options = await ApiService.getChallanOptions();
      if (!mounted) return;
      
      final rawPriceCategories = List<String>.from(options['price_categories'] ?? [])
          .where((name) => name != null && name.toString().isNotEmpty)
          .map((name) => name.toString().trim())
          .toSet()
          .toList()
        ..sort();
      
      setState(() {
        _priceCategories = rawPriceCategories;
        _isLoadingPriceCategories = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPriceCategories = false);
      }
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
            _showPermissionSnackBar();
          }
          return;
        }
      }

      if (status.isPermanentlyDenied) {
        if (mounted) {
          setState(() => cameraInitialized = false);
          _showPermissionSnackBar();
        }
        return;
      }

      // With mobile_scanner v7, the controller is attached and started by the
      // MobileScanner widget itself. Once permissions are granted we just mark
      // the camera as initialized so the widget is built.
      if (mounted) {
        setState(() => cameraInitialized = true);
        // Ensure camera starts after initialization
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && cameraInitialized) {
            try {
              cameraController.start();
            } catch (e) {
              // Camera might already be starting, which is fine
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => cameraInitialized = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera failed: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _initializeCamera,
            ),
          ),
        );
      }
    }
  }

  Future<void> _resumeCamera() async {
    if (kIsWeb) return;
    if (!mounted) return;
    if (!cameraInitialized) {
      // If camera is not initialized, initialize it first
      await _initializeCamera();
      return;
    }

    try {
      // Stop the camera first to ensure clean restart
      try {
        await cameraController.stop();
      } catch (e) {
        // Ignore stop errors - camera might not be running
      }
      
      // Wait a bit before restarting
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Increment camera key to force widget rebuild
      // This ensures MobileScanner widget is recreated and camera restarts
      if (mounted) {
        setState(() {
          _cameraKey++;
        });
      }
      
      // Wait for state update and widget rebuild
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Start the camera
      if (mounted) {
        try {
          await cameraController.start();
          // Verify camera started successfully
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          // If start fails, try to stop and restart
          if (mounted) {
            try {
              await cameraController.stop();
              await Future.delayed(const Duration(milliseconds: 200));
              await cameraController.start();
            } catch (e2) {
              // If still fails, reinitialize
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
      // If all else fails, reinitialize
      if (mounted) {
        setState(() {
          cameraInitialized = false;
        });
        await _initializeCamera();
      }
    }
  }

  void _showPermissionSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Camera permission required'),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Settings',
          textColor: Colors.white,
          onPressed: openAppSettings,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cameraController.dispose();
    _barcodeController.dispose();
    _productIdController.dispose();
    super.dispose();
  }

  // Helper method to check if a cart item matches a product and size combination
  bool _isSameCartItem(CartItem item, Product product, ProductSize? size) {
    // Must be same product
    if (item.product.id != product.id) {
      return false;
    }
    
    // Compare sizes - both null means same, both non-null with same ID means same
    // If one is null and other isn't, they're different sizes (should add as new item)
    final itemSizeId = item.selectedSize?.id;
    final selectedSizeId = size?.id;
    
    if (itemSizeId == null && selectedSizeId == null) {
      return true; // Both null, same size
    }
    if (itemSizeId == null || selectedSizeId == null) {
      return false; // One null, one not - different sizes, add as new item
    }
    return itemSizeId == selectedSizeId; // Both non-null, compare IDs
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
        // Fetch full product details with sizes
        Product? fullProduct = product;
        if (product.id != null) {
          try {
            fullProduct = await ApiService.getProductById(product.id!);
          } catch (e) {
            // Use the product from barcode if getById fails
          }
        }
        
        // Hide keyboard when product is selected
        FocusScope.of(context).unfocus();
        
        setState(() {
          _selectedProduct = fullProduct;
          _selectedSize = fullProduct?.sizes?.isNotEmpty == true ? fullProduct!.sizes!.first : null;
          isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Product not found: ${e.toString()}');
        setState(() => isScanning = false);
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _updateQuantity(int index, int change) {
    setState(() {
      final newQuantity = cartItems[index].quantity + change;
      if (newQuantity > 0) {
        cartItems[index].quantity = newQuantity;
      } else {
        cartItems.removeAt(index);
      }
    });
  }

  void _removeItem(int index) {
    setState(() => cartItems.removeAt(index));
  }

  void _refreshScannerView() {
    setState(() {
      lastScannedCode = null; // Reset last scanned code to allow rescanning
      isScanning = false; // Reset scanning state
      _productIdController.clear(); // Clear product ID input
      _selectedProduct = null; // Clear selected product
      _selectedSize = null; // Clear selected size
    });
    // Resume camera
    // Use post-frame callback to ensure widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _resumeCamera();
      }
    });
  }

  Future<void> _selectProductFromSearch(Product product) async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 50);
    }

    setState(() => isScanning = true);

    try {
      // Fetch full product details with sizes
      Product? fullProduct = product;
      if (product.id != null) {
        try {
          fullProduct = await ApiService.getProductById(product.id!);
        } catch (e) {
          // Use the product from search if getById fails
        }
      }
      
      if (mounted) {
        // Hide keyboard when product is selected
        FocusScope.of(context).unfocus();
        
        setState(() {
          _selectedProduct = fullProduct;
          _selectedSize = fullProduct?.sizes?.isNotEmpty == true ? fullProduct!.sizes!.first : null;
          isScanning = false;
        });
        
        // _showSuccessSnackBar('${fullProduct?.name ?? 'Product'} found');
        // _productIdController.clear();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error loading product: ${e.toString()}');
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
      // First try to find in loaded products by ID/barcode
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
        // Product found in loaded list, fetch full details
        try {
          fullProduct = await ApiService.getProductById(foundProduct.id!);
        } catch (e) {
          fullProduct = foundProduct;
        }
      } else {
        // Try to search by barcode API
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
          // Barcode search failed
        //  throw Exception('Product not found');
        }
      }
      
      if (mounted && fullProduct != null && fullProduct.id != null) {
        // Hide keyboard when product is selected
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
        _showErrorSnackBar('Product not found: ${e.toString()}');
        setState(() => isScanning = false);
      }
    }
  }

  double get _totalCartAmount {
    return cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  Widget _buildPriceHeader(String label, Color color, Color textColor) {
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: textColor,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildPriceCell(double? price, Color color, Color textColor) {
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: price != null ? color.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: price != null ? color.withOpacity(0.3) : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          price != null ? '₹${price.toStringAsFixed(0)}' : '-',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: price != null ? textColor : Colors.grey.shade400,
            fontWeight: price != null ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    
    if (kIsWeb) {
      return _buildWebLayout();
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      resizeToAvoidBottomInset: false, // Keep bottom nav fixed, don't resize body
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content Area
            Column(
          children: [
            // Header
            _buildHeader(),
            
            // Main Content
            Expanded(
              child: _buildScannerTab(isLargeScreen),
            ),
            
                // Spacer for bottom navigation (to prevent content overlap)
                SizedBox(
                  height: 76, // Approximate height of bottom navigation
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'View Page',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Color(0xFF1A1A1A),
              size: 22,
            ),
            onPressed: () {
              FocusScope.of(context).unfocus();
            },
            tooltip: 'Close Keyboard',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerTab(bool isLargeScreen) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Get keyboard height to adjust layout
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        final hasKeyboard = keyboardHeight > 0;
        // Account for bottom navigation height (approximately 60px with margins)
        final bottomNavHeight = hasKeyboard ? 0 : 76.0; // 60px nav + 16px margins
        
        return Column(
          mainAxisSize: MainAxisSize.max,
              children: [
            // QR Scanner Section - reduced by 1/4 inch, hide or shrink when keyboard appears
            if (!hasKeyboard)
                Center(
                  child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  width: 200, // Reduced by 1/4 inch (~25px)
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
                    // Camera View
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

                    // Scanner Overlay
                    if (cameraInitialized)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: ScannerOverlayPainter(isScanning: isScanning),
                        ),
                      ),

                    // Flash and Flip buttons on scanner
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

                    // Scanning Indicator
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

            // Search Section - reduce margin when keyboard appears
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
                                    // Try to search by barcode if no suggestion selected
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
                            // Hide keyboard when product is selected
                            FocusScope.of(context).unfocus();
                            // Clear text field after selection
                            _productIdController.clear();
                                // Fetch full product details with sizes
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

            // Product Details Section - static header, scrollable table
            if (_selectedProduct != null)
              Flexible(
                fit: FlexFit.loose,
                child: LayoutBuilder(
                  builder: (context, productConstraints) {
                    // Calculate available height accounting for keyboard and bottom nav
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
          // Product Name - static
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
          // Tabular format for Sizes and Prices - static header, scrollable rows
          if (product.sizes != null && product.sizes!.isNotEmpty) ...[
            // Table Header - static
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
            // Table Rows - scrollable
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isHighlighted = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isHighlighted ? const Color(0xFFB8860B) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted ? const Color(0xFFB8860B) : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon, 
                color: isHighlighted ? Colors.white : Colors.grey.shade700, 
                size: 18
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isHighlighted ? Colors.white : Colors.grey.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartTab() {
    return Column(
      children: [
        // Cart Summary
        if (cartItems.isNotEmpty)
          // Container(
          //   margin: const EdgeInsets.all(16),
          //   padding: const EdgeInsets.all(20),
          //   decoration: BoxDecoration(
          //     gradient: const LinearGradient(
          //       colors: [Color(0xFFB8860B), Color(0xFFD4AF37)],
          //     ),
          //     borderRadius: BorderRadius.circular(16),
          //     boxShadow: [
          //       BoxShadow(
          //         color: const Color(0xFFB8860B).withOpacity(0.3),
          //         blurRadius: 10,
          //         offset: const Offset(0, 3),
          //       ),
          //     ],
          //   ),
          //   // child: Row(
          //   //   children: [
          //   //     Container(
          //   //       padding: const EdgeInsets.all(10),
          //   //       decoration: BoxDecoration(
          //   //         color: Colors.white.withOpacity(0.9),
          //   //         borderRadius: BorderRadius.circular(12),
          //   //       ),
          //   //       child: const Icon(Icons.receipt_long, color: Color(0xFFB8860B)),
          //   //     ),
          //   //     const SizedBox(width: 12),
          //   //     Expanded(
          //   //       child: Column(
          //   //         crossAxisAlignment: CrossAxisAlignment.start,
          //   //         children: [
          //   //           const Text(
          //   //             'Order Summary',
          //   //             style: TextStyle(
          //   //               color: Colors.white,
          //   //               fontWeight: FontWeight.bold,
          //   //               fontSize: 16,
          //   //             ),
          //   //           ),
          //   //           Text(
          //   //             '${cartItems.length} items • ₹${_totalCartAmount.toStringAsFixed(2)}',
          //   //             style: TextStyle(
          //   //               color: Colors.white.withOpacity(0.9),
          //   //               fontSize: 14,
          //   //             ),
          //   //           ),
          //   //         ],
          //   //       ),
          //   //     ),
          //   //     Container(
          //   //       decoration: BoxDecoration(
          //   //         color: Colors.white,
          //   //         borderRadius: BorderRadius.circular(12),
          //   //         boxShadow: [
          //   //           BoxShadow(
          //   //             color: Colors.black.withOpacity(0.1),
          //   //             blurRadius: 5,
          //   //             offset: const Offset(0, 2),
          //   //           ),
          //   //         ],
          //   //       ),
          //   //       child: ElevatedButton(
          //   //         onPressed: () {
          //   //           Navigator.push(
          //   //             context,
          //   //             MaterialPageRoute(
          //   //               builder: (context) => OrderFormScreen(initialCartItems: cartItems),
          //   //             ),
          //   //           );
          //   //         },
          //   //         style: ElevatedButton.styleFrom(
          //   //           backgroundColor: Colors.white,
          //   //           foregroundColor: const Color(0xFFB8860B),
          //   //           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          //   //           shape: RoundedRectangleBorder(
          //   //             borderRadius: BorderRadius.circular(12),
          //   //           ),
          //   //         ),
          //   //         child: const Text(
          //   //           'Proceed',
          //   //           style: TextStyle(fontWeight: FontWeight.w600),
          //   //         ),
          //   //       ),
          //   //     ),
          //   //   ],
          //   // ),
          // ),

        // Cart Items
        Expanded(
          child: cartItems.isEmpty
              ? _buildEmptyCart()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cartItems.length,
                  itemBuilder: (context, index) => _buildCartItem(index),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 20),
          Text(
            'Your cart is empty',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Scan QR codes to add products',
            style: TextStyle(
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _refreshScannerView,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Start Scanning'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB8860B),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(int index) {
    final item = cartItems[index];
    final product = item.product;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
        children: [
          // Product Header
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFB8860B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.inventory_2, color: const Color(0xFFB8860B)),
            ),
            title: Text(
              product.name ?? 'Product',
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: product.categoryName != null
                ? Text(
                    product.categoryName!,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  )
                : null,
            trailing: IconButton(
              onPressed: () => _removeItem(index),
              icon: Icon(Icons.delete, color: Colors.red.shade400),
            ),
          ),

          // Sizes and Prices Display
          if (product.sizes != null && product.sizes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available Sizes & Prices:',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Fixed Size Column
                            Container(
                              width: 80,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  bottomLeft: Radius.circular(12),
                                ),
                                border: Border(
                                  right: BorderSide(color: Colors.grey.shade300, width: 1),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header
                                  Container(
                                    height: 56,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFB8860B).withOpacity(0.1),
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(12),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Size',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade800,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Size Rows
                                  ...product.sizes!.asMap().entries.map((entry) {
                                    final sizeIndex = entry.key;
                                    final size = entry.value;
                                    final isSelected = item.selectedSize?.id == size.id;
                                    final isLast = sizeIndex == product.sizes!.length - 1;
                                    
                                    return InkWell(
                                      onTap: () {
                                        // If clicking on a different size, add as new cart item
                                        if (!isSelected) {
                                          // Check if this product+size combination already exists
                                          final existingIndex = cartItems.indexWhere((cartItem) => 
                                            _isSameCartItem(cartItem, product, size)
                                          );
                                          
                                          if (existingIndex >= 0) {
                                            // If same product+size exists, just increase quantity
                                            setState(() {
                                              cartItems[existingIndex].quantity++;
                                            });
                                            _showSuccessSnackBar('${product.name} quantity increased');
                                          } else {
                                            // Add new cart item with this size
                                            final unitPrice = size.minPrice ?? 0.0;
                                            setState(() {
                                              cartItems.add(CartItem(
                                                product: product,
                                                selectedSize: size,
                                                quantity: 1,
                                                unitPrice: unitPrice,
                                              ));
                                            });
                                            _showSuccessSnackBar('${product.name} (${size.sizeText ?? 'N/A'}) added to cart');
                                          }
                                        }
                                        // If clicking on already selected size, do nothing (or you could allow changing it)
                                      },
                                      child: Container(
                                        height: 56,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isSelected 
                                              ? const Color(0xFFB8860B).withOpacity(0.1)
                                              : Colors.white,
                                          border: Border(
                                            bottom: isLast 
                                                ? BorderSide.none
                                                : BorderSide(color: Colors.grey.shade200, width: 0.5),
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                size.sizeText ?? 'N/A',
                                                style: TextStyle(
                                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                                  color: isSelected ? const Color(0xFFB8860B) : Colors.black87,
                                                  fontSize: 10,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isSelected) ...[
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.check_circle,
                                                size: 14,
                                                color: const Color(0xFFB8860B),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                            // Scrollable Price Columns
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header Row
                                    Container(
                                      height: 56,
                                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFB8860B).withOpacity(0.1),
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(12),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          _buildPriceHeader('A', Colors.blue, Colors.blue.shade700),
                                          _buildPriceHeader('B', Colors.green, Colors.green.shade700),
                                          _buildPriceHeader('C', Colors.orange, Colors.orange.shade700),
                                          _buildPriceHeader('D', Colors.purple, Colors.purple.shade700),
                                          _buildPriceHeader('E', Colors.red, Colors.red.shade700),
                                          _buildPriceHeader('R', Colors.teal, Colors.teal.shade700),
                                        ],
                                      ),
                                    ),
                                    // Price Rows
                                    ...product.sizes!.asMap().entries.map((entry) {
                                      final sizeIndex = entry.key;
                                      final size = entry.value;
                                      final isSelected = item.selectedSize?.id == size.id;
                                      final isLast = sizeIndex == product.sizes!.length - 1;
                                      
                                      return InkWell(
                                        onTap: () {
                                          // If clicking on a different size, add as new cart item
                                          if (!isSelected) {
                                            // Check if this product+size combination already exists
                                            final existingIndex = cartItems.indexWhere((cartItem) => 
                                              _isSameCartItem(cartItem, product, size)
                                            );
                                            
                                            if (existingIndex >= 0) {
                                              // If same product+size exists, just increase quantity
                                              setState(() {
                                                cartItems[existingIndex].quantity++;
                                              });
                                              _showSuccessSnackBar('${product.name} quantity increased');
                                            } else {
                                              // Add new cart item with this size
                                              final unitPrice = size.minPrice ?? 0.0;
                                              setState(() {
                                                cartItems.add(CartItem(
                                                  product: product,
                                                  selectedSize: size,
                                                  quantity: 1,
                                                  unitPrice: unitPrice,
                                                ));
                                              });
                                              _showSuccessSnackBar('${product.name} (${size.sizeText ?? 'N/A'}) added to cart');
                                            }
                                          }
                                          // If clicking on already selected size, do nothing
                                        },
                                        child: Container(
                                          height: 56,
                                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isSelected 
                                                ? const Color(0xFFB8860B).withOpacity(0.1)
                                                : Colors.white,
                                            border: Border(
                                              bottom: isLast 
                                                  ? BorderSide.none
                                                  : BorderSide(color: Colors.grey.shade200, width: 0.5),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              _buildPriceCell(size.priceA, Colors.blue, Colors.blue.shade700),
                                              _buildPriceCell(size.priceB, Colors.green, Colors.green.shade700),
                                              _buildPriceCell(size.priceC, Colors.orange, Colors.orange.shade700),
                                              _buildPriceCell(size.priceD, Colors.purple, Colors.purple.shade700),
                                              _buildPriceCell(size.priceE, Colors.red, Colors.red.shade700),
                                              _buildPriceCell(size.priceR, Colors.teal, Colors.teal.shade700),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

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
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const MainScreen()),
                (route) => false,
              );
            },
            isHighlighted: true,
          ),
          _buildTextButton(
            label: 'Add Quantity',
            onTap: _selectedProduct != null ? _showAddQuantityDialog : null,
            isHighlighted: _selectedProduct != null,
          ),
        ],
      ),
    );
  }

  // Helper function to get price by category
  double? _getPriceByCategory(ProductSize? size, String category) {
    if (size == null) return null;
    final cat = category.toUpperCase().trim();
    switch (cat) {
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
        if (cat.contains('A')) return size.priceA;
        if (cat.contains('B')) return size.priceB;
        if (cat.contains('C')) return size.priceC;
        if (cat.contains('D')) return size.priceD;
        if (cat.contains('E')) return size.priceE;
        if (cat.contains('R')) return size.priceR;
        return size.minPrice;
    }
  }

  Future<void> _showPriceCategoryDialog() async {
    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add items to cart first'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    String? selectedPriceCategory;

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            width: MediaQuery.of(context).size.width * 0.8,
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB8860B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.category_outlined,
                          color: Color(0xFFB8860B),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Select Price Category',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                            fontSize: 22,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Price Category *',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedPriceCategory,
                    decoration: InputDecoration(
                      hintText: 'Select price category',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(Icons.category_outlined, color: Color(0xFFB8860B), size: 22),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFB8860B), width: 2),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    dropdownColor: Colors.white,
                    iconEnabledColor: const Color(0xFFB8860B),
                    iconSize: 24,
                    isExpanded: true,
                    items: _priceCategories
                        .map((category) => DropdownMenuItem(
                              value: category,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  category,
                                  style: const TextStyle(
                                    color: Color(0xFF1A1A1A),
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ))
                        .toList(),
                    selectedItemBuilder: (BuildContext context) {
                      return _priceCategories.map<Widget>((String category) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            category,
                            style: const TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList();
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select a price category';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      setDialogState(() {
                        selectedPriceCategory = value;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            if (selectedPriceCategory == null || selectedPriceCategory!.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please select a price category'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            Navigator.pop(context);
                            
                            // Send ALL cart items to order form, preserving all quantities
                            if (cartItems.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cart is empty'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            
                            // Update ALL cart items with prices from selected category, preserving ALL quantities
                            final updatedCartItems = cartItems.map((item) {
                              double newUnitPrice = item.unitPrice; // Keep existing price as fallback
                              
                              // Get price from selected category if size is available
                              if (item.selectedSize != null && selectedPriceCategory != null) {
                                final categoryPrice = _getPriceByCategory(
                                  item.selectedSize,
                                  selectedPriceCategory!,
                                );
                                if (categoryPrice != null && categoryPrice > 0) {
                                  newUnitPrice = categoryPrice;
                                }
                              }
                              
                              // Explicitly preserve the quantity - don't rely on defaults
                              final itemQuantity = item.quantity; // Capture quantity explicitly
                              
                              final newCartItem = CartItem(
                                product: item.product,
                                selectedSize: item.selectedSize,
                                quantity: itemQuantity, // Explicitly preserve original quantity
                                unitPrice: newUnitPrice, // Use price from selected category
                              );
                              
                              // Verify quantity was preserved
                              if (newCartItem.quantity != itemQuantity) {
                                // Quantity mismatch detected but continue
                              }
                              
                              return newCartItem;
                            }).toList();
                            
                            // Navigate to order form with ALL cart items
                            // Await result to update cartItems when returning
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => OrderFormScreen(
                                  initialCartItems: updatedCartItems,
                                  initialPriceCategory: selectedPriceCategory,
                                  initialQuantity: 1, // This is just for the quantity controller, not cart items
                                ),
                              ),
                            );
                            
                            // Update cartItems with returned data if available
                            if (result != null && result is List<CartItem>) {
                              setState(() {
                                cartItems = result;
                              });
                            }
                            
                            // Resume camera when returning to scanner view
                            // Use post-frame callback to ensure widget is built
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _resumeCamera();
                              }
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB8860B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'OK',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
  }

  Future<void> _showAddQuantityDialog() async {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please scan or search for a product first'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // COMMENTED OUT - Dialog popup code
    // final quantityController = TextEditingController(text: '1');
    // final formKey = GlobalKey<FormState>();
    // await showDialog(...);

    // Direct navigation to order form screen
                              // Check if size is selected
                              if (_selectedSize == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please select a size'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }
                              
                              // Get price from Category A (default)
                              double unitPrice = 0.0;
                              final categoryPrice = _selectedSize!.priceA;
                              if (categoryPrice != null && categoryPrice > 0) {
                                unitPrice = categoryPrice;
                              } else {
                                unitPrice = _selectedSize!.minPrice ?? 0.0;
                              }
                              
    // Create cart item with default quantity of 1
                              final cartItem = CartItem(
                                product: _selectedProduct!,
                                selectedSize: _selectedSize,
      quantity: 1, // Default quantity
                                unitPrice: unitPrice,
                              );
                              
    // Navigate directly to order form with the cart item (default to Category A)
                              // Pass existing cart items to preserve them
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => OrderFormScreen(
                                    initialCartItems: cartItems.isEmpty ? [cartItem] : [...cartItems, cartItem],
                                    initialPriceCategory: 'A', // Default to Category A
          initialQuantity: 1, // Default quantity
                                  ),
                                ),
                              );
                              
                              // Update cart items with returned data (preserve cart across navigation)
                              if (result != null && result is List<CartItem>) {
                                setState(() {
                                  cartItems = result;
                                });
                              } else {
                                // If no result, add the item to local cart
                                setState(() {
                                  cartItems.add(cartItem);
                                });
                              }
                              
                              // Clear selection after navigation
                              setState(() {
                                _selectedProduct = null;
                                _selectedSize = null;
                                _productIdController.clear();
                                lastScannedCode = null;
                              });
                              
                              // Resume camera when returning to view screen
                              // Use multiple delayed callbacks to ensure camera resumes after navigation completes
                              Future.delayed(const Duration(milliseconds: 500), () {
                                if (mounted && cameraInitialized) {
                                  // First ensure widget is built
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    // Then wait a bit more and resume camera
                                    Future.delayed(const Duration(milliseconds: 300), () {
                                      if (mounted && cameraInitialized) {
                                        _resumeCamera();
                                      }
                                    });
                                  });
                                }
                              });
  }

  Widget _buildTextButton({
    required String label,
    VoidCallback? onTap,
    bool isHighlighted = false,
    int badgeCount = 0,
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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
                  Text(
                    label,
                    style: TextStyle(
                  color: isEnabled && isHighlighted ? Colors.white : Colors.grey.shade500,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : badgeCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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


  Widget _buildWebLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Web Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB8860B), Color(0xFFD4AF37)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB8860B).withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: Colors.white, size: 32),
                    SizedBox(width: 16),
                    Text(
                      'QR Code Scanner',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Web Content
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Scanner Section
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.all(24),
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
                        child: Column(
                          children: [
                            const Icon(
                              Icons.qr_code_2,
                              size: 60,
                              color: Color(0xFFB8860B),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Manual Entry',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _barcodeController,
                              decoration: InputDecoration(
                                hintText: 'Enter barcode or product ID',
                                hintStyle: TextStyle(color: Colors.grey.shade500),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              onSubmitted: (value) {
                                if (value.isNotEmpty) {
                                  _searchProductById(value);
                                }
                              },
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  if (_barcodeController.text.isNotEmpty) {
                                    _searchProductById(_barcodeController.text);
                                  }
                                },
                                icon: const Icon(Icons.search),
                                label: const Text('Search Product'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFB8860B),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 24),

                    // Cart Section
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(
                            child: _buildCartTab(),
                          ),
                          // Add action buttons for web mode
                          if (cartItems.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 16),
                              padding: const EdgeInsets.all(16),
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
                                  Expanded(
                                    child: _buildTextButton(
                                      label: 'Next',
                                      onTap: _showPriceCategoryDialog,
                                      isHighlighted: true,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildTextButton(
                                      label: 'Add Quantity',
                                      onTap: _showAddQuantityDialog,
                                      isHighlighted: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
    final scannerSize = size.width * 0.8; // 80% of container width

    // Draw scanner square
    final scannerRect = Rect.fromCenter(
      center: center,
      width: scannerSize,
      height: scannerSize,
    );
    canvas.drawRect(scannerRect, paint);

    // Draw corner accents
    final cornerPaint = Paint()
      ..color = isScanning ? const Color(0xFF10B981) : const Color(0xFFB8860B)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final cornerLength = scannerSize * 0.15; // 15% of scanner size
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