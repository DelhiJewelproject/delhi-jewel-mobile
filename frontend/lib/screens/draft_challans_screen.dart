import 'package:flutter/material.dart';
import '../models/challan.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import 'view_challan_screen.dart';
import 'challan_summary_screen.dart';
import 'item_info_challan_screen.dart';

class DraftChallansScreen extends StatefulWidget {
  const DraftChallansScreen({super.key});

  @override
  State<DraftChallansScreen> createState() => _DraftChallansScreenState();
}

class _DraftChallansScreenState extends State<DraftChallansScreen> {
  List<Challan> _draftChallans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDraftChallans();
  }

  static const _finalizedStatuses = {'ready', 'in_transit', 'delivered'};

  /// Syncs with server and removes ended challans. Uses raw storage so challan numbers match exactly.
  Future<int> _syncAndRemoveEnded() async {
    // Read raw list once – use exact challan_number/challanNumber as stored
    final rawList = await LocalStorageService.getRawDraftChallansList();
    final dcToCheck = <String>{};
    for (final item in rawList) {
      final dc = LocalStorageService.getDcFromRawDraft(item);
      if (dc != null && dc.isNotEmpty) dcToCheck.add(dc);
    }
    final finalizedDcNumbers = <String>{};
    for (final dc in dcToCheck) {
      Challan? serverChallan;
      try {
        serverChallan = await ApiService.getChallanByNumber(dc);
      } catch (_) {
        try {
          serverChallan = await ApiService.getChallanByNumber(dc.toUpperCase());
        } catch (_) {}
      }
      if (serverChallan != null) {
        final status = (serverChallan.status).toLowerCase();
        if (_finalizedStatuses.contains(status)) {
          final serverDc = LocalStorageService.extractDcPart(serverChallan.challanNumber) ?? serverChallan.challanNumber;
          if (serverDc.isNotEmpty) finalizedDcNumbers.add(serverDc.toUpperCase());
        }
      }
    }
    // Remove using the same raw list so we persist the filtered list
    if (finalizedDcNumbers.isNotEmpty) {
      await LocalStorageService.removeDraftChallansByDcNumbers(finalizedDcNumbers, rawList);
    }
    return finalizedDcNumbers.length;
  }

  Future<void> _loadDraftChallans() async {
    setState(() => _isLoading = true);
    try {
      // Use raw list so we send exact stored challan numbers to API and remove with same data
      final rawList = await LocalStorageService.getRawDraftChallansList();
      final dcToCheck = <String>{};
      for (final item in rawList) {
        final dc = LocalStorageService.getDcFromRawDraft(item);
        if (dc != null && dc.isNotEmpty) dcToCheck.add(dc);
      }
      final finalizedDcNumbers = <String>{};
      for (final dc in dcToCheck) {
        Challan? serverChallan;
        try {
          serverChallan = await ApiService.getChallanByNumber(dc);
        } catch (_) {
          try {
            serverChallan = await ApiService.getChallanByNumber(dc.toUpperCase());
          } catch (_) {}
        }
        if (serverChallan != null) {
          final status = (serverChallan.status).toLowerCase();
          if (_finalizedStatuses.contains(status)) {
            final serverDc = LocalStorageService.extractDcPart(serverChallan.challanNumber) ?? serverChallan.challanNumber;
            if (serverDc.isNotEmpty) finalizedDcNumbers.add(serverDc.toUpperCase());
          }
        }
      }
      if (finalizedDcNumbers.isNotEmpty) {
        await LocalStorageService.removeDraftChallansByDcNumbers(finalizedDcNumbers, rawList);
      }
      if (!mounted) return;
      List<Challan> updated = await LocalStorageService.getDraftChallans();
      if (finalizedDcNumbers.isNotEmpty) {
        updated = updated.where((c) {
          final dc = LocalStorageService.extractDcPart(c.challanNumber);
          return dc == null || dc.isEmpty || !finalizedDcNumbers.contains(dc.toUpperCase());
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        _draftChallans = updated;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load draft challans: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Future<void> _deleteDraftChallan(Challan challan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Draft Challan'),
        content: Text('Are you sure you want to delete ${challan.challanNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete on server if this draft has a challan id (so it can be reused for another challan)
      if (challan.id != null) {
        try {
          await ApiService.deleteChallan(challan.id!);
        } catch (_) {
          // Still remove from local list if server delete fails (e.g. offline)
        }
      }
      // Remove from local storage (by DC so it disappears from Old Challans and is not re-added)
      final dc = LocalStorageService.extractDcPart(challan.challanNumber) ?? challan.challanNumber;
      if (dc.isNotEmpty) {
        await LocalStorageService.removeDraftChallansByDcNumber(dc);
      } else {
        await LocalStorageService.removeDraftChallan(challan.challanNumber);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting draft: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
    if (mounted) _loadDraftChallans();
  }

  Future<void> _continueDraftChallan(Challan challan) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChallanSummaryScreen(
          partyName: challan.partyName,
          stationName: challan.stationName,
          transportName: challan.transportName ?? '',
          priceCategory: challan.priceCategory,
          items: challan.items,
          challanNumber: challan.challanNumber,
          challanId: challan.id, // So "End Challan" updates existing instead of creating new
        ),
      ),
    );
    _loadDraftChallans();
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
          'Old Challans',
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
            icon: const Icon(Icons.sync, color: Color(0xFF1A1A1A)),
            onPressed: () async {
              if (_isLoading) return;
              setState(() => _isLoading = true);
              try {
                final removed = await _syncAndRemoveEnded();
                if (!mounted) return;
                await _loadDraftChallans();
                if (!mounted) return;
                setState(() => _isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(removed > 0
                        ? 'Removed $removed ended challan(s) from drafts.'
                        : 'Synced. No ended challans in your drafts.'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              } catch (e) {
                if (mounted) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Sync failed: $e'),
                      backgroundColor: Colors.red.shade600,
                    ),
                  );
                }
              }
            },
            tooltip: 'Sync & remove ended challans',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF1A1A1A)),
            onSelected: (value) async {
              if (value == 'clear_all') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear all drafts?'),
                    content: const Text(
                      'This will remove all draft challans from this device. '
                      'Challans already ended on server are not affected. Cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear all'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await LocalStorageService.clearAllDraftChallans();
                  if (mounted) _loadDraftChallans();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All draft challans cleared.'),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_all',
                child: ListTile(
                  leading: Icon(Icons.delete_sweep, color: Colors.red),
                  title: Text('Clear all draft challans'),
                ),
              ),
            ],
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
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB8860B)),
                ),
              )
            : _draftChallans.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No draft challans found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadDraftChallans,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _draftChallans.length,
                      itemBuilder: (context, index) {
                        final challan = _draftChallans[index];
                        return _buildChallanCard(challan);
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _buildChallanCard(Challan challan) {
    final itemsWithQuantity = challan.items.where((item) => item.quantity > 0).length;
    final totalAmount = challan.items.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challan.challanNumber,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Party: ${challan.partyName}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Station: ${challan.stationName}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (challan.transportName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Transport: ${challan.transportName}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deleteDraftChallan(challan),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Items: $itemsWithQuantity',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              Text(
                'Total: ₹${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB8860B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _continueDraftChallan(challan),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB8860B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

