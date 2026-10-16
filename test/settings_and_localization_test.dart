import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/l10n/app_strings.dart';
import 'package:pharmacy_app/services/app_settings_repository.dart';
import 'package:pharmacy_app/ui/widgets/settings_bottom_sheet.dart';
import 'package:pharmacy_app/utils/title_sanitizer.dart';

void main() {
  group('AppSettingsRepository Tests', () {
    late AppSettingsRepository repo;

    setUp(() {
      repo = AppSettingsRepository();
      repo.initInMemory();
    });

    test('initializes with default English language and all 9 stores enabled', () {
      expect(repo.state.language, equals(AppLanguage.en));
      expect(repo.state.isArabic, isFalse);
      expect(repo.state.enabledStoreIds.length, equals(9));
      expect(repo.state.enabledStoreIds, equals(kAllStoreIds));
    });

    test('toggles language and notifies listeners', () async {
      var notified = false;
      repo.addListener(() => notified = true);

      await repo.setLanguage(AppLanguage.ar);
      expect(notified, isTrue);
      expect(repo.state.language, equals(AppLanguage.ar));
      expect(repo.state.isArabic, isTrue);

      notified = false;
      await repo.setLanguage(AppLanguage.en);
      expect(notified, isTrue);
      expect(repo.state.language, equals(AppLanguage.en));
      expect(repo.state.isArabic, isFalse);
    });

    test('toggles individual store and preserves others', () async {
      final success = await repo.setStoreEnabled('seoulhouse', false);
      expect(success, isTrue);
      expect(repo.state.isStoreEnabled('seoulhouse'), isFalse);
      expect(repo.state.enabledStoreIds.length, equals(8));

      final reEnabled = await repo.setStoreEnabled('seoulhouse', true);
      expect(reEnabled, isTrue);
      expect(repo.state.isStoreEnabled('seoulhouse'), isTrue);
      expect(repo.state.enabledStoreIds.length, equals(9));
    });

    test('prevents disabling the last remaining store', () async {
      // Disable 8 stores
      for (final storeId in kAllStoreIds.skip(1)) {
        await repo.setStoreEnabled(storeId, false);
      }
      expect(repo.state.enabledStoreIds.length, equals(1));
      final lastStore = repo.state.enabledStoreIds.first;

      // Attempt to disable the last remaining store
      final result = await repo.setStoreEnabled(lastStore, false);
      expect(result, isFalse);
      expect(repo.state.enabledStoreIds.length, equals(1));
      expect(repo.state.isStoreEnabled(lastStore), isTrue);
    });

    test('quick presets selectWalkInOnly, selectOnlineOnly, and selectAllStores', () async {
      await repo.selectWalkInOnly();
      expect(repo.state.enabledStoreIds, equals(kWalkInStoreIds));
      expect(repo.state.enabledStoreIds.length, equals(6));

      await repo.selectOnlineOnly();
      expect(repo.state.enabledStoreIds, equals(kOnlineStoreIds));
      expect(repo.state.enabledStoreIds.length, equals(3));

      await repo.selectAllStores();
      expect(repo.state.enabledStoreIds, equals(kAllStoreIds));
      expect(repo.state.enabledStoreIds.length, equals(9));
    });

    test('purges legacy/removed store IDs and automatically enables seoulhouse on Hive load', () {
      final migrationRepo = AppSettingsRepository();
      migrationRepo.initFromMap({
        'enabled_stores': ['iherb', 'kstyleseoul', 'seoul_eun', 'kbeauty_kingdom', 'trendyol', 'al_nahdi'],
      });

      expect(migrationRepo.state.isStoreEnabled('al_nahdi'), isTrue);
      expect(migrationRepo.state.isStoreEnabled('seoulhouse'), isTrue);
      expect(migrationRepo.state.isStoreEnabled('iherb'), isFalse);
      expect(migrationRepo.state.isStoreEnabled('kstyleseoul'), isFalse);
      expect(migrationRepo.state.isStoreEnabled('seoul_eun'), isFalse);
      expect(migrationRepo.state.isStoreEnabled('kbeauty_kingdom'), isFalse);
      expect(migrationRepo.state.isStoreEnabled('trendyol'), isFalse);
      expect(migrationRepo.state.enabledStoreIds, equals({'al_nahdi', 'seoulhouse'}));
    });
  });

  group('TitleSanitizer.buildStage3SearchQuery Tests', () {
    test('strips volume, units, and filler words to create compact 3-4 word core query', () {
      final raw1 = 'Cetaphil Gentle Skin Cleanser 473 Ml for dry to normal skin';
      final stage3Query1 = TitleSanitizer.buildStage3SearchQuery(raw1);
      expect(stage3Query1, equals('Cetaphil Gentle Skin Cleanser'));

      final raw2 = 'Panadol Extra Tablets 500mg 24 Tabs';
      final stage3Query2 = TitleSanitizer.buildStage3SearchQuery(raw2);
      expect(stage3Query2, equals('Panadol Extra Tablets'));

      final raw3 = 'Now Foods Omega-3 1000 mg 100 Softgels';
      final stage3Query3 = TitleSanitizer.buildStage3SearchQuery(raw3);
      expect(stage3Query3, equals('Now Foods Omega 3'));
    });
  });

  group('AppStrings Localization Tests', () {
    test('provides accurate English and natural Saudi Arabic translations', () {
      final en = AppStrings(AppLanguage.en);
      final ar = AppStrings(AppLanguage.ar);

      expect(en.currency, equals('SAR'));
      expect(ar.currency, equals('ر.س'));

      expect(en.storeName('al_nahdi'), equals('Al-Nahdi'));
      expect(ar.storeName('al_nahdi'), equals('النهدي'));

      expect(en.storeName('whites'), equals('Whites'));
      expect(ar.storeName('whites'), equals('وايتس'));

      expect(en.storeName('lemon'), equals('Lemon Pharmacy'));
      expect(ar.storeName('lemon'), equals('صيدلية ليمون'));

      expect(en.storeName('seoulhouse'), equals('Seoul House'));
      expect(ar.storeName('seoulhouse'), equals('سيول هاوس'));

      expect(en.walkInPresence, equals('Walk-In'));
      expect(ar.walkInPresence, equals('فروع'));

      expect(en.onlinePresence, equals('Online'));
      expect(ar.onlinePresence, equals('أونلاين'));

      expect(en.pricePerBaseUnit('100ml'), equals(' / 100ml'));
      expect(ar.pricePerBaseUnit('100ml'), equals(' / ١٠٠ مل'));

      expect(en.pricePerBaseUnit('100 tabs'), equals(' / 100 tabs'));
      expect(ar.pricePerBaseUnit('100 tabs'), equals(' / ١٠٠ حبة'));
    });
  });

  group('SettingsBottomSheet Widget Tests', () {
    testWidgets('renders language segmented switch and store toggles', (tester) async {
      final repo = AppSettingsRepository();
      repo.initInMemory();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => SettingsBottomSheet.show(ctx, repository: repo),
                child: const Text('Open Settings'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      // Verify settings modal is displayed
      expect(find.byType(SettingsBottomSheet), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('Active Stores'), findsOneWidget);
      expect(find.text('9 / 9'), findsOneWidget);

      // Tap Arabic language option
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();

      expect(repo.state.language, equals(AppLanguage.ar));
      expect(find.text('اللغة'), findsOneWidget);
      expect(find.text('المتاجر المفعلة'), findsOneWidget);

      // Tap Walk-In Only preset chip
      await tester.tap(find.text('الصيدليات المحلية فقط'));
      await tester.pumpAndSettle();

      expect(repo.state.enabledStoreIds.length, equals(6));
      expect(find.text('6 / 9'), findsOneWidget);
    });
  });
}
