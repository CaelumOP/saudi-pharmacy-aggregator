import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pharmacy_app/adapters/al_dawaa_adapter.dart';
import 'package:pharmacy_app/adapters/al_nahdi_adapter.dart';
import 'package:pharmacy_app/adapters/united_pharmacy_adapter.dart';
import 'package:pharmacy_app/adapters/whites_adapter.dart';
import 'package:pharmacy_app/main.dart';
import 'package:pharmacy_app/services/pharmacy_aggregator_orchestrator.dart';
import 'package:pharmacy_app/services/watchlist_repository.dart';
import 'package:pharmacy_app/ui/widgets/canonical_product_hero.dart';
import 'package:pharmacy_app/ui/widgets/price_ladder_row.dart';
import 'package:pharmacy_app/ui/widgets/store_offer_detail_sheet.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late WatchlistRepository watchlistRepo;
  late PharmacyAggregatorOrchestrator orchestrator;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('widget_test_hive_');
    Hive.init(tempDir.path);
    watchlistRepo = WatchlistRepository();
    await watchlistRepo.init(boxName: 'widget_test_box');

    // Create mock adapters backed by recorded fixtures
    final nahdiDio = createMockDio(MockHttpAdapter.fromFixture('al_nahdi_panadol.json'));
    final unitedDio = createMockDio(MockHttpAdapter.fromFixture('united_pharmacy_panadol.json'));
    final whitesDio = createMockDio(MockHttpAdapter.fromFixture('whites_panadol.json'));
    final dawaaDio = createMockDio(MockHttpAdapter.fromFixture('al_dawaa_panadol.json'));

    orchestrator = PharmacyAggregatorOrchestrator(
      adapters: [
        AlNahdiAdapter(dio: nahdiDio),
        UnitedPharmacyAdapter(dio: unitedDio),
        WhitesAdapter(dio: whitesDio),
        AlDawaaAdapter(dio: dawaaDio),
      ],
    );
  });

  tearDown(() async {
    await watchlistRepo.close();
    await Hive.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  testWidgets('renders main comparison screen, executes search, and displays Canonical Hero & Price Ladder',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(PharmacyApp(
      orchestrator: orchestrator,
      watchlistRepository: watchlistRepo,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Title and search components
    expect(find.text('Saudi Pharmacy Deals'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);

    // Verify demo search chips are removed
    expect(find.text('Panadol Extra (Barcode)'), findsNothing);
    expect(find.text('Cetaphil 473ml (Barcode)'), findsNothing);

    // Enter query 'Panadol' and trigger search inside runAsync for real disk I/O handling
    await tester.enterText(find.byType(TextField), 'Panadol');
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await Future.delayed(const Duration(milliseconds: 1400));
    });

    // Wait for streaming lane updates using explicit pump frames
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 1. Verify Canonical Product Hero Card is rendered
    expect(find.byType(CanonicalProductHero), findsOneWidget);
    expect(find.text('LOWEST PRICE'), findsOneWidget);

    // 2. Verify Filter Chips are rendered
    expect(find.textContaining('All Stores'), findsOneWidget);
    expect(find.text('🏥 Walk-In Branches'), findsOneWidget);
    expect(find.text('🌐 Online & K-Beauty'), findsOneWidget);
    expect(find.text('🏷️ Promos Only'), findsOneWidget);

    // 3. Verify Sort Segmented Control is rendered
    expect(find.text('Lowest Price'), findsOneWidget);
    expect(find.text('Unit Value'), findsOneWidget);
    expect(find.text('Bulk Deal'), findsOneWidget);

    // 4. Verify Price Ladder Rows are rendered
    expect(find.byType(PriceLadderRow), findsWidgets);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('Al-Nahdi'), findsWidgets);
    expect(find.text('United Pharmacy'), findsWidgets);
    expect(find.text('Whites'), findsWidgets);
    expect(find.text('Al-Dawaa'), findsWidgets);

    // Verify Pricing is displayed (5.80 SAR as lowest price)
    expect(find.textContaining('5.80 SAR'), findsWidgets);

    // 5. Tap the #1 PriceLadderRow to open StoreOfferDetailSheet
    await tester.tap(find.byType(PriceLadderRow).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(StoreOfferDetailSheet), findsOneWidget);
    expect(find.text('Single Unit Cash Price'), findsOneWidget);

    // Close the detail sheet
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 6. Open Watchlist Drawer using bounded pump
    await tester.tap(find.byIcon(Icons.bookmarks_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Watchlist & Scans'), findsOneWidget);
    expect(find.text('RECENT SCANS'), findsOneWidget);
  });
}
