import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decojewels/models/challan.dart';
import 'package:decojewels/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Each test uses unique DC numbers (DC1xx, DC2xx, etc.) to avoid collisions
  // with the static _recentlyRemovedDcs set that persists across tests.

  group('saveDraftChallan — same device, same party (THE BUG CASE)', () {
    test('Two challans for the same party should remain separate entries', () async {
      final challan1 = Challan(
        id: 100,
        challanNumber: 'SOMIK - DC100001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        transportName: 'ABC Transport',
        priceCategory: 'A',
        status: 'draft',
        items: [
          const ChallanItem(productId: 1, productName: 'Ring', sizeId: 10, quantity: 3, unitPrice: 100),
        ],
      );
      await LocalStorageService.saveDraftChallan(challan1);

      var drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 1, reason: 'Should have 1 draft after first save');
      expect(drafts[0].challanNumber, 'DC100001');
      expect(drafts[0].id, 100);

      // Save DC100002 for the SAME party SOMIK (id=101)
      final challan2 = Challan(
        id: 101,
        challanNumber: 'SOMIK - DC100002',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        transportName: 'ABC Transport',
        priceCategory: 'A',
        status: 'draft',
        items: [
          const ChallanItem(productId: 2, productName: 'Necklace', sizeId: 20, quantity: 5, unitPrice: 200),
          const ChallanItem(productId: 3, productName: 'Bracelet', sizeId: 30, quantity: 2, unitPrice: 150),
        ],
      );
      await LocalStorageService.saveDraftChallan(challan2);

      drafts = await LocalStorageService.getDraftChallans();
      // CRITICAL: Must be 2 separate drafts, NOT 1 overwritten draft
      expect(drafts.length, 2, reason: 'Both challans must exist as separate drafts');

      // Verify DC100001 is intact
      final dc1 = drafts.firstWhere((c) => c.challanNumber == 'DC100001');
      expect(dc1.id, 100, reason: 'DC100001 should keep its own server ID');
      expect(dc1.partyName, 'SOMIK');
      expect(dc1.items.length, 1, reason: 'DC100001 items should not be overwritten');
      expect(dc1.items[0].productName, 'Ring');

      // Verify DC100002 is intact
      final dc2 = drafts.firstWhere((c) => c.challanNumber == 'DC100002');
      expect(dc2.id, 101, reason: 'DC100002 should have its own server ID');
      expect(dc2.partyName, 'SOMIK');
      expect(dc2.items.length, 2, reason: 'DC100002 should have its own items');
    });

    test('Ending one challan should NOT affect the other for same party', () async {
      final challan1 = Challan(
        id: 200,
        challanNumber: 'DC200001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        transportName: 'ABC Transport',
        status: 'draft',
        items: [
          const ChallanItem(productId: 1, productName: 'Ring', sizeId: 10, quantity: 3, unitPrice: 100),
        ],
      );
      final challan2 = Challan(
        id: 201,
        challanNumber: 'DC200002',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        transportName: 'ABC Transport',
        status: 'draft',
        items: [
          const ChallanItem(productId: 2, productName: 'Necklace', sizeId: 20, quantity: 5, unitPrice: 200),
        ],
      );
      await LocalStorageService.saveDraftChallan(challan1);
      await LocalStorageService.saveDraftChallan(challan2);

      var drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 2);

      // Simulate "End Challan" for DC200002 — remove it from drafts
      await LocalStorageService.removeDraftChallanAfterEnd(
        endedChallanId: 201,
        serverChallanNumber: 'DC200002',
        localChallanNumber: 'DC200002',
        partyName: 'SOMIK',
      );

      drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 1, reason: 'Only DC200001 should remain');
      expect(drafts[0].challanNumber, 'DC200001');
      expect(drafts[0].id, 200, reason: 'DC200001 should still have correct ID');
      expect(drafts[0].items.length, 1, reason: 'DC200001 items should be untouched');
    });
  });

  group('saveDraftChallan — same device, different party', () {
    test('Different parties should always create separate entries', () async {
      final challan1 = Challan(
        id: 300,
        challanNumber: 'DC300001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        transportName: 'ABC Transport',
        status: 'draft',
        items: [const ChallanItem(productId: 1, productName: 'Ring', quantity: 3, unitPrice: 100)],
      );
      final challan2 = Challan(
        id: 301,
        challanNumber: 'DC300002',
        partyName: 'RAMAN',
        stationName: 'Delhi',
        transportName: 'XYZ Transport',
        status: 'draft',
        items: [const ChallanItem(productId: 2, productName: 'Necklace', quantity: 5, unitPrice: 200)],
      );

      await LocalStorageService.saveDraftChallan(challan1);
      await LocalStorageService.saveDraftChallan(challan2);

      final drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 2);
      expect(drafts.any((c) => c.challanNumber == 'DC300001' && c.id == 300), true);
      expect(drafts.any((c) => c.challanNumber == 'DC300002' && c.id == 301), true);
    });
  });

  group('saveDraftChallan — updating the SAME challan', () {
    test('Saving the same DC number should update in place (not duplicate)', () async {
      final challan = Challan(
        id: 400,
        challanNumber: 'DC400001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        transportName: 'ABC Transport',
        status: 'draft',
        items: [const ChallanItem(productId: 1, productName: 'Ring', quantity: 3, unitPrice: 100)],
      );
      await LocalStorageService.saveDraftChallan(challan);

      // Update same challan with more items
      final updated = Challan(
        id: 400,
        challanNumber: 'DC400001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        transportName: 'ABC Transport',
        status: 'draft',
        items: [
          const ChallanItem(productId: 1, productName: 'Ring', quantity: 3, unitPrice: 100),
          const ChallanItem(productId: 2, productName: 'Necklace', quantity: 5, unitPrice: 200),
        ],
      );
      await LocalStorageService.saveDraftChallan(updated);

      final drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 1, reason: 'Same DC should update, not create a duplicate');
      expect(drafts[0].items.length, 2, reason: 'Items should be updated');
      expect(drafts[0].id, 400);
    });

    test('Saving with party-prefixed DC should match DC-only in storage', () async {
      final challan = Challan(
        id: 410,
        challanNumber: 'DC410001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        transportName: 'ABC Transport',
        status: 'draft',
        items: [const ChallanItem(productId: 1, productName: 'Ring', quantity: 3, unitPrice: 100)],
      );
      await LocalStorageService.saveDraftChallan(challan);

      // Same challan but with party prefix format
      final updated = Challan(
        id: 410,
        challanNumber: 'SOMIK - DC410001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        transportName: 'ABC Transport',
        status: 'draft',
        items: [
          const ChallanItem(productId: 1, productName: 'Ring', quantity: 5, unitPrice: 100),
        ],
      );
      await LocalStorageService.saveDraftChallan(updated);

      final drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 1, reason: 'Same DC should update, not duplicate');
      expect(drafts[0].items[0].quantity, 5, reason: 'Quantity should be updated');
    });
  });

  group('saveDraftChallan — ID priority (incoming vs existing)', () {
    test('Incoming ID should take priority over existing null ID', () async {
      final noId = Challan(
        id: null,
        challanNumber: 'DC500001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        status: 'draft',
        items: [],
      );
      await LocalStorageService.saveDraftChallan(noId);

      var drafts = await LocalStorageService.getDraftChallans();
      expect(drafts[0].id, null);

      // Second save WITH ID
      final withId = Challan(
        id: 500,
        challanNumber: 'DC500001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        status: 'draft',
        items: [const ChallanItem(productId: 1, productName: 'Ring', quantity: 3, unitPrice: 100)],
      );
      await LocalStorageService.saveDraftChallan(withId);

      drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 1);
      expect(drafts[0].id, 500, reason: 'Incoming non-null ID should be used');
    });

    test('Existing ID preserved when incoming ID is null', () async {
      final withId = Challan(
        id: 510,
        challanNumber: 'DC510001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        status: 'draft',
        items: [const ChallanItem(productId: 1, productName: 'Ring', quantity: 3, unitPrice: 100)],
      );
      await LocalStorageService.saveDraftChallan(withId);

      // Second save WITHOUT ID (like _handleNext does)
      final noId = Challan(
        id: null,
        challanNumber: 'DC510001',
        partyName: 'SOMIK',
        stationName: 'Mumbai',
        status: 'draft',
        items: [const ChallanItem(productId: 1, productName: 'Ring', quantity: 5, unitPrice: 100)],
      );
      await LocalStorageService.saveDraftChallan(noId);

      final drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 1);
      expect(drafts[0].id, 510, reason: 'Existing ID should be preserved when incoming is null');
      expect(drafts[0].items[0].quantity, 5, reason: 'Items should still be updated');
    });
  });

  group('saveDraftChallan — three challans same party stress test', () {
    test('Three challans for SOMIK should all be separate', () async {
      for (int i = 1; i <= 3; i++) {
        final challan = Challan(
          id: 600 + i,
          challanNumber: 'DC60000$i',
          partyName: 'SOMIK',
          stationName: 'Mumbai',
          transportName: 'ABC Transport',
          status: 'draft',
          items: [ChallanItem(productId: i, productName: 'Product $i', quantity: i.toDouble(), unitPrice: 100)],
        );
        await LocalStorageService.saveDraftChallan(challan);
      }

      final drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 3, reason: 'All 3 challans must exist separately');

      for (int i = 1; i <= 3; i++) {
        final d = drafts.firstWhere((c) => c.challanNumber == 'DC60000$i');
        expect(d.id, 600 + i, reason: 'DC60000$i should have correct server ID');
        expect(d.items.length, 1);
        expect(d.items[0].quantity, i.toDouble());
      }
    });
  });

  group('removeDraftChallanAfterEnd — precision removal', () {
    test('Removing one challan should not touch others even for same party', () async {
      for (int i = 1; i <= 3; i++) {
        await LocalStorageService.saveDraftChallan(Challan(
          id: 700 + i,
          challanNumber: 'DC70000$i',
          partyName: 'SOMIK',
          stationName: 'Mumbai',
          transportName: 'ABC Transport',
          status: 'draft',
          items: [ChallanItem(productId: i, productName: 'P$i', quantity: i.toDouble(), unitPrice: 100)],
        ));
      }

      var drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 3);

      // End DC700002
      await LocalStorageService.removeDraftChallanAfterEnd(
        endedChallanId: 702,
        serverChallanNumber: 'DC700002',
        localChallanNumber: 'DC700002',
        partyName: 'SOMIK',
      );

      drafts = await LocalStorageService.getDraftChallans();
      expect(drafts.length, 2, reason: 'Only DC700002 should be removed');
      expect(drafts.any((c) => c.challanNumber == 'DC700001' && c.id == 701), true);
      expect(drafts.any((c) => c.challanNumber == 'DC700003' && c.id == 703), true);
      expect(drafts.any((c) => c.challanNumber == 'DC700002'), false);
    });
  });

  group('extractDcPart', () {
    test('Extracts DC from various formats', () {
      expect(LocalStorageService.extractDcPart('DC000001'), 'DC000001');
      expect(LocalStorageService.extractDcPart('SOMIK - DC000001'), 'DC000001');
      expect(LocalStorageService.extractDcPart('DC-000001'), 'DC000001');
      expect(LocalStorageService.extractDcPart('SOMIK - DC-009504'), 'DC009504');
      expect(LocalStorageService.extractDcPart(''), null);
      expect(LocalStorageService.extractDcPart('NO-NUMBER'), null);
    });
  });
}
