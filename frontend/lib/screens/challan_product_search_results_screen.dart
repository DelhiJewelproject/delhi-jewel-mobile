import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/challan.dart';
import '../models/product_size.dart';
import '../services/local_storage_service.dart';
import 'item_info_challan_screen.dart';

class ChallanProductSearchResultsScreen extends StatefulWidget {
  final List<Product> products;
  final String searchQuery;
  final Challan challan;

  const ChallanProductSearchResultsScreen({
    super.key,
    required this.products,
    required this.searchQuery,
    required this.challan,
  });

  @override
  State<ChallanProductSearchResultsScreen> createState() =>
      _ChallanProductSearchResultsScreenState();
}

class _ChallanProductSearchResultsScreenState
    extends State<ChallanProductSearchResultsScreen> {
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
        title: Text(
          'Search Results: "${widget.searchQuery}"',
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.bold,
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
        child: widget.products.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No products found',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try a different search term',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // Results count
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    color: Colors.white,
                    child: Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: const Color(0xFFB8860B),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${widget.products.length} product${widget.products.length != 1 ? 's' : ''} found',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Products list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: widget.products.length,
                      itemBuilder: (context, index) {
                        return _buildProductItem(widget.products[index]);
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildProductItem(Product product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectProduct(product),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Product icon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB8860B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xFFB8860B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Product details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name ?? 'Unnamed Product',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (product.categoryName != null ||
                          product.externalId != null)
                        Text(
                          [
                            if (product.categoryName != null)
                              product.categoryName,
                            if (product.externalId != null)
                              'ID: ${product.externalId}',
                          ].join(' • '),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Arrow icon
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper function to get price based on price category
  double? _getPriceByCategory(ProductSize? size) {
    if (size == null || widget.challan.priceCategory == null) {
      return size?.minPrice;
    }
    
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

  void _selectProduct(Product product) async {
    // Create ChallanItems for ALL sizes of the product
    final List<ChallanItem> challanItems = [];
    
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

    // Navigate to item info challan screen with selected product
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemInfoChallanScreen(
          partyName: widget.challan.partyName,
          stationName: widget.challan.stationName,
          transportName: widget.challan.transportName ?? '',
          priceCategory: widget.challan.priceCategory,
          initialItems: challanItems,
          challanId: widget.challan.id,
          challanNumber: widget.challan.challanNumber,
          draftChallanNumber: existingDraftNumber, // Fallback for backward compatibility
        ),
      ),
    );
  }
}

