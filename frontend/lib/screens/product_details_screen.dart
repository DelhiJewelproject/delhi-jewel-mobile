import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/product_size.dart';
import '../services/api_service.dart';

class ProductDetailsScreen extends StatelessWidget {
  final Product product;
  final String? partyName;
  final String? stationName;
  final String? transportName;
  final String? priceCategory;

  const ProductDetailsScreen({
    super.key,
    required this.product,
    this.partyName,
    this.stationName,
    this.transportName,
    this.priceCategory,
  });

  @override
  Widget build(BuildContext context) {
    final sizes = product.sizes ?? [];
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
          'Product Details',
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
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isLargeScreen
                ? (screenSize.width - 700) / 2
                : isTablet
                    ? 48
                    : 20,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroCard(isTablet),
              const SizedBox(height: 24),
              if (sizes.isNotEmpty) _buildSizeSection(sizes),
              if (sizes.isEmpty) _buildEmptySizesCard(),
              const SizedBox(height: 24),
              _buildMetaSection(),
              const SizedBox(height: 24),
              if (product.id != null) _buildQrSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(bool isTablet) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFB8860B),
            Color(0xFFD4AF37),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8860B).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (product.categoryName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                product.categoryName!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            product.name ?? 'Product Name',
            style: TextStyle(
              fontSize: isTablet ? 32 : 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              product.priceRange,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          if (partyName != null ||
              stationName != null ||
              transportName != null ||
              priceCategory != null ||
              product.externalId != null) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (partyName != null)
                  _buildChip(Icons.business_center, partyName!),
                if (stationName != null)
                  _buildChip(Icons.location_on_outlined, stationName!),
                if (transportName != null)
                  _buildChip(Icons.local_shipping_outlined, transportName!),
                if (priceCategory != null)
                  _buildChip(Icons.sell_outlined, 'Price: $priceCategory'),
                if (product.externalId != null)
                  _buildChip(Icons.confirmation_number_outlined,
                      'ID: ${product.externalId}'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildSizeSection(List<ProductSize> sizes) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFB8860B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.straighten_rounded,
                  color: Color(0xFFB8860B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Available Sizes & Prices',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...sizes.asMap().entries.map((entry) {
            final index = entry.key;
            final size = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < sizes.length - 1 ? 16 : 0,
              ),
              child: _buildSizeCard(size),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSizeCard(ProductSize size) {
    // If price category is selected, show only that price
    Map<String, double?> priceMap;
    if (priceCategory != null && priceCategory!.isNotEmpty) {
      final selectedPrice = _getPriceForCategory(size, priceCategory!);
      if (selectedPrice != null) {
        priceMap = {priceCategory!: selectedPrice};
      } else {
        priceMap = {};
      }
    } else {
      // Show all prices if no category selected
      priceMap = {
        'A': size.priceA,
        'B': size.priceB,
        'C': size.priceC,
        'D': size.priceD,
        'E': size.priceE,
        'R': size.priceR,
      }..removeWhere((key, value) => value == null);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
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
                  Icons.square_foot_rounded,
                  color: Color(0xFFB8860B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      size.sizeText ?? 'Size Variant',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    if (size.sizeId != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Size ID: ${size.sizeId}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Builder(
                builder: (context) {
                  // Show selected price category price, or minPrice if no category selected
                  double? displayPrice;
                  if (priceCategory != null && priceCategory!.isNotEmpty) {
                    displayPrice = _getPriceForCategory(size, priceCategory!);
                  } else {
                    displayPrice = size.minPrice;
                  }
                  
                  if (displayPrice != null) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB8860B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFB8860B).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '₹${displayPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB8860B),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
          if (priceMap.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Text(
              priceCategory != null && priceCategory!.isNotEmpty
                  ? 'Price Category: $priceCategory'
                  : 'Price Categories',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: priceMap.entries
                  .map(
                    (entry) => _buildPriceChip(entry.key, entry.value!),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceChip(String tier, double price) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFB8860B).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8860B).withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFB8860B),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tier,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${price.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySizesCard() {
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
          Icon(
            Icons.straighten_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No sizes configured',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pricing for this product will appear here once sizes are configured.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaSection() {
    final metaItems = <Map<String, dynamic>>[];
    if (product.externalId != null) {
      metaItems.add({
        'label': 'External ID',
        'value': '${product.externalId}',
        'icon': Icons.confirmation_number_outlined  // Store IconData directly instead of codePoint
      });
    }
    if (product.categoryName != null) {
      metaItems.add({
        'label': 'Category',
        'value': product.categoryName!,
        'icon': Icons.category_outlined  // Store IconData directly instead of codePoint
      });
    }
    if (product.qrCode != null) {
      metaItems.add({
        'label': 'QR Code Reference',
        'value': product.qrCode!,
        'icon': Icons.qr_code_2_outlined  // Store IconData directly instead of codePoint
      });
    }

    if (metaItems.isEmpty) {
      return const SizedBox.shrink();
    }

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
              const Icon(
                Icons.info_outline,
                color: Color(0xFFB8860B),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Product Information',
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
          ...metaItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            // Use IconData directly from the map (already stored as IconData, not codePoint)
            final iconData = item['icon'] as IconData;
            return Column(
              children: [
                _buildMetaRow(
                  iconData,
                  item['label']!,
                  item['value']!,
                ),
                if (index < metaItems.length - 1) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMetaRow(IconData icon, String label, String value) {
    return Row(
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
    );
  }

  Widget _buildQrSection() {
    final qrUrl = ApiService.getProductQrCodeUrl(product.id!);
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
          const Row(
            children: [
              Icon(
                Icons.qr_code_2_rounded,
                color: Color(0xFFB8860B),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Product QR Code',
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
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.grey.shade300,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Image.network(
                qrUrl,
                width: 200,
                height: 200,
                fit: BoxFit.contain,
                cacheWidth: 400,
                cacheHeight: 400,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFB8860B),
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'QR Code unavailable',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFDF4E3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Color(0xFFB8860B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Scan this QR code to quickly access product details.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.4,
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

  double? _getPriceForCategory(ProductSize size, String category) {
    switch (category.toUpperCase()) {
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
        return null;
    }
  }
}
