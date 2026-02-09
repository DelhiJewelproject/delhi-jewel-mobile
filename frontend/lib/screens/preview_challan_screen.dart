import 'package:flutter/material.dart';

import '../models/challan.dart';
import '../services/api_service.dart';
import 'challan_summary_screen.dart';

class PreviewChallanScreen extends StatefulWidget {
  final Challan? challan;
  final int? challanId;
  final String? challanNumber;
  // Parameters needed to navigate back to ChallanSummaryScreen
  final String partyName;
  final String stationName;
  final String transportName;
  final String? priceCategory;
  final List<ChallanItem> items;

  const PreviewChallanScreen({
    super.key,
    this.challan,
    this.challanId,
    this.challanNumber,
    required this.partyName,
    required this.stationName,
    required this.transportName,
    this.priceCategory,
    required this.items,
  });

  @override
  State<PreviewChallanScreen> createState() => _PreviewChallanScreenState();
}

class _PreviewChallanScreenState extends State<PreviewChallanScreen> {
  Challan? _challan;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.challan != null) {
      _challan = widget.challan;
      // If challan has an ID but no items, reload from server to get items
      if (widget.challan!.id != null && 
          (widget.challan!.items.isEmpty || widget.challan!.items.length == 0)) {
        _loadChallan();
      }
    } else {
      _loadChallan();
    }
  }

  Future<void> _loadChallan() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      Challan challan;
      if (widget.challanId != null) {
        challan = await ApiService.getChallanById(widget.challanId!);
      } else if (widget.challanNumber != null) {
        challan = await ApiService.getChallanByNumber(widget.challanNumber!);
      } else if (widget.challan != null && widget.challan!.id != null) {
        // If challan object is provided with an ID, reload it from server
        challan = await ApiService.getChallanById(widget.challan!.id!);
      } else if (widget.challan != null && widget.challan!.challanNumber.isNotEmpty) {
        // If challan object is provided with a challan number, reload it from server
        challan = await ApiService.getChallanByNumber(widget.challan!.challanNumber);
      } else {
        throw Exception('No challan reference provided');
      }
      if (!mounted) return;
      setState(() => _challan = challan);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToSummaryScreen(BuildContext context) {
    // Simply pop to go back to the summary screen
    Navigator.pop(context);
  }


  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    final isLargeScreen = screenSize.width > 900;

    return WillPopScope(
      onWillPop: () async {
        _navigateToSummaryScreen(context);
        return false; // Prevent default back behavior
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1A1A1A)),
            onPressed: () => _navigateToSummaryScreen(context),
          ),
        title: const Text(
          'Challan Details',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: false,
        actions: [
          if (_challan != null) ...[
            IconButton(
              icon: const Icon(Icons.print_outlined, color: Color(0xFF1A1A1A)),
              onPressed: () => _showComingSoon('Print'),
              tooltip: 'Print',
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined, color: Color(0xFF1A1A1A)),
              onPressed: () => _showComingSoon('Share'),
              tooltip: 'Share',
            ),
          ],
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
        child: RefreshIndicator(
          onRefresh: _loadChallan,
          color: const Color(0xFFB8860B),
          child: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB8860B)),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Loading challan details...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : _error != null
                  ? _buildErrorState()
                  : _challan == null
                      ? _buildEmptyState()
                      : SingleChildScrollView(
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
                              _buildDetailsCard(),
                              const SizedBox(height: 24),
                              _buildItemsCard(),
                              const SizedBox(height: 24),
                              // Design Allocations Card (if any)
                              if (_hasDesignAllocations())
                                _buildDesignAllocationsCard(),
                              if (_hasDesignAllocations())
                                const SizedBox(height: 24),
                              _buildSummaryCard(),
                              // QR Code Card hidden
                              // const SizedBox(height: 24),
                              // _buildQrCard(),
                              // const SizedBox(height: 24),
                            ],
                          ),
                        ),
        ),
      ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 20),
            Text(
              'Unable to load challan',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadChallan,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 20),
            Text(
              'Challan not found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The requested challan could not be found',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final challan = _challan!;
    // Calculate totals from items if challan totals are 0 or not set
    final totalQuantity = challan.totalQuantity > 0 
        ? challan.totalQuantity 
        : challan.items.fold(0.0, (sum, item) => sum + item.quantity);
    final totalAmount = challan.totalAmount > 0 
        ? challan.totalAmount 
        : challan.items.fold(0.0, (sum, item) => sum + (item.quantity * item.unitPrice));
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
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


  Widget _buildDetailsCard() {
    final challan = _challan!;
    
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
            _buildDetailRow('Challan Number', challan.challanNumber),
            const SizedBox(height: 16),
            _buildDetailRow('Party Name', challan.partyName),
            const SizedBox(height: 16),
            _buildDetailRow('Station Name', challan.stationName),
            const SizedBox(height: 16),
            _buildDetailRow('Transport Name', challan.transportName ?? 'Not specified'),
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

  Widget _buildSimpleDetail(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label - ',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildItemsCard() {
    final challan = _challan!;
    if (challan.items.isEmpty) {
      return Container(
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
              Icons.inventory_2_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'No items in this challan',
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
                Icons.list_alt_rounded,
                color: Color(0xFFB8860B),
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
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
          ...challan.items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < challan.items.length - 1 ? 10 : 0,
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

  // Check if challan has design allocations
  bool _hasDesignAllocations() {
    if (_challan == null) return false;
    final designAllocations = _getDesignAllocations();
    return designAllocations != null && designAllocations.isNotEmpty;
  }

  // Helper method to get design allocations from challan
  Map<String, Map<String, int>>? _getDesignAllocations() {
    if (_challan == null || _challan!.metadata == null) return null;
    
    try {
      final metadata = _challan!.metadata!;
      final designAllocationsJson = metadata['design_allocations'];
      
      if (designAllocationsJson == null) return null;
      
      // Parse design allocations from metadata
      if (designAllocationsJson is Map) {
        final result = <String, Map<String, int>>{};
        for (var entry in designAllocationsJson.entries) {
          final sizeKey = entry.key.toString();
          final designMap = entry.value;
          
          if (designMap is Map) {
            final designs = <String, int>{};
            for (var designEntry in designMap.entries) {
              final design = designEntry.key.toString();
              final qty = designEntry.value;
              if (qty is int) {
                designs[design] = qty;
              } else if (qty is num) {
                designs[design] = qty.toInt();
              }
            }
            if (designs.isNotEmpty) {
              result[sizeKey] = designs;
            }
          }
        }
        return result.isNotEmpty ? result : null;
      }
    } catch (e) {
      print('Error parsing design allocations: $e');
    }
    
    return null;
  }

  // Helper method to get item key
  String _getItemKey(ChallanItem item) {
    return '${item.productId ?? 'null'}_${item.sizeId ?? 'null'}';
  }

  Widget _buildDesignAllocationsCard() {
    final designAllocations = _getDesignAllocations();
    if (designAllocations == null || designAllocations.isEmpty) {
      return const SizedBox.shrink();
    }

    // Get all allocations with item info
    final allocations = <Map<String, dynamic>>[];
    
    for (var entry in designAllocations.entries) {
      final sizeKey = entry.key;
      final designMap = entry.value;
      
      // Find the item for this size key
      final item = _challan!.items.firstWhere(
        (item) => _getItemKey(item) == sizeKey,
        orElse: () => ChallanItem(productName: 'Unknown', quantity: 0),
      );
      
      if (item.productName != 'Unknown' && designMap.isNotEmpty) {
        allocations.add({
          'productName': item.productName,
          'sizeText': item.sizeText ?? 'N/A',
          'totalQuantity': item.quantity,
          'designs': designMap,
        });
      }
    }

    if (allocations.isEmpty) {
      return const SizedBox.shrink();
    }

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
          const Row(
            children: [
              Icon(
                Icons.palette_outlined,
                color: Color(0xFFB8860B),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Design Allocations',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...allocations.map((allocation) {
            final productName = allocation['productName'] as String;
            final sizeText = allocation['sizeText'] as String;
            final totalQuantity = allocation['totalQuantity'] as double;
            final designs = allocation['designs'] as Map<String, int>;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey.shade200,
                  width: 1,
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
                              productName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Size: $sizeText',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total Quantity: ${totalQuantity.toStringAsFixed(0)}',
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
                  Divider(color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  // Design allocations
                  Text(
                    'Design Allocations:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: designs.entries.map((entry) {
                      final design = entry.key;
                      final qty = entry.value;
                      final isStaticDesign = ['D1', 'D2', 'D3'].contains(design);
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB8860B).withOpacity(0.1),
                          border: Border.all(
                            color: const Color(0xFFB8860B),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isStaticDesign) ...[
                              Container(
                                width: 20,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              design,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ': $qty',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB8860B),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildQrCard() {
    final challan = _challan!;
    final qrUrl = challan.id != null
        ? ApiService.getChallanQrUrl(challan.id!)
        : ApiService.getChallanQrUrlByNumber(challan.challanNumber);

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
              const Icon(
                Icons.qr_code_2_rounded,
                color: Color(0xFFB8860B),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
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
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: const Color(0xFFB8860B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Scan this QR code to quickly access challan details on the dispatch floor.',
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

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature feature is coming soon'),
        backgroundColor: const Color(0xFFB8860B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return 'Not available';
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year at $hour:$minute';
  }
}

