import 'package:flutter/material.dart';
import '../models/challan.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import 'view_challan_screen.dart';
import 'preview_challan_screen.dart';
import 'challan_product_selection_screen.dart';
import 'item_info_challan_screen.dart';
import 'main_screen.dart';

class ChallanSummaryScreen extends StatefulWidget {
  final String partyName;
  final String stationName;
  final String transportName;
  final String? priceCategory;
  final List<ChallanItem> items;
  final String? challanNumber;
  final int? challanId; // Real challan ID from database

  const ChallanSummaryScreen({
    super.key,
    required this.partyName,
    required this.stationName,
    required this.transportName,
    this.priceCategory,
    required this.items,
    this.challanNumber,
    this.challanId,
  });

  @override
  State<ChallanSummaryScreen> createState() => _ChallanSummaryScreenState();
}

class _ChallanSummaryScreenState extends State<ChallanSummaryScreen> {
  bool _isSubmitting = false;
  String? _generatedChallanNumber;
  List<ChallanItem> _currentItems = [];

  @override
  void initState() {
    super.initState();
    // Challan number should always be provided now (created after party details)
    // If not provided, this is an error state
    if (widget.challanNumber == null || widget.challanNumber!.isEmpty) {
      print('Warning: Challan number not provided to ChallanSummaryScreen');
    }
    _generatedChallanNumber = widget.challanNumber ?? 'ERROR-NO-NUMBER';
    _currentItems = List.from(widget.items);
    _saveDraftChallan();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload items from local storage when screen becomes visible
    if (ModalRoute.of(context)?.isCurrent == true) {
      _reloadItems();
    }
  }

  Future<void> _reloadItems() async {
    try {
      final updatedDrafts = await LocalStorageService.getDraftChallans();
      final updatedDraft = updatedDrafts.firstWhere(
        (c) => c.challanNumber == _generatedChallanNumber,
        orElse: () => Challan(
          id: null,
          challanNumber: _generatedChallanNumber!,
          partyName: widget.partyName,
          stationName: widget.stationName,
          transportName: widget.transportName,
          priceCategory: widget.priceCategory,
          status: 'draft',
          items: _currentItems,
        ),
      );
      
      if (mounted) {
        setState(() {
          _currentItems = List.from(updatedDraft.items);
        });
      }
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _saveDraftChallan() async {
    // Only save to local storage if we have a real challan ID (for backup)
    // Otherwise, the challan should already be in the database
    final draftChallan = Challan(
      id: widget.challanId, // Use real challan ID if available
      challanNumber: _generatedChallanNumber!,
      partyName: widget.partyName,
      stationName: widget.stationName,
      transportName: widget.transportName,
      priceCategory: widget.priceCategory,
      status: 'draft',
      items: _currentItems,
    );
    await LocalStorageService.saveDraftChallan(draftChallan);
  }

  Future<void> _handleAddMore() async {
    // Save current items to local storage (backup)
    final draftChallan = Challan(
      id: widget.challanId, // Use real challan ID if available
      challanNumber: _generatedChallanNumber!,
      partyName: widget.partyName,
      stationName: widget.stationName,
      transportName: widget.transportName,
      priceCategory: widget.priceCategory,
      status: 'draft',
      items: _currentItems,
    );

    // Save to local storage before navigating (backup only)
    await LocalStorageService.saveDraftChallan(draftChallan);

    if (!mounted) return;
    // Navigate to product selection screen with stored items
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChallanProductSelectionScreen(
          challan: draftChallan,
          initialStoredItems: _currentItems,
        ),
      ),
    );
    
    // When returning, reload draft challan to get updated items
    if (mounted) {
      final updatedDrafts = await LocalStorageService.getDraftChallans();
      final updatedDraft = updatedDrafts.firstWhere(
        (c) => c.challanNumber == _generatedChallanNumber,
        orElse: () => draftChallan,
      );
      
      if (mounted) {
        setState(() {
          _currentItems = List.from(updatedDraft.items);
        });
        await _saveDraftChallan();
      }
    }
  }

  Future<void> _handleViewChallan() async {
    // Reload items from local storage before viewing
    final updatedDrafts = await LocalStorageService.getDraftChallans();
    final updatedDraft = updatedDrafts.firstWhere(
      (c) => c.challanNumber == _generatedChallanNumber,
      orElse: () => Challan(
        id: null,
        challanNumber: _generatedChallanNumber!,
        partyName: widget.partyName,
        stationName: widget.stationName,
        transportName: widget.transportName,
        priceCategory: widget.priceCategory,
        status: 'draft',
        items: _currentItems,
      ),
    );

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreviewChallanScreen(
          challan: updatedDraft,
          challanId: widget.challanId,
          challanNumber: widget.challanNumber ?? _generatedChallanNumber,
          partyName: widget.partyName,
          stationName: widget.stationName,
          transportName: widget.transportName,
          priceCategory: widget.priceCategory,
          items: _currentItems,
        ),
      ),
    );
    
    // Update items after viewing
    if (mounted) {
      setState(() {
        _currentItems = List.from(updatedDraft.items);
      });
    }
  }

  Future<void> _handleEndChallan() async {
    // Reload items from local storage before submitting
    final updatedDrafts = await LocalStorageService.getDraftChallans();
    final updatedDraft = updatedDrafts.firstWhere(
      (c) => c.challanNumber == _generatedChallanNumber,
      orElse: () => Challan(
        id: null,
        challanNumber: _generatedChallanNumber!,
        partyName: widget.partyName,
        stationName: widget.stationName,
        transportName: widget.transportName,
        priceCategory: widget.priceCategory,
        status: 'draft',
        items: _currentItems,
      ),
    );
    
    final itemsWithQuantity = updatedDraft.items.where((item) => item.quantity > 0).toList();
    
    if (itemsWithQuantity.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one product with quantity greater than 0'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final payload = {
        'items': itemsWithQuantity.map((item) => item.toPayload()).toList(),
        'status': 'ready', // Finalize the challan - ready for dispatch
      };

      Challan challan;
      // If challan ID exists, update the existing challan; otherwise create new one
      if (widget.challanId != null) {
        challan = await ApiService.updateChallan(widget.challanId!, payload);
      } else {
        // Fallback: create new challan if ID is not available
        final createPayload = {
          'party_name': widget.partyName,
          'station_name': widget.stationName,
          'transport_name': widget.transportName,
          'price_category': widget.priceCategory,
          'items': itemsWithQuantity.map((item) => item.toPayload()).toList(),
          'status': 'ready',
        };
        challan = await ApiService.createChallan(createPayload);
      }
      if (!mounted) return;

      // Reload challan from server to ensure items are included
      Challan? fullChallan;
      if (challan.id != null) {
        try {
          fullChallan = await ApiService.getChallanById(challan.id!);
        } catch (e) {
          fullChallan = challan;
        }
      } else {
        fullChallan = challan;
      }

      // Remove from local storage since it's now submitted
      if (_generatedChallanNumber != null) {
        await LocalStorageService.removeDraftChallan(_generatedChallanNumber!);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Challan created successfully'),
          backgroundColor: Color(0xFF10B981),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ViewChallanScreen(challan: fullChallan),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create challan: $e'),
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
          'Challan Summary',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined, color: Color(0xFF1A1A1A)),
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const MainScreen()),
                (route) => false,
              );
            },
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
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Challan Info Card
                    Container(
                      padding: const EdgeInsets.all(20),
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
                          const Text(
                            'Challan Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildInfoRow('Challan Number:', _generatedChallanNumber ?? 'DRAFT'),
                          const SizedBox(height: 16),
                          _buildInfoRow('Party Name:', widget.partyName),
                          const SizedBox(height: 16),
                          _buildInfoRow('Station:', widget.stationName),
                          const SizedBox(height: 16),
                          _buildInfoRow('Transport Name:', widget.transportName ?? 'Not specified'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Items Summary
                    Container(
                      padding: const EdgeInsets.all(20),
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
                          const Text(
                            'Items Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildSummaryRow(
                            'Total Items:',
                            _currentItems.where((item) => item.quantity > 0).length.toString(),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow(
                            'Total Quantity:',
                            _getTotalQuantity().toStringAsFixed(2),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow(
                            'Total Amount:',
                            '₹${_getTotalAmount().toStringAsFixed(2)}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Add More Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleAddMore,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Add More',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // View Challan Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleViewChallan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.visibility, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'View Challan',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // End Challan Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleEndChallan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB8860B),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'End Challan',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
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

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  double _getTotalQuantity() {
    // Only count items with quantity > 0
    return _currentItems
        .where((item) => item.quantity > 0)
        .fold(0.0, (sum, item) => sum + item.quantity);
  }

  double _getTotalAmount() {
    // Calculate total amount from items with quantity > 0
    // Use quantity * unitPrice to ensure accurate calculation
    return _currentItems
        .where((item) => item.quantity > 0)
        .fold(0.0, (sum, item) => sum + (item.quantity * item.unitPrice));
  }
}

