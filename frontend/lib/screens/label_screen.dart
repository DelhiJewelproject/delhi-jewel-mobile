import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../services/api_service.dart';
import '../models/product.dart';
import '../models/product_size.dart';

class LabelItem {
  String? productName;
  String? productSize;
  int numberOfLabels;
  Product? selectedProduct;
  ProductSize? selectedSize;

  LabelItem({
    this.productName,
    this.productSize,
    this.numberOfLabels = 1,
    this.selectedProduct,
    this.selectedSize,
  });
}

class LabelScreen extends StatefulWidget {
  const LabelScreen({super.key});

  @override
  State<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends State<LabelScreen> {
  final _formKey = GlobalKey<FormState>();
  List<LabelItem> _labelItems = [LabelItem()];
  bool _isGenerating = false;
  bool _isLoadingProducts = false;
  List<Product> _allProducts = [];
  final Map<int, TextEditingController> _productControllers = {};
  final Map<int, TextEditingController> _numberOfLabelsControllers = {};

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    for (var controller in _productControllers.values) {
      controller.dispose();
    }
    for (var controller in _numberOfLabelsControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProducts() async {
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
      return _allProducts.take(20).toList();
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
        .take(20)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    final isSmallScreen = screenSize.width < 360;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFFFFF),
              const Color(0xFFF8F8F8),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Professional Header
              _buildHeader(isTablet, isSmallScreen),
              // Form Content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 16 : isTablet ? 32 : 24,
                    vertical: isSmallScreen ? 16 : 24,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSectionHeader(isTablet, isSmallScreen),
                        const SizedBox(height: 16),
                        // Label Items List
                        ...List.generate(_labelItems.length, (index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildLabelItemCard(index, isTablet, isSmallScreen),
                          );
                        }),
                        const SizedBox(height: 24),
                        // Generate Button
                        _buildGenerateButton(isTablet, isSmallScreen),
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

  Widget _buildHeader(bool isTablet, bool isSmallScreen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.label_rounded,
            color: const Color(0xFFB8860B),
            size: 24,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Generate Labels',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Create product labels',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Color(0xFF1A1A1A)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(bool isTablet, bool isSmallScreen) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Icons.inventory_2_rounded,
              color: const Color(0xFFB8860B),
              size: 18,
            ),
            const SizedBox(width: 8),
            const Text(
              'Label Items',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFB8860B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_labelItems.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB8860B),
                ),
              ),
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _addLabelItem,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add Item'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFB8860B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabelItemCard(int index, bool isTablet, bool isSmallScreen) {
    final item = _labelItems[index];
    
    // Ensure controllers exist for this index
    if (!_productControllers.containsKey(index)) {
      _productControllers[index] = TextEditingController(text: item.productName ?? '');
    }
    if (!_numberOfLabelsControllers.containsKey(index)) {
      _numberOfLabelsControllers[index] = TextEditingController(text: item.numberOfLabels.toString());
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
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
          // Card Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB8860B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB8860B),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Item',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              if (_labelItems.length > 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: Colors.red.shade400,
                  onPressed: () => _removeLabelItem(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          // Product Name Field with TypeAhead
          _buildProductNameField(index, item, isSmallScreen),
          const SizedBox(height: 12),
          // Product Size Dropdown (updates based on selected product)
          _buildProductSizeDropdown(index, item, isSmallScreen),
          const SizedBox(height: 12),
          // Number of Labels Field
          _buildTextField(
            controller: _numberOfLabelsControllers[index] ??= TextEditingController(text: item.numberOfLabels.toString()),
            label: 'Number of Labels',
            icon: Icons.numbers_outlined,
            keyboardType: TextInputType.number,
            onChanged: (value) {
              item.numberOfLabels = int.tryParse(value) ?? 1;
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Number of labels is required';
              }
              final num = int.tryParse(value);
              if (num == null || num < 1) {
                return 'Enter a valid number (min: 1)';
              }
              return null;
            },
            isSmallScreen: isSmallScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildProductNameField(int index, LabelItem item, bool isSmallScreen) {
    if (!_productControllers.containsKey(index)) {
      _productControllers[index] = TextEditingController(text: item.productName ?? '');
    }

    return TypeAheadField<Product>(
      controller: _productControllers[index]!,
      builder: (context, controller, focusNode) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 14,
          ),
          decoration: InputDecoration(
            labelText: 'Product Name *',
            labelStyle: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 13,
            ),
            prefixIcon: const Icon(Icons.inventory_2_outlined, color: Color(0xFFB8860B), size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFB8860B), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.red.shade400, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.red.shade400, width: 2),
            ),
            errorStyle: TextStyle(
              color: Colors.red.shade300,
              fontSize: 11,
            ),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                    onPressed: () {
                      controller.clear();
                      setState(() {
                        item.selectedProduct = null;
                        item.selectedSize = null;
                        item.productName = null;
                        item.productSize = null;
                      });
                    },
                  )
                : null,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Product name is required';
            }
            if (item.selectedProduct == null) {
              return 'Please select from the suggestions';
            }
            return null;
          },
        );
      },
      suggestionsCallback: (pattern) async {
        return _getFilteredProducts(pattern);
      },
      itemBuilder: (context, Product suggestion) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              tileColor: Colors.white,
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB8860B), Color(0xFFC9A227)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: Colors.black,
                ),
              ),
              title: Text(
                suggestion.name ?? 'Product',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              subtitle: Text(
                suggestion.categoryName ?? '',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF666666),
                ),
              ),
            ),
          ),
        );
      },
      onSelected: (Product product) {
        setState(() {
          item.selectedProduct = product;
          item.productName = product.name ?? 'Product';
          item.selectedSize = null;
          item.productSize = null;
          _productControllers[index]!.text = item.productName!;
        });
      },
      hideOnEmpty: false,
      hideOnError: false,
      hideOnLoading: false,
      debounceDuration: const Duration(milliseconds: 300),
      emptyBuilder: (context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Text(
          _isLoadingProducts
              ? 'Loading products...'
              : 'Type to search or select a product',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildProductSizeDropdown(int index, LabelItem item, bool isSmallScreen) {
    final product = item.selectedProduct;
    final sizes = product?.sizes ?? [];

    return DropdownButtonFormField<ProductSize>(
      value: item.selectedSize,
      style: const TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: 'Product Size (Optional)',
        labelStyle: const TextStyle(
          color: Color(0xFF666666),
          fontSize: 13,
        ),
        prefixIcon: const Icon(Icons.straighten_outlined, color: Color(0xFFB8860B), size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFB8860B), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade400, width: 2),
        ),
      ),
      dropdownColor: Colors.white,
      iconEnabledColor: const Color(0xFFB8860B),
      items: sizes
          .where((size) => size.isActive != false)
          .map((size) => DropdownMenuItem(
                value: size,
                child: Text(
                  size.sizeText ?? 'Size',
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                  ),
                ),
              ))
          .toList(),
      onChanged: product == null
          ? null
          : (ProductSize? size) {
              setState(() {
                item.selectedSize = size;
                item.productSize = size?.sizeText;
              });
            },
      hint: Text(
        product == null
            ? 'Select product first'
            : sizes.isEmpty
                ? 'No sizes available'
                : 'Select size',
        style: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    required bool isSmallScreen,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF666666),
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFFB8860B), size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFB8860B), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade400, width: 2),
        ),
        errorStyle: TextStyle(
          color: Colors.red.shade300,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildGenerateButton(bool isTablet, bool isSmallScreen) {
    return ElevatedButton.icon(
      onPressed: _isGenerating ? null : _generateLabels,
      icon: Icon(
        Icons.print_rounded,
        size: 20,
        color: _isGenerating ? Colors.grey : Colors.white,
      ),
      label: Text(
        'Generate Labels',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _isGenerating ? Colors.grey : Colors.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _isGenerating ? Colors.grey.shade400 : const Color(0xFFB8860B),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
      ),
    );
  }

  void _addLabelItem() {
    setState(() {
      final newIndex = _labelItems.length;
      _labelItems.add(LabelItem());
      _productControllers[newIndex] = TextEditingController();
      _numberOfLabelsControllers[newIndex] = TextEditingController(text: '1');
    });
  }

  void _removeLabelItem(int index) {
    if (_productControllers.containsKey(index)) {
      _productControllers[index]!.dispose();
      _productControllers.remove(index);
    }
    if (_numberOfLabelsControllers.containsKey(index)) {
      _numberOfLabelsControllers[index]!.dispose();
      _numberOfLabelsControllers.remove(index);
    }
    setState(() {
      _labelItems.removeAt(index);
      // Reindex controllers
      final newProductControllers = <int, TextEditingController>{};
      final newNumberOfLabelsControllers = <int, TextEditingController>{};
      for (int i = 0; i < _labelItems.length; i++) {
        if (i < index) {
          if (_productControllers.containsKey(i)) {
            newProductControllers[i] = _productControllers[i]!;
          }
          if (_numberOfLabelsControllers.containsKey(i)) {
            newNumberOfLabelsControllers[i] = _numberOfLabelsControllers[i]!;
          }
        } else if (i >= index) {
          if (_productControllers.containsKey(i + 1)) {
            newProductControllers[i] = _productControllers[i + 1]!;
          }
          if (_numberOfLabelsControllers.containsKey(i + 1)) {
            newNumberOfLabelsControllers[i] = _numberOfLabelsControllers[i + 1]!;
          }
        }
      }
      _productControllers.clear();
      _numberOfLabelsControllers.clear();
      _productControllers.addAll(newProductControllers);
      _numberOfLabelsControllers.addAll(newNumberOfLabelsControllers);
    });
  }

  Future<void> _generateLabels() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text('Please fix the errors in the form'),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // Validate all items
    bool hasErrors = false;
    for (var item in _labelItems) {
      if (item.productName == null || item.productName!.trim().isEmpty) {
        hasErrors = true;
        break;
      }
      if (item.numberOfLabels < 1) {
        hasErrors = true;
        break;
      }
    }

    if (hasErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text('Please fill all required fields correctly'),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      // Prepare label data for API
      final items = _labelItems.map((item) => <String, dynamic>{
        'product_name': item.productName ?? (item.selectedProduct?.name ?? ''),
        'product_size': item.productSize ?? (item.selectedSize?.sizeText ?? ''),
        'number_of_labels': item.numberOfLabels,
      }).toList();

      final labelData = <String, dynamic>{
        'items': items,
        'created_by': 'system',
      };

      print('Prepared label data: $labelData');

      // Call API to generate labels
      final result = await ApiService.generateLabels(labelData);

      if (mounted) {
        final totalLabels = result['total_labels'] ?? 0;
        final itemsCreated = result['items_created'] ?? 0;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Successfully generated $totalLabels labels from $itemsCreated item(s)!',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );

        // Show success dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: const Color(0xFFB8860B).withOpacity(0.3),
                width: 1,
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Color(0xFF10B981),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Labels Generated',
                  style: TextStyle(
                    color: Color(0xFFB8860B),
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            content: Text(
              'Successfully created $itemsCreated label item(s) with $totalLabels total labels.\n\nLabels have been saved to the database and are ready for printing.',
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context); // Close label screen
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB8860B), Color(0xFFC9A227)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
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
                  child: Text(
                    'Error: ${e.toString().replaceAll('Exception: ', '')}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }
}
