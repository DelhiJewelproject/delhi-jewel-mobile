import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:vibration/vibration.dart';

import '../models/product.dart';
import '../models/product_size.dart';
import '../services/api_service.dart';
import 'check_price_manual_screen.dart';

class CategorySelectionScanScreen extends StatefulWidget {
  const CategorySelectionScanScreen({super.key});

  @override
  State<CategorySelectionScanScreen> createState() =>
      _CategorySelectionScanScreenState();
}

class _CategorySelectionScanScreenState
    extends State<CategorySelectionScanScreen> {
  final TextEditingController _categoryController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  List<String> _priceCategories = [];
  String? _selectedPriceCategory;
  bool _isLoading = false;
  bool _isScanning = false;
  Product? _scannedProduct;
  String? _lastScannedCode;

  @override
  void initState() {
    super.initState();
    _loadPriceCategories();
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _loadPriceCategories() async {
    setState(() => _isLoading = true);
    try {
      final options = await ApiService.getChallanOptions(quick: false);
      if (!mounted) return;
      
      // Extract price categories
      final priceCategories = List<String>.from(options['price_categories'] ?? [])
          .where((name) => name != null && name.toString().isNotEmpty)
          .map((name) => name.toString().trim())
          .toSet()
          .toList()
        ..sort();

      setState(() {
        _priceCategories = priceCategories;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load price categories: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Future<void> _handlePriceCategorySelected(String priceCategory) async {
    setState(() {
      _selectedPriceCategory = priceCategory;
      _categoryController.text = priceCategory;
    });

    // Navigate to check price manual screen with selected price category
    await _navigateToCheckPrice();
  }

  Future<void> _handleQRScan(String code) async {
    if (_isScanning) return; // Prevent multiple scans
    
    // Prevent duplicate scans
    if (_lastScannedCode == code) return;
    _lastScannedCode = code;
    
    setState(() => _isScanning = true);

    // Haptic feedback
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 100);
    }

    try {
      final product = await ApiService.getProductByBarcode(code.trim());
      if (!mounted) return;
      
      setState(() {
        _isScanning = false;
        _scannedProduct = product;
      });
      
      // Show product details dialog
      _showProductDetails(product);
      
      // Clear lastScannedCode after delay to allow rescanning
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _lastScannedCode = null);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Product not found: $e'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _navigateToCheckPrice() async {
    if (_selectedPriceCategory == null || _selectedPriceCategory!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a price category'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckPriceManualScreen(
          initialPriceCategory: _selectedPriceCategory,
        ),
      ),
    );
  }

  void _showProductDetails(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB8860B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.inventory_2,
                      color: Color(0xFFB8860B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name ?? 'Product',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        if (product.categoryName != null)
                          Text(
                            product.categoryName!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            const Divider(),
            
            // Product Details
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Image (if available)
                    if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                      Container(
                        width: double.infinity,
                        height: 250,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.grey.shade100,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            product.imageUrl!,
                            fit: BoxFit.cover,
                            cacheWidth: 400,
                            cacheHeight: 400,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.image_not_supported,
                                size: 60,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    
                    // QR Code
                    if (product.qrCode != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.qr_code, color: Color(0xFFB8860B)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'QR Code',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    product.qrCode!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Sizes and Prices
                    if (product.sizes != null && product.sizes!.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Available Sizes & Prices',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...product.sizes!.map((size) => _buildSizeCard(size)),
                        ],
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No sizes available for this product',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 20),
                    
                    // Price Range
                    if (product.minPrice != null || product.maxPrice != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFB8860B), Color(0xFFD4AF37)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.currency_rupee, color: Colors.white),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Price Range',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                  Text(
                                    product.priceRange,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
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
            
            // Action Buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _scannedProduct = null);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFB8860B), width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Scan Another',
                        style: TextStyle(
                          color: Color(0xFFB8860B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CheckPriceManualScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB8860B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Check Price',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeCard(ProductSize size) {
    final hasPrices = [
      size.priceA,
      size.priceB,
      size.priceC,
      size.priceD,
      size.priceE,
      size.priceR,
    ].any((price) => price != null);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFB8860B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  size.sizeText ?? 'N/A',
                  style: const TextStyle(
                    color: Color(0xFFB8860B),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              if (hasPrices)
                Text(
                  size.minPrice == size.maxPrice
                      ? '₹${size.minPrice!.toStringAsFixed(2)}'
                      : '₹${size.minPrice!.toStringAsFixed(2)} - ₹${size.maxPrice!.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
            ],
          ),
          if (hasPrices) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (size.priceA != null)
                  _buildPriceChip('A', size.priceA!),
                if (size.priceB != null)
                  _buildPriceChip('B', size.priceB!),
                if (size.priceC != null)
                  _buildPriceChip('C', size.priceC!),
                if (size.priceD != null)
                  _buildPriceChip('D', size.priceD!),
                if (size.priceE != null)
                  _buildPriceChip('E', size.priceE!),
                if (size.priceR != null)
                  _buildPriceChip('R', size.priceR!),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceChip(String category, double price) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        '$category: ₹${price.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade700,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
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
          'Select Price Category',
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
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFB8860B)),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Loading categories...',
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
                  // Select Category Dropdown
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.category_outlined,
                              color: Color(0xFFB8860B),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Select Price Category',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TypeAheadField<String>(
                          controller: _categoryController,
                          builder: (context, controller, focusNode) {
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                hintText: 'Search price category (A, B, C, D, E, R)',
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
                                            _selectedPriceCategory = null;
                                          });
                                        },
                                      )
                                    : null,
                              ),
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFF1A1A1A),
                              ),
                            );
                          },
                          suggestionsCallback: (pattern) async {
                            if (pattern.isEmpty) {
                              return _priceCategories.take(20).toList();
                            }
                            final search = pattern.toLowerCase();
                            return _priceCategories
                                .where((category) =>
                                    category.toLowerCase().contains(search))
                                .take(20)
                                .toList();
                          },
                          itemBuilder: (context, String suggestion) {
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
                                    Icons.category_outlined,
                                    size: 20,
                                    color: Color(0xFFB8860B),
                                  ),
                                ),
                                title: Text(
                                  suggestion,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                tileColor: Colors.white,
                              ),
                            );
                          },
                          onSelected: (String suggestion) {
                            _handlePriceCategorySelected(suggestion);
                          },
                          hideOnEmpty: false,
                          hideOnError: false,
                          hideOnLoading: false,
                          debounceDuration: const Duration(milliseconds: 300),
                        ),
                      ],
                    ),
                  ),

                  // Scan QR Code Section
                  Expanded(
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Scan QR Code',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                children: [
                                  MobileScanner(
                                    controller: _scannerController,
                                    onDetect: (capture) {
                                      final barcode =
                                          capture.barcodes.first.rawValue;
                                      if (barcode == null ||
                                          barcode.isEmpty ||
                                          _isScanning) return;
                                      _handleQRScan(barcode);
                                    },
                                  ),
                                  // QR Code Scanning Frame
                                  CustomPaint(
                                    painter: QRScannerOverlay(),
                                    child: Container(),
                                  ),
                                  // Scanning Indicator
                                  if (_isScanning)
                                    Container(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      child: const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                Color(0xFFB8860B),
                                              ),
                                            ),
                                            SizedBox(height: 16),
                                            Text(
                                              'Processing...',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
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
                        const SizedBox(height: 16),
                        // Manual Check Price Link
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const CheckPriceManualScreen(),
                                ),
                              );
                            },
                            child: Text(
                              'Didn\'t find QR Code ? Click here to Check Price Manual',
                              style: TextStyle(
                                fontSize: 14,
                                color: const Color(0xFFB8860B),
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// Custom painter for QR scanner overlay with blue corner brackets
class QRScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2196F3) // Blue color
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final cornerLength = 30.0;
    final margin = 40.0;

    // Calculate the scanning area (centered)
    final scanAreaSize = size.width - (margin * 2);
    final scanAreaTop = (size.height - scanAreaSize) / 2;
    final scanAreaLeft = margin;

    // Top-left corner
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop),
      Offset(scanAreaLeft + cornerLength, scanAreaTop),
      paint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop),
      Offset(scanAreaLeft, scanAreaTop + cornerLength),
      paint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize - cornerLength, scanAreaTop),
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop),
      paint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop),
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + cornerLength),
      paint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop + scanAreaSize - cornerLength),
      Offset(scanAreaLeft, scanAreaTop + scanAreaSize),
      paint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop + scanAreaSize),
      Offset(scanAreaLeft + cornerLength, scanAreaTop + scanAreaSize),
      paint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + scanAreaSize - cornerLength),
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + scanAreaSize),
      paint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize - cornerLength, scanAreaTop + scanAreaSize),
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + scanAreaSize),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

