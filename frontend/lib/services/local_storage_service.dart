import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/challan.dart';

class LocalStorageService {
  static const String _draftChallansKey = 'draft_challans';
  static const String _draftOrderKey = 'draft_order';

  /// DCs we just removed (End Challan). Block re-adding them for a short window so late saveDraftChallan doesn't resurrect the draft.
  static final Set<String> _recentlyRemovedDcs = {};
  static DateTime? _recentlyRemovedClearAt;
  static const Duration _recentlyRemovedWindow = Duration(seconds: 3);

  /// Canonical format for draft challan number in local storage: DC-only (e.g. DC009504), no party name.
  /// Matches server format after finalization so sync and removal work reliably.
  static String _normalizeChallanNumberForStorage(String challanNumber) {
    final dc = extractDcPart(challanNumber);
    return (dc ?? challanNumber.trim()).isNotEmpty ? (dc ?? challanNumber.trim()) : challanNumber.trim();
  }

  // Save a draft challan to local storage. Stores challanNumber as DC-only (e.g. DC009504) to match server.
  static Future<void> saveDraftChallan(Challan challan) async {
    try {
      final challanNum = challan.challanNumber.trim();
      final incomingDc = extractDcPart(challanNum);
      final storageNumber = _normalizeChallanNumberForStorage(challanNum);

      // Don't re-add a draft we just removed (End Challan) — avoids late callbacks resurrecting it
      final now = DateTime.now();
      if (_recentlyRemovedClearAt != null && now.isAfter(_recentlyRemovedClearAt!)) {
        _recentlyRemovedDcs.clear();
        _recentlyRemovedClearAt = null;
      }
      if (incomingDc != null &&
          incomingDc.isNotEmpty &&
          _recentlyRemovedDcs.contains(incomingDc.toUpperCase())) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final draftChallans = await getDraftChallans();

      // 1) Match by DC (storage is always DC-only)
      int existingIndex = draftChallans.indexWhere((c) {
        final dc = extractDcPart(c.challanNumber);
        return dc != null && dc.toUpperCase() == (incomingDc ?? '').toUpperCase();
      });
      bool matchedByNumber = existingIndex >= 0;

      if (existingIndex == -1) {
        existingIndex = draftChallans.indexWhere((c) =>
            c.partyName == challan.partyName &&
            c.stationName == challan.stationName &&
            (c.transportName ?? '') == (challan.transportName ?? '') &&
            c.status == 'draft');
      }
      if (existingIndex == -1 && challan.id != null) {
        existingIndex = draftChallans.indexWhere((c) =>
            c.id != null && c.id == challan.id);
      }
      if (existingIndex == -1 && incomingDc != null && incomingDc.isNotEmpty) {
        existingIndex = draftChallans.indexWhere((c) {
          final dc = extractDcPart(c.challanNumber);
          return dc != null && dc.toUpperCase() == incomingDc.toUpperCase();
        });
      }

      if (existingIndex != -1) {
        final existing = draftChallans[existingIndex];
        final sameChallan = incomingDc != null &&
            (extractDcPart(existing.challanNumber)?.toUpperCase() == incomingDc.toUpperCase());
        final itemsToSave = (matchedByNumber || sameChallan)
            ? challan.items
            : _mergeDraftItems(existing.items, challan.items);
        draftChallans[existingIndex] = Challan(
          id: existing.id ?? challan.id,
          challanNumber: storageNumber,
          partyName: challan.partyName,
          stationName: challan.stationName,
          transportName: challan.transportName,
          priceCategory: challan.priceCategory ?? existing.priceCategory,
          status: 'draft',
          items: itemsToSave,
        );
      } else {
        draftChallans.add(Challan(
          id: challan.id,
          challanNumber: storageNumber,
          partyName: challan.partyName,
          stationName: challan.stationName,
          transportName: challan.transportName,
          priceCategory: challan.priceCategory,
          totalAmount: challan.totalAmount,
          totalQuantity: challan.totalQuantity,
          status: 'draft',
          items: challan.items,
        ));
      }

      // Always persist with DC-only challan numbers
      final normalized = draftChallans.map((c) {
        final dc = _normalizeChallanNumberForStorage(c.challanNumber);
        return dc != c.challanNumber ? c.copyWith(challanNumber: dc) : c;
      }).toList();
      final jsonList = normalized.map((c) => c.toJson()).toList();
      print('[DRAFT_SAVE] Saving draft: incoming challanNumber="$challanNum", storageNumber (DC-only)="$storageNumber", total drafts=${jsonList.length}');
      for (var i = 0; i < jsonList.length; i++) {
        final m = jsonList[i] as Map<String, dynamic>;
        print('[DRAFT_SAVE]   draft[$i]: challan_number="${m['challan_number']}", party_name="${m['party_name']}"');
      }
      await prefs.setString(_draftChallansKey, json.encode(jsonList));
    } catch (e) {
      print('Error saving draft challan: $e');
    }
  }

  static List<ChallanItem> _mergeDraftItems(List<ChallanItem> existing, List<ChallanItem> incoming) {
    final merged = <ChallanItem>[];
    merged.addAll(existing);
    final existingKeys = existing.map((item) =>
        '${item.productId ?? 'null'}_${item.sizeId ?? 'null'}').toSet();
    for (var newItem in incoming) {
      final key = '${newItem.productId ?? 'null'}_${newItem.sizeId ?? 'null'}';
      if (!existingKeys.contains(key)) {
        merged.add(newItem);
      } else {
        final i = merged.indexWhere((item) =>
            '${item.productId ?? 'null'}_${item.sizeId ?? 'null'}' == key);
        if (i != -1 && newItem.quantity > merged[i].quantity) merged[i] = newItem;
      }
    }
    return merged;
  }

  // Get all draft challans from local storage. Returns challans with DC-only challanNumber; migrates storage if needed.
  static Future<List<Challan>> getDraftChallans() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_draftChallansKey);
      
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      
      final jsonList = json.decode(jsonString) as List<dynamic>;
      final list = jsonList.map((j) => Challan.fromJson(j as Map<String, dynamic>)).toList();
      // Normalize to DC-only so sync/removal match server; persist if any had party name (migrate)
      bool anyChanged = false;
      final normalized = list.map((c) {
        final dc = _normalizeChallanNumberForStorage(c.challanNumber);
        if (dc != c.challanNumber) {
          anyChanged = true;
          return c.copyWith(challanNumber: dc);
        }
        return c;
      }).toList();
      if (anyChanged) {
        final jsonToSave = normalized.map((c) => c.toJson()).toList();
        await prefs.setString(_draftChallansKey, json.encode(jsonToSave));
      }
      return normalized;
    } catch (e) {
      print('Error loading draft challans: $e');
      return [];
    }
  }

  // Remove a draft challan from local storage (match by DC-only challanNumber)
  static Future<void> removeDraftChallan(String challanNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftChallans = await getDraftChallans();
      final keyDc = _normalizeChallanNumberForStorage(challanNumber);
      final key = challanNumber.trim();
      draftChallans.removeWhere((c) {
        final cn = c.challanNumber.trim();
        final cDc = extractDcPart(c.challanNumber);
        return cn == key || cn == keyDc || (cDc != null && cDc == keyDc);
      });
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

  /// Extract "DC009546" from "SSN - DC009546", "DC009546", or "DC-009546". Public for sync use.
  static String? extractDcPart(String challanNumber) {
    final trimmed = challanNumber.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'DC-?\d+', caseSensitive: false).firstMatch(trimmed);
    final raw = match?.group(0);
    if (raw == null) return null;
    return raw.replaceAll('-', ''); // normalize DC-009546 -> DC009546
  }

  static String? _extractDcPart(String challanNumber) => extractDcPart(challanNumber);

  /// Remove any draft that matches the ended challan (by id, exact number, partyName - challanNumber, or DC part).
  /// Call this after End Challan so the draft disappears from Old Challans.
  /// Prefer matching by "partyName - challanNumber" (e.g. TESTPARTY - DC009545) since that's how drafts are stored.
  static Future<void> removeDraftChallanAfterEnd({
    required int? endedChallanId,
    required String serverChallanNumber,
    String? localChallanNumber,
    String? partyName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftChallans = await getDraftChallans();
      final serverDc = _extractDcPart(serverChallanNumber);
      final localDc = localChallanNumber != null ? _extractDcPart(localChallanNumber) : null;
      final partyDc = partyName != null && partyName.trim().isNotEmpty && serverDc != null
          ? '${partyName.trim()} - $serverDc'
          : null;
      final before = draftChallans.length;
      bool sameIgnoreCase(String a, String b) =>
          a.trim().toLowerCase() == b.trim().toLowerCase();

      // [DEBUG] What's in local storage when we try to remove
      print('[DRAFT_REMOVE] removeDraftChallanAfterEnd: serverChallanNumber="$serverChallanNumber", localChallanNumber="$localChallanNumber", partyName="$partyName", endedChallanId=$endedChallanId');
      print('[DRAFT_REMOVE] Current drafts in storage (count=${draftChallans.length}): challanNumbers=${draftChallans.map((c) => '"${c.challanNumber}"').toList()}');

      draftChallans.removeWhere((c) {
        if (endedChallanId != null && c.id == endedChallanId) return true;
        final cn = c.challanNumber.trim();
        final serverNum = serverChallanNumber.trim();
        if (sameIgnoreCase(cn, serverNum)) return true;
        if (localChallanNumber != null && sameIgnoreCase(cn, localChallanNumber)) return true;
        if (partyDc != null && sameIgnoreCase(cn, partyDc)) return true;
        if (partyDc != null && partyName != null) {
          final draftDc = _extractDcPart(c.challanNumber);
          if (c.partyName.trim().isNotEmpty && draftDc != null) {
            final draftPartyDc = '${c.partyName.trim()} - $draftDc';
            if (sameIgnoreCase(draftPartyDc, partyDc)) return true;
          }
        }
        final dc = _extractDcPart(c.challanNumber);
        if (dc != null && serverDc != null && dc == serverDc) return true;
        if (dc != null && localDc != null && dc == localDc) return true;
        return false;
      });
      print('[DRAFT_REMOVE] After removeDraftChallanAfterEnd: count=${draftChallans.length}');
      // Block re-adding this DC for a short window so late saveDraftChallan doesn't resurrect the draft
      if (serverDc != null && serverDc.isNotEmpty) _recentlyRemovedDcs.add(serverDc.toUpperCase());
      if (localDc != null && localDc.isNotEmpty) _recentlyRemovedDcs.add(localDc.toUpperCase());
      _recentlyRemovedClearAt = DateTime.now().add(_recentlyRemovedWindow);
      // Always persist so local storage is updated (ended challans disappear from Old Challans)
      final jsonList = draftChallans.map((c) => c.toJson()).toList();
      await prefs.setString(_draftChallansKey, json.encode(jsonList));
    } catch (e) {
      print('Error removing draft after end: $e');
    }
  }

  /// Read challan number from a raw draft item (supports both challan_number and challanNumber keys).
  static String _getChallanNumberFromRaw(Map<String, dynamic> item) {
    final v = item['challan_number'] ?? item['challanNumber'];
    return (v == null ? '' : v.toString()).trim();
  }

  /// Extract DC from raw draft item for comparison (same keys as storage).
  static String? getDcFromRawDraft(Map<String, dynamic> item) {
    final numStr = _getChallanNumberFromRaw(item);
    return extractDcPart(numStr);
  }

  /// Raw read of draft_challans – returns decoded list so sync uses exact stored data.
  static Future<List<Map<String, dynamic>>> getRawDraftChallansList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftChallansKey);
      if (raw == null || raw.isEmpty) return [];
      final list = json.decode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('Error getRawDraftChallansList: $e');
      return [];
    }
  }

  /// Remove ALL drafts whose challan number matches this DC (e.g. DC009504).
  static Future<void> removeDraftChallansByDcNumber(String dcNumber) async {
    if (dcNumber.trim().isEmpty) return;
    final targetDc = (extractDcPart(dcNumber) ?? dcNumber.trim()).toUpperCase();
    if (targetDc.isEmpty) return;
    await removeDraftChallansByDcNumbers([targetDc]);
  }

  /// Remove ALL drafts whose DC is in [dcNumbers]. Uses [rawList] if provided (same read as sync), else reads from prefs.
  static Future<void> removeDraftChallansByDcNumbers(Iterable<String> dcNumbers, [List<Map<String, dynamic>>? rawList]) async {
    final targetSet = dcNumbers.map((n) => (extractDcPart(n) ?? n.trim()).toUpperCase()).where((s) => s.isNotEmpty).toSet();
    if (targetSet.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      List<Map<String, dynamic>> list;
      if (rawList != null) {
        list = rawList;
      } else {
        final raw = prefs.getString(_draftChallansKey);
        if (raw == null || raw.isEmpty) return;
        final decoded = json.decode(raw) as List<dynamic>;
        list = decoded.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      print('[DRAFT_REMOVE] removeDraftChallansByDcNumbers: targetSet (DCs to remove)=$targetSet, rawListCount=${list.length}');
      for (final dc in targetSet) {
        _recentlyRemovedDcs.add(dc);
      }
      _recentlyRemovedClearAt = DateTime.now().add(_recentlyRemovedWindow);
      final kept = <Map<String, dynamic>>[];
      for (final item in list) {
        final numStr = _getChallanNumberFromRaw(item);
        final dc = (extractDcPart(numStr) ?? '').toUpperCase();
        if (dc.isEmpty || !targetSet.contains(dc)) kept.add(item);
      }
      print('[DRAFT_REMOVE] Result: kept ${kept.length}, removed ${list.length - kept.length}');
      await prefs.setString(_draftChallansKey, json.encode(kept));
    } catch (e) {
      print('Error removeDraftChallansByDcNumbers: $e');
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

  // ========== PRODUCT SEARCH HISTORY METHODS ==========
  static const String _productSearchHistoryKey = 'product_search_history';
  static const int _maxHistoryItems = 50; // Keep top 50 most/recently searched products

  /// Save a product search (when user selects a product)
  static Future<void> saveProductSearch(int productId, String productName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = await getProductSearchHistory();
      
      // Remove existing entry if present (to update timestamp)
      history.removeWhere((item) => item['product_id'] == productId);
      
      // Add to front with current timestamp
      history.insert(0, {
        'product_id': productId,
        'product_name': productName,
        'searched_at': DateTime.now().toIso8601String(),
        'search_count': 1, // Will be updated if exists
      });
      
      // Keep only top N items
      if (history.length > _maxHistoryItems) {
        history.removeRange(_maxHistoryItems, history.length);
      }
      
      await prefs.setString(_productSearchHistoryKey, json.encode(history));
    } catch (e) {
      print('Error saving product search: $e');
    }
  }

  /// Get product search history (sorted by most recent and most frequent)
  static Future<List<Map<String, dynamic>>> getProductSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_productSearchHistoryKey);
      
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      
      final history = json.decode(jsonString) as List<dynamic>;
      return history.map((item) => Map<String, dynamic>.from(item as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error loading product search history: $e');
      return [];
    }
  }

  /// Get product IDs from search history (for filtering products)
  static Future<List<int>> getProductSearchHistoryIds() async {
    final history = await getProductSearchHistory();
    return history.map((item) => item['product_id'] as int).whereType<int>().toList();
  }

  /// Clear product search history
  static Future<void> clearProductSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_productSearchHistoryKey);
    } catch (e) {
      print('Error clearing product search history: $e');
    }
  }
}

