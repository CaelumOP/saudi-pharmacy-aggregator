import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/utils/title_sanitizer.dart';

void main() {
  group('TitleSanitizer - Clean Promotional Noise', () {
    test('strips (1+1 Free) while retaining brand and volume', () {
      final input = 'Panadol Extra Tablet 24 pcs (1+1 Free)';
      final result = TitleSanitizer.clean(input);
      expect(result, equals('Panadol Extra Tablet 24 pcs'));
    });

    test('strips Twin Pack and bundle markers while retaining weight', () {
      final input = 'Cetaphil Moisturizing Cream 566gm - Twin Pack';
      final result = TitleSanitizer.clean(input);
      expect(result, equals('Cetaphil Moisturizing Cream 566gm'));
    });

    test('strips brackets with Special Offer and Save percentage', () {
      final input = 'Bioderma Sensibio H2O 500ml [Special Offer - Save 20%]';
      final result = TitleSanitizer.clean(input);
      expect(result, equals('Bioderma Sensibio H2O 500ml'));
    });

    test('strips Arabic promotional phrases (عرض خاص, خصم, مجانا)', () {
      final input = 'كريم سيتافيل المرطب 453 جرام (عرض خاص خصم 20% مجانا)';
      final result = TitleSanitizer.clean(input);
      expect(result, equals('كريم سيتافيل المرطب 453 جرام'));
    });

    test('preserves core medical dosage and tablet counts intact', () {
      final input = 'Panadol Advance Paracetamol 500 mg - 24 Tablets';
      final result = TitleSanitizer.clean(input);
      expect(result, equals('Panadol Advance Paracetamol 500 mg 24 Tablets'));
    });
  });

  group('TitleSanitizer - Unit Info Extraction', () {
    test('extracts liquid volume in ml', () {
      final info = TitleSanitizer.extractUnitInfo('Cetaphil Gentle Skin Cleanser 473 ml');
      expect(info.quantity, equals(473.0));
      expect(info.metric, equals('ml'));
    });

    test('converts liters to ml', () {
      final info = TitleSanitizer.extractUnitInfo('Saline Solution 1.5 L');
      expect(info.quantity, equals(1500.0));
      expect(info.metric, equals('ml'));
    });

    test('extracts weight in grams (g / gm)', () {
      final info1 = TitleSanitizer.extractUnitInfo('Cetaphil Moisturizing Cream 453 G');
      expect(info1.quantity, equals(453.0));
      expect(info1.metric, equals('g'));

      final info2 = TitleSanitizer.extractUnitInfo('Cetaphil Moisturizing Cream 566gm');
      expect(info2.quantity, equals(566.0));
      expect(info2.metric, equals('g'));
    });

    test('converts kilograms to grams', () {
      final info = TitleSanitizer.extractUnitInfo('Baby Bath Salt 1 kg');
      expect(info.quantity, equals(1000.0));
      expect(info.metric, equals('g'));
    });

    test('extracts tablet, caplet, and piece counts', () {
      final infoTabs = TitleSanitizer.extractUnitInfo('Panadol Extra 24 Tablets');
      expect(infoTabs.quantity, equals(24.0));
      expect(infoTabs.metric, equals('tabs'));

      final infoCaps = TitleSanitizer.extractUnitInfo('Panadol Sinus 24 Caplets');
      expect(infoCaps.quantity, equals(24.0));
      expect(infoCaps.metric, equals('tabs'));

      final infoPcs = TitleSanitizer.extractUnitInfo('Panadol Extra 24 pcs');
      expect(infoPcs.quantity, equals(24.0));
      expect(infoPcs.metric, equals('tabs'));
    });

    test('ignores nutrient designations so Omega 3 Capsules does not parse as 3 tabs', () {
      final info = TitleSanitizer.extractUnitInfo('VitabioticsAquamarine 60% Omega 3 Capsules');
      expect(info.quantity, isNull);
      expect(info.metric, isNull);
    });

    test('extracts softgel count while ignoring Omega-3 and dosage mg', () {
      final info = TitleSanitizer.extractUnitInfo('Now Foods Omega-3 1000 mg 90 Softgels');
      expect(info.quantity, equals(90.0));
      expect(info.metric, equals('tabs'));
    });

    test('extracts Arabic volume and weight units (مل, غ, جم)', () {
      final infoLiquid = TitleSanitizer.extractUnitInfo('مستخلص الحلزون 100مل');
      expect(infoLiquid.quantity, equals(100.0));
      expect(infoLiquid.metric, equals('ml'));

      final infoWeight1 = TitleSanitizer.extractUnitInfo('كريم الحلزون 100غ');
      expect(infoWeight1.quantity, equals(100.0));
      expect(infoWeight1.metric, equals('g'));

      final infoWeight2 = TitleSanitizer.extractUnitInfo('دخون معمول نجد - 100جم');
      expect(infoWeight2.quantity, equals(100.0));
      expect(infoWeight2.metric, equals('g'));
    });

    test('extracts Arabic oral counts (قرص, كبسولة)', () {
      final infoTabs = TitleSanitizer.extractUnitInfo('بنادول اكسترا 24 قرص');
      expect(infoTabs.quantity, equals(24.0));
      expect(infoTabs.metric, equals('tabs'));

      final infoCaps = TitleSanitizer.extractUnitInfo('اوميجا 3 بارادوكس 30 كبسولة');
      expect(infoCaps.quantity, equals(30.0));
      expect(infoCaps.metric, equals('tabs'));
    });

    test('returns null for items without explicit metrics', () {
      final info = TitleSanitizer.extractUnitInfo('Digital Blood Pressure Monitor');
      expect(info.quantity, isNull);
      expect(info.metric, isNull);
    });
  });

  group('TitleSanitizer - Price Per Base Unit Calculation', () {
    test('calculates SAR per 100ml for liquids', () {
      // 473 ml at 104.65 SAR -> (104.65 / 473) * 100 = 22.12
      final basePrice = TitleSanitizer.calculatePricePerBaseUnit(
        price: 104.65,
        quantity: 473.0,
        metric: 'ml',
      );
      expect(basePrice, equals(22.12));
    });

    test('calculates SAR per 100g for creams', () {
      // 453 g at 141.45 SAR -> (141.45 / 453) * 100 = 31.23
      final basePrice = TitleSanitizer.calculatePricePerBaseUnit(
        price: 141.45,
        quantity: 453.0,
        metric: 'g',
      );
      expect(basePrice, equals(31.23));
    });

    test('calculates SAR per 10 tablets for oral medications', () {
      // 24 tablets at 8.00 SAR -> (8.00 / 24) * 10 = 3.33
      final basePrice = TitleSanitizer.calculatePricePerBaseUnit(
        price: 8.00,
        quantity: 24.0,
        metric: 'tabs',
      );
      expect(basePrice, equals(3.33));
    });

    test('returns null when quantity is null or zero', () {
      expect(
        TitleSanitizer.calculatePricePerBaseUnit(price: 10.0, quantity: null, metric: 'ml'),
        isNull,
      );
      expect(
        TitleSanitizer.calculatePricePerBaseUnit(price: 10.0, quantity: 0, metric: 'ml'),
        isNull,
      );
    });
  });
}
