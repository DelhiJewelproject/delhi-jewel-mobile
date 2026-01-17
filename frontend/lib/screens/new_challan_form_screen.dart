import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../services/api_service.dart';
import '../models/challan.dart';
import 'item_info_challan_screen.dart';
import 'challan_selection_scan_screen.dart';

class NewChallanFormScreen extends StatefulWidget {
  const NewChallanFormScreen({super.key});

  @override
  State<NewChallanFormScreen> createState() => _NewChallanFormScreenState();
}

class _NewChallanFormScreenState extends State<NewChallanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _partyController = TextEditingController();
  final TextEditingController _stationController = TextEditingController();
  final TextEditingController _transportController = TextEditingController();
  final TextEditingController _priceCategoryController =
      TextEditingController();

  List<String> _partyOptions = [];
  List<String> _stationOptions = [];
  List<String> _transportOptions = [];
  List<String> _priceCategories = [];

  bool _isLoadingOptions = false;
  bool _isLoadingPartyData = false;
  String? _errorMessage;

  // Responsive design variables
  late bool isMobile;
  late bool isTablet;
  late bool isDesktop;
  late double screenWidth;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  void _updateResponsiveVariables(BuildContext context) {
    screenWidth = MediaQuery.of(context).size.width;
    isMobile = screenWidth < 600;
    isTablet = screenWidth >= 600 && screenWidth < 1200;
    isDesktop = screenWidth >= 1200;
  }

  Future<void> _loadPartyData(String partyName) async {
    if (partyName.trim().isEmpty) return;

    setState(() => _isLoadingPartyData = true);

    try {
      // Get station and price_category from orders table
      final orderData = await ApiService.getPartyDataFromOrders(partyName.trim());
      
      // Get transport name from challan table (if available)
      Challan? matchingChallan;
      try {
        final challans = await ApiService.getChallans(
          search: partyName.trim(),
          limit: 10,
        );

        // Find the most recent challan with exact party name match
        for (var challan in challans) {
          if (challan.partyName.trim().toLowerCase() ==
              partyName.trim().toLowerCase()) {
            matchingChallan = challan;
            break; // Get the first one (most recent due to ordering)
          }
        }
      } catch (e) {
        // Silently fail for challan lookup - not critical
        if (kDebugMode) {
          print('Error loading challan data: $e');
        }
      }

      if (!mounted) return;

      bool hasChanges = false;

      // Auto-fill station from orders table (always update when party changes)
      if (orderData != null && 
          orderData['station'] != null && 
          orderData['station']!.toString().trim().isNotEmpty) {
        final newStation = orderData['station']!.toString().trim();
        if (_stationController.text != newStation) {
          _stationController.text = newStation;
          hasChanges = true;
        }
      }

      // Auto-fill price category from orders table (always update when party changes)
      if (orderData != null && 
          orderData['price_category'] != null && 
          orderData['price_category']!.toString().trim().isNotEmpty) {
        final newPriceCategory = orderData['price_category']!.toString().trim();
        if (_priceCategoryController.text != newPriceCategory) {
          _priceCategoryController.text = newPriceCategory;
          hasChanges = true;
        }
      }

      // Set transport name: default to "By Road", or use from challan if available (always update when party changes)
      String newTransport = 'By Road';
      if (matchingChallan != null &&
          matchingChallan.transportName != null &&
          matchingChallan.transportName!.isNotEmpty) {
        newTransport = matchingChallan.transportName!;
      }
      if (_transportController.text != newTransport) {
        _transportController.text = newTransport;
        hasChanges = true;
      }

      if (hasChanges) {
        setState(() {});

        // Show a subtle notification
        // if (mounted) {
        //   ScaffoldMessenger.of(context).showSnackBar(
        //     SnackBar(
        //       content: const Row(
        //         children: [
        //           Icon(Icons.auto_awesome, size: 18, color: Colors.white),
        //           SizedBox(width: 8),
        //           Text('Fields auto-filled from orders and challan data'),
        //         ],
        //       ),
        //       backgroundColor: const Color(0xFF10B981),
        //       duration: const Duration(seconds: 2),
        //       behavior: SnackBarBehavior.floating,
        //     ),
        //   );
        // }
      }
    } catch (e) {
      // Silently fail - don't show error for auto-fill
      if (kDebugMode) {
        print('Error loading party data: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingPartyData = false);
      }
    }
  }

  Future<void> _loadOptions() async {
    setState(() {
      _isLoadingOptions = true;
      _errorMessage = null;
    });
    try {
      final options = await ApiService.getChallanOptions();
      if (!mounted) return;

      // Remove duplicates and normalize data
      final rawPartyNames = List<String>.from(options['party_names'] ?? []);
      final rawStationNames = List<String>.from(options['station_names'] ?? []);

      // Deduplicate party names (case-insensitive)
      final seenParty = <String>{};
      final partyNames = <String>[];
      for (var name in rawPartyNames) {
        if (name.isNotEmpty) {
          final normalized = name.trim().toLowerCase();
          if (normalized.isNotEmpty && !seenParty.contains(normalized)) {
            seenParty.add(normalized);
            partyNames.add(name.trim());
          }
        }
      }

      // Deduplicate station names (case-insensitive)
      final seenStation = <String>{};
      final stationNames = <String>[];
      for (var name in rawStationNames) {
        if (name.isNotEmpty) {
          final normalized = name.trim().toLowerCase();
          if (normalized.isNotEmpty && !seenStation.contains(normalized)) {
            seenStation.add(normalized);
            stationNames.add(name.trim());
          }
        }
      }

      // Sort for better UX
      partyNames.sort();
      stationNames.sort();

      setState(() {
        _partyOptions = partyNames;
        _stationOptions = stationNames;
        _transportOptions = List<String>.from(options['transport_names'] ?? [])
            .where((name) => name.isNotEmpty)
            .map((name) => name.trim())
            .toSet()
            .toList()
          ..sort();
        _priceCategories = List<String>.from(options['price_categories'] ?? [])
            .where((name) => name != null && name.toString().isNotEmpty)
            .map((name) => name.toString().trim())
            .toSet()
            .toList()
          ..sort();
        _isLoadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingOptions = false;
        _errorMessage = 'Unable to load options. Please check your connection.';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to load options: ${e.toString().split(':').last}'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadOptions,
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final partyName = _partyController.text.trim();
    final stationName = _stationController.text.trim();
    final transportName = _transportController.text.trim();
    final priceCategory = _priceCategoryController.text.trim().isEmpty
        ? null
        : _priceCategoryController.text.trim();

    // Create challan immediately after party details are entered
    setState(() => _isLoadingOptions = true);
    try {
      final challanData = {
        'party_name': partyName,
        'station_name': stationName,
        'transport_name': transportName,
        'price_category': priceCategory,
        'status': 'draft',
        'items': [], // No items yet, will be added later
      };

      final challan = await ApiService.createChallan(challanData);
      
    if (!mounted) return;
      
      // Navigate with the created challan
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChallanSelectionScanScreen(
          partyName: partyName,
          stationName: stationName,
          transportName: transportName,
          priceCategory: priceCategory,
            challanId: challan.id,
            challanNumber: challan.challanNumber,
        ),
      ),
    );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingOptions = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create challan: ${e.toString().split(':').last}'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void dispose() {
    _partyController.dispose();
    _stationController.dispose();
    _transportController.dispose();
    _priceCategoryController.dispose();
    super.dispose();
  }

  Widget _buildFormField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    required List<String> options,
    required String? Function(String?) validator,
    bool isRequired = true,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: isMobile ? 16 : 18, color: const Color(0xFFB8860B)),
              SizedBox(width: isMobile ? 6 : 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: isMobile ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A1A),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (isRequired) ...[
                const SizedBox(width: 4),
                const Text(
                  '*',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: isMobile ? 8 : 10),
          TypeAheadField<String>(
            controller: controller,
            builder: (context, textController, focusNode) {
              return TextFormField(
                controller: textController,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: isMobile ? 14 : 15,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 14 : 16,
                    vertical: isMobile ? 14 : 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                    borderSide: BorderSide(
                      color: Colors.grey.shade300,
                      width: 1.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                    borderSide: BorderSide(
                      color: Colors.grey.shade300,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                    borderSide: const BorderSide(
                      color: Color(0xFFB8860B),
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                    borderSide: BorderSide(
                      color: Colors.red.shade300,
                      width: 1.5,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                    borderSide: BorderSide(
                      color: Colors.red.shade400,
                      width: 2,
                    ),
                  ),
                  prefixIcon: Icon(
                    icon,
                    color: Colors.grey.shade600,
                    size: isMobile ? 18 : 20,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller == _partyController && _isLoadingPartyData)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                const Color(0xFFB8860B),
                              ),
                            ),
                          ),
                        ),
                      if (textController.text.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: isMobile ? 18 : 20,
                            color: Colors.grey.shade400,
                          ),
                          onPressed: () {
                            textController.clear();
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
                style: TextStyle(
                  fontSize: isMobile ? 14 : 15,
                  color: const Color(0xFF1A1A1A),
                ),
                validator: validator,
                onChanged: (value) {
                  setState(() {});
                  // Auto-fill when party name changes (always update fields)
                  if (controller == _partyController && value.isNotEmpty) {
                    final trimmedValue = value.trim();
                    // Debounce: wait a bit before auto-filling to avoid too many API calls
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted &&
                          _partyController.text.trim().toLowerCase() ==
                              trimmedValue.toLowerCase()) {
                        _loadPartyData(trimmedValue);
                      }
                    });
                  }
                },
              );
            },
            suggestionsCallback: (pattern) async {
              // Return all options when pattern is empty, or filtered options
              if (pattern.isEmpty) {
                return options;
              }
              return options
                  .where((option) =>
                      option.toLowerCase().contains(pattern.toLowerCase()))
                  .toList();
            },
            itemBuilder: (context, suggestion) {
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
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 16,
                    vertical: isMobile ? 10 : 12,
                  ),
                  leading: Container(
                    padding: EdgeInsets.all(isMobile ? 5 : 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB8860B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: isMobile ? 16 : 18,
                      color: const Color(0xFFB8860B),
                    ),
                  ),
                  title: Text(
                    suggestion,
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 15,
                      color: const Color(0xFF1A1A1A),
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  tileColor: Colors.white,
                  dense: true,
                ),
              );
            },
            onSelected: (suggestion) {
              controller.text = suggestion;
              setState(() {});

              // If party name is selected, try to auto-fill other fields
              if (controller == _partyController) {
                _loadPartyData(suggestion);
              }
            },
            hideOnEmpty: false,
            hideOnError: false,
            hideOnLoading: false,
            debounceDuration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header Card
          // Container(
          //   padding: const EdgeInsets.all(16),
          //   decoration: BoxDecoration(
          //     color: Colors.white,
          //     borderRadius: BorderRadius.circular(12),
          //     boxShadow: [
          //       BoxShadow(
          //         color: Colors.black.withOpacity(0.05),
          //         blurRadius: 8,
          //         offset: const Offset(0, 2),
          //       ),
          //     ],
          //   ),
          //   child: Row(
          //     children: [
          //       Container(
          //         padding: const EdgeInsets.all(10),
          //         decoration: BoxDecoration(
          //           color: const Color(0xFFB8860B).withOpacity(0.1),
          //           borderRadius: BorderRadius.circular(10),
          //         ),
          //         child: const Icon(
          //           Icons.description_outlined,
          //           color: Color(0xFFB8860B),
          //           size: 22,
          //         ),
          //       ),
          //       const SizedBox(width: 12),
          //       Expanded(
          //         child: Column(
          //           crossAxisAlignment: CrossAxisAlignment.start,
          //           children: [
          //             const Text(
          //               'New Challan',
          //               style: TextStyle(
          //                 fontSize: 16,
          //                 fontWeight: FontWeight.bold,
          //                 color: Color(0xFF1A1A1A),
          //               ),
          //             ),
          //             const SizedBox(height: 2),
          //             Text(
          //               'Enter the required details',
          //               style: TextStyle(
          //                 fontSize: 12,
          //                 color: Colors.grey.shade600,
          //               ),
          //             ),
          //           ],
          //         ),
          //       ),
          //     ],
          //   ),
          // ),
          // const SizedBox(height: 16),

          // Form Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildFormField(
                    label: 'Party Name',
                    hint: 'Select or enter party name',
                    icon: Icons.business,
                    controller: _partyController,
                    options: _partyOptions,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Party name is required';
                      }
                      return null;
                    },
                  ),
                  _buildFormField(
                    label: 'Station Name',
                    hint: 'Select or enter station name',
                    icon: Icons.location_on,
                    controller: _stationController,
                    options: _stationOptions,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Station name is required';
                      }
                      return null;
                    },
                  ),
                  _buildFormField(
                    label: 'Price Category',
                    hint: 'Select price category (optional)',
                    icon: Icons.currency_rupee,
                    controller: _priceCategoryController,
                    options: _priceCategories,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please select a price category';
                      }
                      return null;
                    },
                    isRequired: true,
                  ),
                  _buildFormField(
                    label: 'Transport Name',
                    hint: 'Select or enter transport name',
                    icon: Icons.local_shipping,
                    controller: _transportController,
                    options: _transportOptions,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Transport name is required';
                      }
                      return null;
                    },
                  ),
                  
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
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
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB8860B).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
                            color: Color(0xFFB8860B),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Create New Challan',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Fill in the basic information to start a new challan',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Form Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildFormField(
                        label: 'Party Name',
                        hint: 'Select or enter party name',
                        icon: Icons.business,
                        controller: _partyController,
                        options: _partyOptions,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Party name is required';
                          }
                          return null;
                        },
                      ),
                      _buildFormField(
                        label: 'Station Name',
                        hint: 'Select or enter station name',
                        icon: Icons.location_on,
                        controller: _stationController,
                        options: _stationOptions,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Station name is required';
                          }
                          return null;
                        },
                      ),
                      _buildFormField(
                        label: 'Transport Name',
                        hint: 'Select or enter transport name',
                        icon: Icons.local_shipping,
                        controller: _transportController,
                        options: _transportOptions,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Transport name is required';
                          }
                          return null;
                        },
                      ),
                      _buildFormField(
                        label: 'Price Category',
                        hint: 'Select price category (optional)',
                        icon: Icons.currency_rupee,
                        controller: _priceCategoryController,
                        options: _priceCategories,
                        validator: (value) => null,
                        isRequired: false,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Panel - Info
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB8860B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          color: Color(0xFFB8860B),
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'New Challan',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Create a new challan by filling in the basic information. '
                        'All fields with * are required.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Quick Tips:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 14,
                                  color: const Color(0xFFB8860B),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Party name auto-fills other fields',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.search,
                                  size: 14,
                                  color: const Color(0xFFB8860B),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Type to filter dropdown options',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 32),

              // Right Panel - Form
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _buildFormField(
                          label: 'Party Name',
                          hint: 'Select or enter party name',
                          icon: Icons.business,
                          controller: _partyController,
                          options: _partyOptions,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Party name is required';
                            }
                            return null;
                          },
                        ),
                        _buildFormField(
                          label: 'Station Name',
                          hint: 'Select or enter station name',
                          icon: Icons.location_on,
                          controller: _stationController,
                          options: _stationOptions,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Station name is required';
                            }
                            return null;
                          },
                        ),
                        _buildFormField(
                          label: 'Transport Name',
                          hint: 'Select or enter transport name',
                          icon: Icons.local_shipping,
                          controller: _transportController,
                          options: _transportOptions,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Transport name is required';
                            }
                            return null;
                          },
                        ),
                        _buildFormField(
                          label: 'Price Category',
                          hint: 'Select price category (optional)',
                          icon: Icons.currency_rupee,
                          controller: _priceCategoryController,
                          options: _priceCategories,
                          validator: (value) => null,
                          isRequired: false,
                        ),
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

  Widget _buildSubmitButton() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : isTablet ? 24 : 32,
        vertical: isMobile ? 16 : 24,
      ),
      child: Column(
        children: [
          Container(
            height: isMobile ? 50 : 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB8860B).withOpacity(0.3),
                  blurRadius: isMobile ? 8 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB8860B),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                ),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Continue to Add Items',
                    style: TextStyle(
                      fontSize: isMobile ? 15 : 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(width: isMobile ? 6 : 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: isMobile ? 18 : 20,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: isMobile ? 8 : 16),
          Center(
            child: Text(
              'You can add products in the next step',
              style: TextStyle(
                fontSize: isMobile ? 12 : 13,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _updateResponsiveVariables(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: isDesktop
          ? null
          : AppBar(
              elevation: 0,
              backgroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Color(0xFF1A1A1A)),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                'New Challan',
                style: TextStyle(
                  color: const Color(0xFF1A1A1A),
                  fontSize: isMobile ? 18 : 20,
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
      body: _isLoadingOptions
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
                    'Loading options...',
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : _errorMessage != null && _partyOptions.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 20 : 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: isMobile ? 48 : 64,
                          color: const Color(0xFFFFCDD2),
                        ),
                        SizedBox(height: isMobile ? 16 : 20),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isMobile ? 14 : 16,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        SizedBox(height: isMobile ? 20 : 24),
                        ElevatedButton.icon(
                          onPressed: _loadOptions,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB8860B),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 20 : 24,
                              vertical: isMobile ? 10 : 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: isMobile
                          ? _buildMobileLayout()
                          : isTablet
                              ? _buildTabletLayout()
                              : _buildDesktopLayout(),
                    ),
                    _buildSubmitButton(),
                  ],
                ),
    );
  }
}