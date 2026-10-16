import '../domain/models/pharmacy_offer.dart';

/// Exception thrown when a pharmacy endpoint responds with an anti-bot Cloudflare Turnstile challenge.
///
/// Triggers the interactive bottom-sheet bridge to obtain clearance cookies from the user.
class CloudflareChallengeException implements Exception {
  /// The store identifier that triggered the challenge (e.g. 'al_dawaa').
  final String storeId;

  /// The target URL that triggered the challenge.
  final String challengeUrl;

  /// Additional diagnostic details or raw HTTP headers.
  final String? message;

  /// Creates a [CloudflareChallengeException] with store identification.
  const CloudflareChallengeException({
    required this.storeId,
    required this.challengeUrl,
    this.message,
  });

  @override
  String toString() =>
      'CloudflareChallengeException(store: $storeId, url: $challengeUrl, message: $message)';
}

/// Store presence format indicating brick-and-mortar footprint vs digital-only operation.
enum StorePresenceType {
  /// Store operates both physical walk-in retail pharmacies and online delivery.
  physicalAndOnline,

  /// Store operates strictly as an e-commerce digital platform.
  onlineOnly,
}

/// Store catalog and merchandise specialty domain.
enum StoreSpecialty {
  /// Comprehensive pharmaceutical, prescription, OTC and personal care catalog.
  pharmacyAndCare,

  /// Korean beauty, dermocosmetics, and skincare specialty catalog.
  kBeautyAndSkincare,

  /// Dietary supplements, vitamins, and sports nutrition specialty catalog.
  supplements,
}

/// Abstract contract implemented by each pharmacy search adapter.
///
/// Enforces a unified lookup interface for GTIN barcode lookups and keyword queries,
/// isolating store-specific serialization, headers, and protocol logic.
abstract class PharmacyAdapter {
  /// Identifier used to identify the store lane (e.g., 'al_nahdi', 'united_pharmacy').
  String get storeId;

  /// Display name of the pharmacy.
  String get storeName;

  /// Base storefront or API hostname.
  String get baseUrl;

  /// Physical vs online-only store operating footprint.
  StorePresenceType get presenceType;

  /// Store merchandise specialty focus.
  StoreSpecialty get specialty;

  /// Default HTTP headers pinned to the English catalog (en-SA) for consistent parsing.
  Map<String, String> get defaultHeaders;

  /// Performs a Stage 1 barcode lookup using a 13-digit GTIN / EAN code.
  Future<List<PharmacyOffer>> searchByBarcode(String gtin);

  /// Performs a text search by product title or keyword with an optional maximum result count.
  Future<List<PharmacyOffer>> searchByKeyword(String query, {int limit = 5});
}
