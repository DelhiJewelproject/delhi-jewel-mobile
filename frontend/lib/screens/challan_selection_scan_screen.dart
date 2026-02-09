import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:vibration/vibration.dart';

import '../models/challan.dart';
import '../models/product.dart';
import '../models/product_size.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import 'check_price_manual_screen.dart';
import 'challan_product_selection_screen.dart';
import 'item_info_challan_screen.dart';
import 'main_screen.dart';

class ChallanSelectionScanScreen extends StatefulWidget {
  final String? partyName;
  final String? stationName;
  final String? transportName;
  final String? priceCategory;
  final int? challanId;
  final String? challanNumber;

  const ChallanSelectionScanScreen({
    super.key,
    this.partyName,
    this.stationName,
    this.transportName,
    this.priceCategory,
    this.challanId,
    this.challanNumber,
  });

  @override
  State<ChallanSelectionScanScreen> createState() =>
      _ChallanSelectionScanScreenState();
}

class _ChallanSelectionScanScreenState
    extends State<ChallanSelectionScanScreen> {
  final TextEditingController _challanController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  List<Challan> _draftChallans = [];
  Challan? _selectedChallan;
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isNavigating = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    // If challan is already created, use it directly
    if (widget.challanId != null && widget.challanNumber != null) {
      _selectedChallan = Challan(
        id: widget.challanId,
        challanNumber: widget.challanNumber!,
        partyName: widget.partyName ?? '',
        stationName: widget.stationName ?? '',
        transportName: widget.transportName,
        priceCategory: widget.priceCategory,
        status: 'draft',
        items: [],
      );
      _challanController.text = widget.challanNumber!;
    } else {
    _loadDraftChallans();
    }
  }

  @override
  void dispose() {
    _challanController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset navigation flag when screen becomes visible again
    if (_isNavigating && ModalRoute.of(context)?.isCurrent == true) {
      setState(() {
        _isNavigating = false;
      });
      // Reload draft challans in case new ones were created
      _loadDraftChallans();
      // Restart scanner if it was stopped
      try {
        _scannerController.start();
      } catch (e) {
        // Scanner might already be running, ignore error
      }
    }
  }

  Future<void> _loadDraftChallans() async {
    setState(() => _isLoading = true);
    try {
      final draftChallans = await LocalStorageService.getDraftChallans();
      if (!mounted) return;
      setState(() {
        _draftChallans = draftChallans;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      // Silently fail - draft challans might not exist yet
    }
  }

  /// True if current screen has a new challan from form (so we may show cancel dialog).
  bool get _isNewChallanFromForm {
    if (widget.challanId == null || widget.challanNumber == null) return false;
    final c = _selectedChallan;
    return c != null && c.id == widget.challanId;
  }

  /// Returns true only when challan has no stored items (in memory, local draft, or server).
  Future<bool> _hasChallanNoStoredItems() async {
    if (!_isNewChallanFromForm) return false;
    final c = _selectedChallan!;
    if (c.items.isNotEmpty) return false;
    // Check local draft – items are often saved here first (e.g. after ItemInfoChallanScreen OK)
    final drafts = await LocalStorageService.getDraftChallans();
    final ourDc = LocalStorageService.extractDcPart(widget.challanNumber ?? '');
    for (final d in drafts) {
      final match = (d.id != null && d.id == widget.challanId) ||
          (ourDc != null &&
              ourDc.isNotEmpty &&
              LocalStorageService.extractDcPart(d.challanNumber)?.toUpperCase() == ourDc.toUpperCase());
      if (match && d.items.isNotEmpty) return false;
    }
    try {
      final fetched = await ApiService.getChallanById(widget.challanId!);
      return fetched.items.isEmpty;
    } catch (_) {
      return true;
    }
  }

  void _goToMain() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (route) => false,
    );
  }

  Future<void> _handleBackPressed() async {
    if (!_isNewChallanFromForm) {
      _goToMain();
      return;
    }
    final bool noStoredItems = await _hasChallanNoStoredItems();
    if (!mounted) return;
    if (!noStoredItems) {
      _goToMain();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel challan?'),
        content: const Text(
          'No products selected on this challan. Do you want to cancel this challan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirm == true && widget.challanId != null) {
      try {
        await ApiService.deleteChallan(widget.challanId!);
      } catch (_) {
        // Still go back even if delete fails
      }
      final dc = LocalStorageService.extractDcPart(widget.challanNumber ?? '');
      if (dc != null && dc.isNotEmpty) {
        await LocalStorageService.removeDraftChallansByDcNumber(dc);
      }
      _goToMain();
    }
  }

  String _formatChallanDisplay(Challan challan) {
    return challan.challanNumber;
  }

  Future<void> _handleChallanSelected(Challan challan) async {
    // If it's the "New Challan" option (id == -1), create a real challan via API
    Challan challanToSelect = challan;
    if (challan.id == -1) {
      // Create a real challan instead of draft
      try {
        final challanData = {
          'party_name': widget.partyName ?? '',
          'station_name': widget.stationName ?? '',
          'transport_name': widget.transportName ?? '',
          'price_category': widget.priceCategory,
          'status': 'draft',
          'items': [],
        };
        final createdChallan = await ApiService.createChallan(challanData);
        challanToSelect = createdChallan;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create challan: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }
    }
    
    setState(() {
      _selectedChallan = challanToSelect;
      _challanController.text = challan.id == -1 
          ? 'Create New Challan' 
          : _formatChallanDisplay(challanToSelect);
    });

    // Don't navigate immediately - allow QR scanning for products
    // User can manually navigate using the button or scan products via QR
  }

  Future<void> _handleQRScan(String code) async {
    final trimmedCode = code.trim();
    
    // Prevent multiple scans of the same code
    if (_isScanning) return;
    if (_lastScannedCode == trimmedCode) {
      // Check if enough time has passed since last scan (2 seconds debounce)
      if (_lastScanTime != null && 
          DateTime.now().difference(_lastScanTime!) < const Duration(seconds: 2)) {
        return;
      }
    }
    
    setState(() {
      _isScanning = true;
      _lastScannedCode = trimmedCode;
      _lastScanTime = DateTime.now();
    });

    // Haptic feedback
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 100);
    }

    // If challan is selected, scan for products
    if (_selectedChallan != null) {
      try {
        final product = await ApiService.getProductByBarcode(trimmedCode);
        if (!mounted) return;
        
        // Fetch full product details with sizes
        Product? fullProduct = product;
        if (product.id != null) {
          try {
            fullProduct = await ApiService.getProductById(product.id!);
          } catch (e) {
            // Use the product from barcode if getById fails
          }
        }
        
        setState(() => _isScanning = false);
        
        // Navigate to item info screen with the scanned product
        if (fullProduct != null && fullProduct.id != null) {
          await _navigateToItemInfoWithProduct(fullProduct);
        } else {
          throw Exception('Invalid product data');
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isScanning = false;
          // Clear last scanned code on error to allow retry
          _lastScannedCode = null;
          _lastScanTime = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product not found: $e'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      // If no challan selected, scan for challan
      try {
        final challan = await ApiService.getChallanByNumber(trimmedCode);
        if (!mounted) return;
        setState(() => _isScanning = false);
        await _handleChallanSelected(challan);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isScanning = false;
          // Clear last scanned code on error to allow retry
          _lastScannedCode = null;
          _lastScanTime = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Challan not found: $e'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Helper function to get price based on price category
  double? _getPriceByCategory(ProductSize? size, String? priceCategory) {
    if (size == null) return null;
    
    // If no price category is selected, use minPrice as fallback
    if (priceCategory == null || priceCategory.isEmpty) {
      return size.minPrice;
    }
    
    // Map price category to price tier
    final category = priceCategory.toUpperCase().trim();
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

  Future<void> _navigateToItemInfoWithProduct(Product product) async {
    Challan? challanToUse = _selectedChallan;
    
    // If no challan is selected but we have challanId and challanNumber from widget, use them
    if (challanToUse == null && 
        widget.challanId != null && 
        widget.challanNumber != null &&
        widget.partyName != null && 
        widget.stationName != null && 
        widget.transportName != null) {
      challanToUse = Challan(
        id: widget.challanId,
        challanNumber: widget.challanNumber!,
        partyName: widget.partyName!,
        stationName: widget.stationName!,
        transportName: widget.transportName,
        priceCategory: widget.priceCategory,
        status: 'draft',
        items: [],
      );
    } else if (challanToUse == null && 
        widget.partyName != null && 
        widget.stationName != null && 
        widget.transportName != null) {
      // If no challan is selected and no challanId provided, create a real challan via API
      try {
        final challanData = {
          'party_name': widget.partyName!,
          'station_name': widget.stationName!,
          'transport_name': widget.transportName!,
          'price_category': widget.priceCategory,
          'status': 'draft',
          'items': [],
        };
        final challan = await ApiService.createChallan(challanData);
        challanToUse = challan;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create challan: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }
    } else if (challanToUse != null && widget.priceCategory != null && widget.priceCategory!.isNotEmpty) {
      challanToUse = Challan(
        id: challanToUse.id,
        challanNumber: challanToUse.challanNumber,
        partyName: challanToUse.partyName,
        stationName: challanToUse.stationName,
        transportName: challanToUse.transportName,
        priceCategory: widget.priceCategory,
        status: challanToUse.status,
        items: challanToUse.items,
      );
    }
    
    if (challanToUse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or scan a challan first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Create ChallanItems for ALL sizes of the product
    final priceCategory = challanToUse.priceCategory ?? widget.priceCategory;
    final List<ChallanItem> challanItems = [];

    if (product.sizes != null && product.sizes!.isNotEmpty) {
      // Create an item for each size, but skip sizes whose price is 0
      for (var size in product.sizes!) {
        final defaultPrice =
            _getPriceByCategory(size, priceCategory) ?? size.minPrice ?? 0;
        // Filter out sizes with zero or negative price – don't show them in the table
        if (defaultPrice <= 0) {
          continue;
        }
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

    // Stop scanner before navigation
    setState(() {
      _isNavigating = true;
    });
    
    try {
      await _scannerController.stop();
    } catch (e) {
      // Ignore errors when stopping scanner
    }

    // Check for existing draft challan number
    String? existingDraftNumber;
    try {
      final draftChallans = await LocalStorageService.getDraftChallans();
      final existingDraft = draftChallans.firstWhere(
        (c) =>
            c.partyName == challanToUse!.partyName &&
            c.stationName == challanToUse.stationName &&
            (c.transportName ?? '') == (challanToUse.transportName ?? '') &&
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

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemInfoChallanScreen(
          partyName: challanToUse!.partyName,
          stationName: challanToUse.stationName,
          transportName: challanToUse.transportName ?? '',
          priceCategory: priceCategory,
          initialItems: challanItems,
          challanId: challanToUse.id,
          challanNumber: challanToUse.challanNumber,
          draftChallanNumber: existingDraftNumber, // Fallback for backward compatibility
        ),
      ),
    );
  }

  Future<void> _navigateToProductSelection() async {
    Challan? challanToUse = _selectedChallan;
    
    // If no challan is selected but we have challanId and challanNumber from widget, use them
    if (challanToUse == null && 
        widget.challanId != null && 
        widget.challanNumber != null &&
        widget.partyName != null && 
        widget.stationName != null && 
        widget.transportName != null) {
      challanToUse = Challan(
        id: widget.challanId,
        challanNumber: widget.challanNumber!,
        partyName: widget.partyName!,
        stationName: widget.stationName!,
        transportName: widget.transportName,
        priceCategory: widget.priceCategory,
        status: 'draft',
        items: [],
      );
    } else if (challanToUse == null && 
        widget.partyName != null && 
        widget.stationName != null && 
        widget.transportName != null) {
      // If no challan is selected and no challanId provided, create a real challan via API
      try {
        final challanData = {
          'party_name': widget.partyName!,
          'station_name': widget.stationName!,
          'transport_name': widget.transportName!,
          'price_category': widget.priceCategory,
          'status': 'draft',
          'items': [],
        };
        final challan = await ApiService.createChallan(challanData);
        challanToUse = challan;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create challan: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }
    } else if (challanToUse != null && widget.priceCategory != null && widget.priceCategory!.isNotEmpty) {
      // If an existing challan is selected but form has priceCategory, update it
      challanToUse = Challan(
        id: challanToUse.id,
        challanNumber: challanToUse.challanNumber,
        partyName: challanToUse.partyName,
        stationName: challanToUse.stationName,
        transportName: challanToUse.transportName,
        priceCategory: widget.priceCategory, // Override with form's priceCategory
        status: challanToUse.status,
        items: challanToUse.items,
      );
    }
    
    if (challanToUse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or scan a challan'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Stop scanner before navigation
    setState(() {
      _isNavigating = true;
    });
    
    try {
      await _scannerController.stop();
    } catch (e) {
      // Ignore errors when stopping scanner
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChallanProductSelectionScreen(
          challan: challanToUse!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackPressed();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1A1A1A)),
          onPressed: _handleBackPressed,
        ),
        title: const Text(
          'Select Challan',
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
                      'Loading draft challans...',
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
                  // Select Challan Dropdown
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
                              Icons.receipt_long_rounded,
                              color: Color(0xFFB8860B),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Select Challan',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TypeAheadField<Challan>(
                          controller: _challanController,
                          builder: (context, controller, focusNode) {
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                hintText: 'Search challan by number or ID',
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
                                            _selectedChallan = null;
                                            _lastScannedCode = null;
                                            _lastScanTime = null;
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
                            final List<Challan> results = [];
                            
                            // Add "Create New Challan" option at the top if form data is provided
                            if (widget.partyName != null && 
                                widget.stationName != null && 
                                widget.transportName != null) {
                              // Create a special "New Challan" entry
                              results.add(Challan(
                                id: -1, // Special ID to identify new challan
                                challanNumber: 'NEW_CHALLAN',
                                partyName: widget.partyName!,
                                stationName: widget.stationName!,
                                transportName: widget.transportName,
                                priceCategory: widget.priceCategory,
                                status: 'draft',
                                items: [],
                              ));
                            }
                            
                            // Add draft challans
                            if (pattern.isEmpty) {
                              results.addAll(_draftChallans);
                            } else {
                              final search = pattern.toLowerCase();
                              final filtered = _draftChallans
                                  .where((challan) {
                                    return challan.challanNumber
                                            .toLowerCase()
                                            .contains(search) ||
                                        challan.partyName
                                            .toLowerCase()
                                            .contains(search) ||
                                        challan.stationName
                                            .toLowerCase()
                                            .contains(search);
                                  })
                                  .toList();
                              results.addAll(filtered);
                            }
                            
                            return results;
                          },
                          itemBuilder: (context, Challan suggestion) {
                            final isNewChallan = suggestion.id == -1;
                            
                            return Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.grey.shade200,
                                    width: 0.5,
                                  ),
                                ),
                                color: isNewChallan 
                                    ? const Color(0xFFFDF4E3) 
                                    : Colors.white,
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isNewChallan
                                        ? const Color(0xFFB8860B)
                                        : const Color(0xFFB8860B)
                                            .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isNewChallan 
                                        ? Icons.add_circle_outline_rounded
                                        : Icons.receipt_long_rounded,
                                    size: 20,
                                    color: isNewChallan 
                                        ? Colors.white 
                                        : const Color(0xFFB8860B),
                                  ),
                                ),
                                title: Text(
                                  isNewChallan 
                                      ? 'Create New Challan'
                                      : suggestion.challanNumber,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isNewChallan 
                                        ? const Color(0xFFB8860B)
                                        : const Color(0xFF1A1A1A),
                                  ),
                                ),
                                subtitle: isNewChallan
                                    ? Text(
                                        '${suggestion.partyName} • ${suggestion.stationName}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                      )
                                    : Text(
                                        '${suggestion.partyName} • ${suggestion.stationName}${suggestion.items != null && suggestion.items!.isNotEmpty ? ' • ${suggestion.items!.length} items' : ''}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                tileColor: isNewChallan 
                                    ? const Color(0xFFFDF4E3) 
                                    : Colors.white,
                              ),
                            );
                          },
                          onSelected: (Challan suggestion) {
                            _handleChallanSelected(suggestion);
                          },
                          hideOnEmpty: false,
                          hideOnError: false,
                          hideOnLoading: false,
                          debounceDuration: const Duration(milliseconds: 300),
                        ),
                      ],
                    ),
                  ),

                  // Continue with New Challan Button (only show when form data is provided and no challan selected)
                  if (widget.partyName != null && 
                      widget.stationName != null && 
                      widget.transportName != null &&
                      _selectedChallan == null)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ElevatedButton(
                        onPressed: _navigateToProductSelection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB8860B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.add_circle_outline, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Continue with New Challan',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Manual Product Selection Button (show when challan is selected)
                  if (_selectedChallan != null)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ElevatedButton(
                        onPressed: _navigateToProductSelection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB8860B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.inventory_2_outlined, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Select Products Manually',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Scan QR Code Section
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            _selectedChallan != null 
                                ? 'Scan Product QR Code' 
                                : 'Scan Challan QR Code',
                            style: const TextStyle(
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
                                      // Don't process scans if navigating or not mounted
                                      if (!mounted || _isNavigating) return;
                                      
                                      final barcodes = capture.barcodes;
                                      if (barcodes.isEmpty) return;
                                      
                                      final barcode = barcodes.first.rawValue;
                                      if (barcode == null || barcode.isEmpty) return;
                                      
                                      // Prevent multiple rapid scans
                                      if (_isScanning) return;
                                      
                                      _handleQRScan(barcode);
                                    },
                                  ),
                                  // QR Code Scanning Frame
                                  CustomPaint(
                                    painter: QRScannerOverlay(),
                                    child: Container(),
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


