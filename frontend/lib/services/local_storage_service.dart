import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/challan.dart';

class LocalStorageService {
  static const String _draftChallansKey = 'draft_challans';
  static const String _draftOrderKey = 'draft_order';

  // Save a draft challan to local storage
  static Future<void> saveDraftChallan(Challan challan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftChallans = await getDraftChallans();
      
      // First check by challan number (most specific)
      int existingIndex = draftChallans.indexWhere((c) => 
        c.challanNumber == challan.challanNumber && challan.challanNumber.isNotEmpty
      );
      
      // If not found by challan number, check by party/station/transport combination
      // This ensures we update the same draft challan even if number changes
      if (existingIndex == -1) {
        existingIndex = draftChallans.indexWhere((c) => 
          c.partyName == challan.partyName &&
          c.stationName == challan.stationName &&
          (c.transportName ?? '') == (challan.transportName ?? '') &&
          c.status == 'draft' // Only match draft challans
        );
      }
      
      // Also check by ID if both have IDs
      if (existingIndex == -1 && challan.id != null) {
        existingIndex = draftChallans.indexWhere((c) => 
          c.id != null && c.id == challan.id
        );
      }
      
      if (existingIndex != -1) {
        // Update existing challan - merge items to avoid losing data
        final existing = draftChallans[existingIndex];
        final mergedItems = <ChallanItem>[];
        
        // Add existing items
        mergedItems.addAll(existing.items);
        
        // Add new items that don't exist (by productId + sizeId)
        final existingKeys = existing.items.map((item) => 
          '${item.productId ?? 'null'}_${item.sizeId ?? 'null'}'
        ).toSet();
        
        for (var newItem in challan.items) {
          final key = '${newItem.productId ?? 'null'}_${newItem.sizeId ?? 'null'}';
          if (!existingKeys.contains(key)) {
            mergedItems.add(newItem);
          } else {
            // Update existing item with new quantity if it's greater
            final existingItemIndex = mergedItems.indexWhere((item) => 
              '${item.productId ?? 'null'}_${item.sizeId ?? 'null'}' == key
            );
            if (existingItemIndex != -1 && newItem.quantity > mergedItems[existingItemIndex].quantity) {
              mergedItems[existingItemIndex] = newItem;
            }
          }
        }
        
        // Update the existing challan with merged items
        draftChallans[existingIndex] = Challan(
          id: existing.id,
          challanNumber: challan.challanNumber.isNotEmpty ? challan.challanNumber : existing.challanNumber,
          partyName: challan.partyName,
          stationName: challan.stationName,
          transportName: challan.transportName,
          priceCategory: challan.priceCategory ?? existing.priceCategory,
          status: 'draft',
          items: mergedItems,
        );
      } else {
        // Add new challan only if it doesn't exist
        draftChallans.add(challan);
      }
      
      // Convert to JSON and save
      final jsonList = draftChallans.map((c) => c.toJson()).toList();
      await prefs.setString(_draftChallansKey, json.encode(jsonList));
    } catch (e) {
      print('Error saving draft challan: $e');
    }
  }

  // Get all draft challans from local storage
  static Future<List<Challan>> getDraftChallans() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_draftChallansKey);
      
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      
      final jsonList = json.decode(jsonString) as List<dynamic>;
      return jsonList.map((json) => Challan.fromJson(json)).toList();
    } catch (e) {
      print('Error loading draft challans: $e');
      return [];
    }
  }

  // Remove a draft challan from local storage
  static Future<void> removeDraftChallan(String challanNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftChallans = await getDraftChallans();
      
      draftChallans.removeWhere((c) => c.challanNumber == challanNumber);
      
      final jsonList = draftChallans.map((c) => c.toJson()).toList();
      await prefs.setString(_draftChallansKey, json.encode(jsonList));
    } catch (e) {
      print('Error removing draft challan: $e');
    }
  }

  // Remove a draft challan by ID
  static Future<void> removeDraftChallanById(int? id) async {
    if (id == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftChallans = await getDraftChallans();
      
      draftChallans.removeWhere((c) => c.id == id);
      
      final jsonList = draftChallans.map((c) => c.toJson()).toList();
      await prefs.setString(_draftChallansKey, json.encode(jsonList));
    } catch (e) {
      print('Error removing draft challan: $e');
    }
  }

  // Clear all draft challans
  static Future<void> clearAllDraftChallans() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftChallansKey);
    } catch (e) {
      print('Error clearing draft challans: $e');
    }
  }

  // ========== DRAFT ORDER METHODS ==========
  
  // Save a draft order to local storage
  static Future<void> saveDraftOrder({
    required String orderNumber,
    required Map<String, dynamic> orderData,
    List<ChallanItem>? storedItems,
    Map<String, Map<String, int>>? designAllocations,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftOrder = {
        'order_number': orderNumber,
        'order_data': orderData,
        'stored_items': storedItems?.map((item) => item.toJson()).toList() ?? [],
        'design_allocations': designAllocations ?? {},
        'saved_at': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_draftOrderKey, json.encode(draftOrder));
    } catch (e) {
      print('Error saving draft order: $e');
    }
  }

  // Get draft order from local storage
  static Future<Map<String, dynamic>?> getDraftOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_draftOrderKey);
      
      if (jsonString == null || jsonString.isEmpty) {
        return null;
      }
      
      final draftOrder = json.decode(jsonString) as Map<String, dynamic>;
      
      // Convert stored_items back to ChallanItem list
      final storedItemsJson = draftOrder['stored_items'] as List<dynamic>? ?? [];
      final storedItems = storedItemsJson
          .map((item) => ChallanItem.fromJson(item as Map<String, dynamic>))
          .toList();
      
      // Convert design_allocations
      final designAllocationsJson = draftOrder['design_allocations'] as Map<String, dynamic>? ?? {};
      final designAllocations = designAllocationsJson.map(
        (key, value) => MapEntry(
          key,
          Map<String, int>.from(value as Map<String, dynamic>)
        )
      );
      
      return {
        'order_number': draftOrder['order_number'] as String,
        'order_data': draftOrder['order_data'] as Map<String, dynamic>,
        'stored_items': storedItems,
        'design_allocations': designAllocations,
        'saved_at': draftOrder['saved_at'] as String?,
      };
    } catch (e) {
      print('Error loading draft order: $e');
      return null;
    }
  }

  // Remove draft order from local storage
  static Future<void> removeDraftOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftOrderKey);
    } catch (e) {
      print('Error removing draft order: $e');
    }
  }
}

