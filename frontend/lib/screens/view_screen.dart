import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';
import '../models/product.dart';
import '../models/product_size.dart';
import '../models/cart_item.dart';

class ViewScreen extends StatefulWidget {
  const ViewScreen({super.key});

  @override
  State<ViewScreen> createState() => _ViewScreenState();
}

class _ViewScreenState extends State<ViewScreen> {
  final MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  final TextEditingController _barcodeController = TextEditingController();
  
  bool isScanning = false;
  String? lastScannedCode;
  List<CartItem> cartItems = [];
  bool cameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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
            setState(() {
              cameraInitialized = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Camera permission is required. Please grant permission in settings.'),
                backgroundColor: Colors.red.shade600,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Open Settings',
                  textColor: Colors.white,
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
          return;
        }
      }
      
      if (status.isPermanentlyDenied) {
        if (mounted) {
          setState(() {
            cameraInitialized = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Camera permission is permanently denied. Please enable it in app settings.'),
              backgroundColor: Colors.red.shade600,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Open Settings',
                textColor: Colors.white,
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return;
      }
      
      try {
        if (cameraController.isStarting) {
          await cameraController.stop();
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        // Camera might not be running, continue anyway
      }
      
      int retries = 3;
      bool started = false;
      
      while (retries > 0 && !started && mounted) {
        try {
          await cameraController.start();
          started = true;
          if (mounted) {
            setState(() {
              cameraInitialized = true;
            });
          }
        } catch (e) {
          retries--;
          if (retries > 0) {
            await Future.delayed(const Duration(milliseconds: 500));
          } else {
            throw e;
          }
        }
      }
      
    } catch (e) {
      if (mounted) {
        setState(() {
          cameraInitialized = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera initialization failed: ${e.toString()}'),
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

  @override
  void dispose() {
    cameraController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture barcodeCapture) async {
    if (isScanning) return;
    
    final List<Barcode> barcodes = barcodeCapture.barcodes;
    if (barcodes.isEmpty) return;

    final String? barcode = barcodes.first.rawValue;
    if (barcode == null || barcode.isEmpty) return;
    
    if (lastScannedCode == barcode) return;
    lastScannedCode = barcode;

    setState(() {
      isScanning = true;
    });

    try {
      final product = await ApiService.getProductByBarcode(barcode);
      
      if (mounted) {
        // Check if product already in cart
        final existingIndex = cartItems.indexWhere(
          (item) => item.product.id == product.id
        );
        
        if (existingIndex >= 0) {
          // Product already in cart, increase quantity
          setState(() {
            cartItems[existingIndex].quantity++;
            isScanning = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${product.name} quantity increased'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 1),
            ),
          );
        } else {
          // New product - add to cart with first available size
          setState(() {
            if (product.sizes != null && product.sizes!.isNotEmpty) {
              cartItems.add(CartItem(
                product: product,
                selectedSize: product.sizes!.first,
                quantity: 1,
              ));
            } else {
              cartItems.add(CartItem(
                product: product,
                selectedSize: null,
                quantity: 1,
              ));
            }
            isScanning = false;
          });
          
          // Scroll to bottom to show new item
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product not found: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {
          isScanning = false;
        });
      }
    }
  }

  void _updateQuantity(int index, int change) {
    if (index >= cartItems.length) return;
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
    setState(() {
      cartItems.removeAt(index);
    });
  }

  double get _totalCartAmount {
    return cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A2E),
                const Color(0xFF16213E),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 80,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      'Enter Product Barcode',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _barcodeController,
                        decoration: InputDecoration(
                          labelText: 'Barcode / QR Code',
                          prefixIcon: const Icon(Icons.qr_code_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        onSubmitted: (value) async {
                          if (value.isEmpty) return;
                          setState(() => isScanning = true);
                          try {
                            final product = await ApiService.getProductByBarcode(value);
                            setState(() {
                              if (product.sizes != null && product.sizes!.isNotEmpty) {
                                cartItems.add(CartItem(
                                  product: product,
                                  selectedSize: product.sizes!.first,
                                  quantity: 1,
                                ));
                              } else {
                                cartItems.add(CartItem(
                                  product: product,
                                  selectedSize: null,
                                  quantity: 1,
                                ));
                              }
                              isScanning = false;
                            });
                            _barcodeController.clear();
                          } catch (e) {
                            setState(() => isScanning = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: ${e.toString()}')),
                            );
                          }
                        },
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Top Third: Camera View (Reduced Size)
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                // Camera
                Positioned.fill(
                  child: cameraInitialized
                      ? MobileScanner(
                          controller: cameraController,
                          onDetect: (BarcodeCapture capture) {
                            _handleBarcode(capture);
                          },
                        )
                      : Container(
                          color: Colors.black,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(
                                  color: Color(0xFF6366F1),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Initializing Camera...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ElevatedButton(
                                  onPressed: _initializeCamera,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                  ),
                                  child: const Text('Retry Camera'),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                
                // Top Header
                SafeArea(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Scan QR Code',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (cartItems.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF10B981), Color(0xFF059669)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${cartItems.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                
                // Scanning indicator
                if (isScanning)
                  Container(
                    color: Colors.black.withOpacity(0.7),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Bottom Two-Thirds: Scanned Products List (Larger)
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shopping_cart_rounded, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Scanned Products',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${cartItems.length} item${cartItems.length != 1 ? 's' : ''}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (cartItems.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '₹${_totalCartAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Products List
                  Expanded(
                    child: cartItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.qr_code_scanner_outlined,
                                  size: 80,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Scan products to add them here',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: cartItems.length,
                            itemBuilder: (context, index) {
                              return _buildCartItemCard(index);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(int index) {
    final item = cartItems[index];
    final product = item.product;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Product Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name ?? 'Product',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (product.categoryName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              product.categoryName!,
                              style: const TextStyle(
                                color: Color(0xFF6366F1),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _removeItem(index),
                ),
              ],
            ),
          ),
          
          // Size Selection with All Price Tiers
          if (product.sizes != null && product.sizes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.straighten_outlined, size: 18, color: Color(0xFF6366F1)),
                      SizedBox(width: 8),
                      Text(
                        'Select Size & Price Tier:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Size Selection Buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: product.sizes!.map((size) {
                      final isSelected = item.selectedSize?.id == size.id;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            item.selectedSize = size;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6366F1)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF6366F1)
                                  : Colors.grey.shade300,
                              width: isSelected ? 2.5 : 1,
                            ),
                          ),
                          child: Text(
                            size.sizeText ?? 'N/A',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Price Tiers Grid (A, B, C, D, E, R)
                  if (item.selectedSize != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Price Tiers for ${item.selectedSize!.sizeText ?? "Selected Size"}:',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (item.selectedSize!.priceA != null)
                                _buildPriceChip('A', item.selectedSize!.priceA!, Colors.blue),
                              if (item.selectedSize!.priceB != null)
                                _buildPriceChip('B', item.selectedSize!.priceB!, Colors.green),
                              if (item.selectedSize!.priceC != null)
                                _buildPriceChip('C', item.selectedSize!.priceC!, Colors.orange),
                              if (item.selectedSize!.priceD != null)
                                _buildPriceChip('D', item.selectedSize!.priceD!, Colors.purple),
                              if (item.selectedSize!.priceE != null)
                                _buildPriceChip('E', item.selectedSize!.priceE!, Colors.red),
                              if (item.selectedSize!.priceR != null)
                                _buildPriceChip('R', item.selectedSize!.priceR!, Colors.teal),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          
          // Quantity and Price
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                // Quantity Controls
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 20),
                        onPressed: () => _updateQuantity(index, -1),
                        color: const Color(0xFF6366F1),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '${item.quantity}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 20),
                        onPressed: () => _updateQuantity(index, 1),
                        color: const Color(0xFF6366F1),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Total Price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '₹${item.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceChip(String label, double price, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${price.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
