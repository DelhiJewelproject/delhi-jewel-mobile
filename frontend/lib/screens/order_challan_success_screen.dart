import 'package:flutter/material.dart';
import '../models/challan.dart';
import '../services/api_service.dart';
import 'main_screen.dart';

class OrderChallanSuccessScreen extends StatelessWidget {
  final Challan? challan; // Make challan optional since orders don't create challans
  final String partyName;
  final String orderNumber;
  final List<ChallanItem> items;
  final double totalAmount;
  final Map<String, Map<String, int>>? designAllocations;

  const OrderChallanSuccessScreen({
    super.key,
    this.challan, // Optional - not required for orders
    required this.partyName,
    required this.orderNumber,
    required this.items,
    required this.totalAmount,
    this.designAllocations,
  });

  void _navigateToMainScreen(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    final isLargeScreen = screenSize.width > 900;

    return WillPopScope(
      onWillPop: () async {
        _navigateToMainScreen(context);
        return false; // Prevent default back behavior
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1A1A1A)),
            onPressed: () => _navigateToMainScreen(context),
        ),
        title: const Text(
          'Order Created',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined, color: Color(0xFF1A1A1A)),
            onPressed: () => _navigateToMainScreen(context),
            tooltip: 'Home',
          ),
        ],
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
          physics: const AlwaysScrollableScrollPhysics(),
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
              // Success Banner
              _buildSuccessBanner(),
              const SizedBox(height: 24),
              // Details Card
              _buildDetailsCard(),
              const SizedBox(height: 24),
              // Items Card
              _buildItemsCard(),
              const SizedBox(height: 24),
              // Design Allocations Card (if any)
              // if (designAllocations != null && designAllocations!.isNotEmpty)
              //   _buildDesignAllocationsCard(),
              // if (designAllocations != null && designAllocations!.isNotEmpty)
              //   const SizedBox(height: 24),
              // Summary Card
              _buildSummaryCard(),
              // QR Code Card hidden
              // const SizedBox(height: 24),
              // if (challan != null) _buildQrCard(),
              // if (challan != null) const SizedBox(height: 24),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB8860B), Color(0xFFC9A227)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Order Created Successfully!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
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
          const Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Color(0xFFB8860B),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Order Information',
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
                _buildDetailRow('Party Name', partyName),
                const SizedBox(height: 16),
                _buildDetailRow('Order Number', orderNumber),
                // if (challan.priceCategory != null) ...[
                //   const SizedBox(height: 16),
                //   _buildDetailRow('Price Category', challan.priceCategory!),
                // ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method for row with heading and data
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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard() {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
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
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'No items in this order',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
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
          ...items.where((item) => item.quantity > 0).toList().asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final filteredItems = items.where((item) => item.quantity > 0).toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < filteredItems.length - 1 ? 10 : 0,
              ),
              child: _buildItemCard(item, index + 1),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildItemCard(ChallanItem item, int index) {
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

  // Helper method to get item key
  String _getItemKey(ChallanItem item) {
    return '${item.productId ?? 'null'}_${item.sizeId ?? 'null'}';
  }

  // Widget _buildDesignAllocationsCard() {
  //   if (designAllocations == null || designAllocations!.isEmpty) {
  //     return const SizedBox.shrink();
  //   }

  //   // Get all allocations with item info
  //   final allocations = <Map<String, dynamic>>[];
    
  //   for (var entry in designAllocations!.entries) {
  //     final sizeKey = entry.key;
  //     final designMap = entry.value;
      
  //     // Find the item for this size key
  //     final item = items.firstWhere(
  //       (item) => _getItemKey(item) == sizeKey,
  //       orElse: () => ChallanItem(productName: 'Unknown', quantity: 0),
  //     );
      
  //     if (item.productName != 'Unknown' && designMap.isNotEmpty) {
  //       allocations.add({
  //         'productName': item.productName,
  //         'sizeText': item.sizeText ?? 'N/A',
  //         'totalQuantity': item.quantity,
  //         'designs': designMap,
  //       });
  //     }
  //   }

  //   if (allocations.isEmpty) {
  //     return const SizedBox.shrink();
  //   }

  //   return Container(
  //     padding: const EdgeInsets.all(24),
  //     decoration: BoxDecoration(
  //       color: Colors.white,
  //       borderRadius: BorderRadius.circular(16),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black.withOpacity(0.05),
  //           blurRadius: 10,
  //           offset: const Offset(0, 4),
  //         ),
  //       ],
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         const Row(
  //           children: [
  //             Icon(
  //               Icons.palette_outlined,
  //               color: Color(0xFFB8860B),
  //               size: 20,
  //             ),
  //             SizedBox(width: 8),
  //             Text(
  //               'Design Allocations',
  //               style: TextStyle(
  //                 fontSize: 16,
  //                 fontWeight: FontWeight.bold,
  //                 color: Color(0xFF1A1A1A),
  //                 letterSpacing: 0.3,
  //               ),
  //             ),
  //           ],
  //         ),
  //         const SizedBox(height: 16),
  //         ...allocations.map((allocation) {
  //           final productName = allocation['productName'] as String;
  //           final sizeText = allocation['sizeText'] as String;
  //           final totalQuantity = allocation['totalQuantity'] as double;
  //           final designs = allocation['designs'] as Map<String, int>;
            
  //           return Container(
  //             margin: const EdgeInsets.only(bottom: 16),
  //             padding: const EdgeInsets.all(16),
  //             decoration: BoxDecoration(
  //               color: Colors.grey.shade50,
  //               borderRadius: BorderRadius.circular(12),
  //               border: Border.all(
  //                 color: Colors.grey.shade200,
  //                 width: 1,
  //               ),
  //             ),
  //             child: Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 // Product and Size info
  //                 Row(
  //                   children: [
  //                     Expanded(
  //                       child: Column(
  //                         crossAxisAlignment: CrossAxisAlignment.start,
  //                         children: [
  //                           Text(
  //                             productName,
  //                             style: const TextStyle(
  //                               fontSize: 14,
  //                               fontWeight: FontWeight.bold,
  //                               color: Color(0xFF1A1A1A),
  //                             ),
  //                             maxLines: 1,
  //                             overflow: TextOverflow.ellipsis,
  //                           ),
  //                           const SizedBox(height: 4),
  //                           Text(
  //                             'Size: $sizeText',
  //                             style: TextStyle(
  //                               fontSize: 12,
  //                               color: Colors.grey.shade700,
  //                             ),
  //                           ),
  //                           const SizedBox(height: 4),
  //                           Text(
  //                             'Total Quantity: ${totalQuantity.toStringAsFixed(0)}',
  //                             style: const TextStyle(
  //                               fontSize: 12,
  //                               fontWeight: FontWeight.w600,
  //                               color: Color(0xFFB8860B),
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //                 const SizedBox(height: 12),
  //                 Divider(color: Colors.grey.shade300),
  //                 const SizedBox(height: 12),
  //                 // Design allocations
  //                 Text(
  //                   'Design Allocations:',
  //                   style: TextStyle(
  //                     fontSize: 12,
  //                     fontWeight: FontWeight.w600,
  //                     color: Colors.grey.shade700,
  //                   ),
  //                 ),
  //                 const SizedBox(height: 8),
  //                 Wrap(
  //                   spacing: 8,
  //                   runSpacing: 8,
  //                   children: designs.entries.map((entry) {
  //                     final design = entry.key;
  //                     final qty = entry.value;
  //                     final isStaticDesign = ['D1', 'D2', 'D3'].contains(design);
                      
  //                     return Container(
  //                       padding: const EdgeInsets.symmetric(
  //                         horizontal: 10,
  //                         vertical: 6,
  //                       ),
  //                       decoration: BoxDecoration(
  //                         color: const Color(0xFFB8860B).withOpacity(0.1),
  //                         border: Border.all(
  //                           color: const Color(0xFFB8860B),
  //                           width: 1,
  //                         ),
  //                         borderRadius: BorderRadius.circular(6),
  //                       ),
  //                       child: Row(
  //                         mainAxisSize: MainAxisSize.min,
  //                         children: [
  //                           if (isStaticDesign) ...[
  //                             Container(
  //                               width: 20,
  //                               height: 16,
  //                               decoration: BoxDecoration(
  //                                 color: Colors.grey.shade100,
  //                                 borderRadius: BorderRadius.circular(3),
  //                                 border: Border.all(
  //                                   color: Colors.grey.shade300,
  //                                 ),
  //                               ),
  //                               child: Icon(
  //                                 Icons.image_outlined,
  //                                 size: 12,
  //                                 color: Colors.grey.shade600,
  //                               ),
  //                             ),
  //                             const SizedBox(width: 4),
  //                           ],
  //                           Text(
  //                             design,
  //                             style: const TextStyle(
  //                               fontSize: 12,
  //                               fontWeight: FontWeight.w600,
  //                               color: Color(0xFF1A1A1A),
  //                             ),
  //                           ),
  //                           const SizedBox(width: 4),
  //                           Text(
  //                             ': $qty',
  //                             style: const TextStyle(
  //                               fontSize: 12,
  //                               fontWeight: FontWeight.bold,
  //                               color: Color(0xFFB8860B),
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                     );
  //                   }).toList(),
  //                 ),
  //               ],
  //             ),
  //           );
  //         }).toList(),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildSummaryCard() {
    final totalQuantity = items.fold(0.0, (sum, item) => sum + item.quantity);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                color: Colors.white.withOpacity(0.9),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Total: ${totalAmount.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                color: Colors.white.withOpacity(0.9),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Quantity: ${totalQuantity.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrCard() {
    if (challan == null) return const SizedBox.shrink();
    
    final qrUrl = challan!.id != null
        ? ApiService.getChallanQrUrl(challan!.id!)
        : ApiService.getChallanQrUrlByNumber(challan!.challanNumber);

    return Container(
      padding: const EdgeInsets.all(24),
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
          const Row(
            children: [
              Icon(
                Icons.qr_code_2_rounded,
                color: Color(0xFFB8860B),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'QR Code',
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.grey.shade300,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
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
                    'Scan this QR code to quickly access order details on the dispatch floor.',
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
}
