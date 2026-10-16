import '../services/app_settings_repository.dart';

/// Centralized localization dictionary for Saudi Pharmacy Price Aggregator.
///
/// Provides instant, non-breaking strings for both English (`en`) and natural Saudi Arabic (`ar`).
class AppStrings {
  final AppLanguage language;

  /// Creates an [AppStrings] instance for the given [language].
  const AppStrings(this.language);

  /// True if currently set to Arabic.
  bool get isArabic => language == AppLanguage.ar;

  // App Bar & Branding
  String get appTitle => isArabic ? 'عروض الصيدليات والعناية' : 'Saudi Pharmacy Deals';
  String get searchHint => isArabic ? 'ابحث عن دواء أو منتج أو امسح الباركود...' : 'Search medication or scan barcode...';
  String get clearSearchTooltip => isArabic ? 'مسح البحث' : 'Clear search';
  String get scanBarcodeTooltip => isArabic ? 'مسح الباركود' : 'Scan barcode';
  String get watchlistTooltip => isArabic ? 'قائمة المتابعة' : 'Watchlist';
  String get settingsTooltip => isArabic ? 'الإعدادات' : 'Settings';

  // Filter Chips
  String get filterAll => isArabic ? 'كل المتاجر' : 'All Stores';
  String get filterWalkIn => isArabic ? '🏥 فروع + أونلاين' : '🏥 Walk-In Branches';
  String get filterOnline => isArabic ? '🌐 أونلاين وكورية' : '🌐 Online & K-Beauty';
  String get filterPromos => isArabic ? '🏷️ العروض فقط' : '🏷️ Promos Only';

  // 1-Tap Sort Control
  String get sortLowestPrice => isArabic ? 'الأقل سعراً' : 'Lowest Price';
  String get sortUnitValue => isArabic ? 'سعر الوحدة' : 'Unit Value';
  String get sortBulkDeal => isArabic ? 'عرض الكميات' : 'Bulk Deal';

  // Status & Counts
  String comparingStores(int total, int completed) =>
      isArabic ? 'جاري مقارنة $total متاجر... اكتمل $completed' : 'Comparing $total stores... $completed completed';
  String verificationRequired(String storeName) =>
      isArabic ? 'يتطلب متجر $storeName تحقق بنقرة واحدة [تحقق]' : '$storeName requires 1-tap verification [Verify]';
  String noMatchesFoundStores(int count) =>
      isArabic ? '$count متاجر لم تجد نتائج مطابقة' : '$count stores had no matches';
  String get expand => isArabic ? 'عرض' : 'Expand';
  String get collapse => isArabic ? 'إخفاء' : 'Collapse';
  String get inStock => isArabic ? 'متوفر' : 'In Stock';
  String get outOfStock => isArabic ? 'غير متوفر' : 'Out of Stock';
  String get walkInPresence => isArabic ? 'فروع' : 'Walk-In';
  String get onlinePresence => isArabic ? 'أونلاين' : 'Online';

  // Canonical Product Hero
  String get canonicalHeroTitle => isArabic ? 'المنتج المرجعي' : 'Canonical Product';
  String get lowestSinglePriceWinner => isArabic ? 'أقل سعر مفرد' : 'Lowest Price';
  String get bestUnitValueWinner => isArabic ? 'أفضل قيمة للوحدة' : 'Best Unit Value';
  String get bestBulkDealWinner => isArabic ? 'أفضل عرض كميات' : 'Best Bulk Deal';
  String get barcodeLabel => isArabic ? 'باركود' : 'Barcode';
  String get pinnedToWatchlist => isArabic ? 'تمت الإضافة للمفضلة' : 'Pinned to Watchlist';
  String get addToWatchlist => isArabic ? 'إضافة للمفضلة' : 'Add to Watchlist';

  // Price & Units
  String get currency => isArabic ? 'ر.س' : 'SAR';
  String pricePerBaseUnit(String unit) {
    if (!isArabic) return ' / $unit';
    switch (unit) {
      case '100ml':
        return ' / ١٠٠ مل';
      case '100g':
        return ' / ١٠٠ جم';
      case '100 tabs':
      case '10 tabs':
        return ' / ١٠٠ حبة';
      default:
        return ' / $unit';
    }
  }

  // Offer Detail Bottom Sheet
  String get offerDetailsTitle => isArabic ? 'تفاصيل العرض' : 'Offer Details';
  String get singleUnitPriceLabel => isArabic ? 'سعر القطعة المفردة' : 'Single Unit Cash Price';
  String get baseUnitPriceLabel => isArabic ? 'سعر الوحدة المعيارية' : 'Standard Base Value';
  String get vatStatusLabel => isArabic ? 'حالة الضريبة' : 'VAT / Tax Status';
  String get vat15Inclusive => isArabic ? 'شامل ضريبة القيمة المضافة 15%' : '15% VAT Included';
  String get vat0SfdaRegulated => isArabic ? 'دواء مسجل معفى من الضريبة (0% SFDA)' : '0% VAT SFDA Regulated Drug';
  String get matchConfidenceLabel => isArabic ? 'دقة المطابقة' : 'Match Confidence';
  String get exactBarcodeMatch => isArabic ? 'مطابقة باركود دقيقة (GTIN)' : 'Exact GTIN Barcode Match';
  String smartTitleMatch(double score) =>
      isArabic ? 'مطابقة ذكية بالاسم (${(score * 100).toStringAsFixed(0)}%)' : 'Smart Title Match (${(score * 100).toStringAsFixed(0)}%)';
  String get activePromosLabel => isArabic ? 'العروض الترويجية النشطة' : 'Active Promotions';
  String get noActivePromos => isArabic ? 'لا توجد عروض كميات إضافية لهذا المنتج' : 'No active multi-buy promotions for this item';
  String get skuLabel => isArabic ? 'رمز المنتج (SKU)' : 'SKU / Item ID';
  String get openInStoreButton => isArabic ? 'فتح صفحة المنتج في المتجر' : 'Open in Official Store';

  // Settings Bottom Sheet
  String get settingsTitle => isArabic ? 'الإعدادات' : 'Settings';
  String get languageSectionTitle => isArabic ? 'اللغة' : 'Language';
  String get englishLanguage => 'English';
  String get arabicLanguage => 'العربية';
  String get activeStoresSectionTitle => isArabic ? 'المتاجر المفعلة' : 'Active Stores';
  String get storesSubtitle => isArabic
      ? 'المتاجر غير المفعلة يتم إخفاؤها من مقارنة الأسعار، ولكنها تظل مفعلة تلقائياً في الخلفية للتعرف على الباركود الممسوح.'
      : 'Disabled stores are hidden from price results, but still help identify scanned barcodes in the background.';
  String get selectAllStores => isArabic ? 'تحديد الكل' : 'Select All';
  String get selectWalkInOnly => isArabic ? 'الصيدليات المحلية فقط' : 'Walk-In Pharmacies Only';
  String get selectOnlineOnly => isArabic ? 'المتاجر الإلكترونية فقط' : 'Online & K-Beauty Only';
  String get walkInGroupHeader => isArabic ? 'الصيدليات وفروعها المحلية' : 'Walk-In Pharmacy Chains';
  String get onlineGroupHeader => isArabic ? 'المتاجر الإلكترونية والعناية الكورية' : 'Online & Specialty Stores';
  String get atLeastOneStoreError => isArabic ? 'يجب إبقاء متجر واحد على الأقل مفعلاً' : 'At least one store must remain enabled';

  // Localized Store Names
  String storeName(String storeId, {String? defaultName}) {
    if (!isArabic) {
      switch (storeId) {
        case 'al_nahdi':
          return 'Al-Nahdi';
        case 'united_pharmacy':
          return 'United Pharmacy';
        case 'whites':
          return 'Whites';
        case 'al_dawaa':
          return 'Al-Dawaa';
        case 'boots':
          return 'Boots';
        case 'lemon':
          return 'Lemon Pharmacy';
        case 'nice_one':
          return 'Nice One';
        case 'golden_scent':
          return 'Golden Scent';
        case 'seoulhouse':
          return 'Seoul House';
        default:
          return defaultName ?? storeId;
      }
    } else {
      switch (storeId) {
        case 'al_nahdi':
          return 'النهدي';
        case 'united_pharmacy':
          return 'المتحدة';
        case 'whites':
          return 'وايتس';
        case 'al_dawaa':
          return 'الدواء';
        case 'boots':
          return 'بوتس';
        case 'lemon':
          return 'صيدلية ليمون';
        case 'nice_one':
          return 'نايس ون';
        case 'golden_scent':
          return 'قولدن سنت';
        case 'seoulhouse':
          return 'سيول هاوس';
        default:
          return defaultName ?? storeId;
      }
    }
  }

  // Autocomplete & Smart Query Corrections
  String showingResultsFor(String query) =>
      isArabic ? 'عرض النتائج لـ "$query"' : 'Showing results for "$query"';
  String searchInsteadFor(String query) =>
      isArabic ? 'البحث عن "$query" بدلاً من ذلك' : 'Search "$query" instead';
  String didYouMean(String query) =>
      isArabic ? 'هل تقصد: $query' : 'Did you mean: $query';
}
