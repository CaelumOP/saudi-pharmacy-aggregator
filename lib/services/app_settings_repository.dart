import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Supported application interface languages.
enum AppLanguage {
  /// English (Left-to-Right).
  en,

  /// Arabic (Right-to-Left).
  ar,
}

/// Immutable state containing user preferences for language and enabled comparison stores.
class AppSettingsState {
  /// Currently active UI language.
  final AppLanguage language;

  /// Set of store IDs enabled by the user for active price comparison.
  final Set<String> enabledStoreIds;

  /// Creates an [AppSettingsState] instance.
  const AppSettingsState({
    this.language = AppLanguage.en,
    required this.enabledStoreIds,
  });

  /// True if [storeId] is enabled for price comparison display.
  bool isStoreEnabled(String storeId) => enabledStoreIds.contains(storeId);

  /// Returns true if currently set to Arabic.
  bool get isArabic => language == AppLanguage.ar;

  /// Creates a copy with optionally updated fields.
  AppSettingsState copyWith({
    AppLanguage? language,
    Set<String>? enabledStoreIds,
  }) {
    return AppSettingsState(
      language: language ?? this.language,
      enabledStoreIds: enabledStoreIds != null ? Set.from(enabledStoreIds) : this.enabledStoreIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsState &&
          runtimeType == other.runtimeType &&
          language == other.language &&
          setEquals(enabledStoreIds, other.enabledStoreIds);

  @override
  int get hashCode => language.hashCode ^ enabledStoreIds.hashCode;
}

/// All 9 registered store IDs in the aggregator system.
const Set<String> kAllStoreIds = {
  'al_nahdi',
  'united_pharmacy',
  'whites',
  'al_dawaa',
  'boots',
  'lemon',
  'nice_one',
  'golden_scent',
  'seoulhouse',
};

/// Physical retail pharmacies with walk-in branch networks.
const Set<String> kWalkInStoreIds = {
  'al_nahdi',
  'united_pharmacy',
  'whites',
  'al_dawaa',
  'boots',
  'lemon',
};

/// Online-only beauty, skincare, and e-commerce platforms.
const Set<String> kOnlineStoreIds = {
  'nice_one',
  'golden_scent',
  'seoulhouse',
};

/// Repository managing user preferences (Language and Active Store Toggles).
///
/// Backed by Hive with an immediate in-memory fallback so tests and startup never block.
/// Exposes [stateNotifier] for reactive UI updates across the entire application.
class AppSettingsRepository {
  static const String defaultBoxName = 'pharmacy_settings_box';
  static const String _keyLanguage = 'app_language';
  static const String _keyEnabledStores = 'enabled_stores';

  Box<dynamic>? _box;
  Map<String, dynamic>? _inMemoryStore;

  late final ValueNotifier<AppSettingsState> stateNotifier;

  /// Shared singleton instance for convenient access across widgets and orchestrator.
  static final AppSettingsRepository instance = AppSettingsRepository();

  /// Creates an [AppSettingsRepository] with optional pre-opened [Box].
  AppSettingsRepository({Box<dynamic>? box}) {
    _box = box;
    _inMemoryStore = <String, dynamic>{};
    stateNotifier = ValueNotifier<AppSettingsState>(
      const AppSettingsState(
        language: AppLanguage.en,
        enabledStoreIds: kAllStoreIds,
      ),
    );
    _loadInitialState();
  }

  /// Initializes Hive storage and opens the settings box.
  Future<void> init({String boxName = defaultBoxName}) async {
    try {
      _box = await Hive.openBox<dynamic>(boxName);
      _loadInitialState();
    } catch (_) {
      initInMemory();
    }
  }

  /// Initializes in-memory fallback when disk storage is unavailable.
  void initInMemory() {
    _inMemoryStore ??= <String, dynamic>{};
    _loadInitialState();
  }

  /// Initializes repository with pre-filled storage values (useful for migration and testing).
  void initFromMap(Map<String, dynamic> initialMap) {
    _inMemoryStore = Map<String, dynamic>.from(initialMap);
    _loadInitialState();
  }

  /// Current settings state snapshot.
  AppSettingsState get state => stateNotifier.value;

  /// Adds a listener to be notified when settings change.
  void addListener(VoidCallback listener) => stateNotifier.addListener(listener);

  /// Removes a previously registered listener.
  void removeListener(VoidCallback listener) => stateNotifier.removeListener(listener);

  void _loadInitialState() {
    final langStr = _getValue(_keyLanguage)?.toString();
    final AppLanguage lang;
    if (langStr == 'ar') {
      lang = AppLanguage.ar;
    } else {
      lang = AppLanguage.en;
    }

    final rawStores = _getValue(_keyEnabledStores);
    final Set<String> stores = {};
    if (rawStores is List) {
      for (final s in rawStores) {
        final id = s.toString();
        // Purge obsolete/removed store IDs
        if (kAllStoreIds.contains(id)) {
          stores.add(id);
        }
      }
      // Automatically ensure Seoul House is enabled by default
      stores.add('seoulhouse');

      // Ensure at least one valid store exists
      if (stores.isEmpty) {
        stores.addAll(kAllStoreIds);
      }
      // Persist sanitized state to permanently clean up legacy Hive data
      _putValue(_keyEnabledStores, stores.toList());
    } else {
      stores.addAll(kAllStoreIds);
    }

    stateNotifier.value = AppSettingsState(
      language: lang,
      enabledStoreIds: stores,
    );
  }

  dynamic _getValue(String key) {
    if (_box != null && _box!.isOpen) {
      return _box!.get(key);
    }
    if (_inMemoryStore != null) {
      return _inMemoryStore![key];
    }
    return null;
  }

  Future<void> _putValue(String key, dynamic val) async {
    if (_box != null && _box!.isOpen) {
      await _box!.put(key, val);
      return;
    }
    if (_inMemoryStore != null) {
      _inMemoryStore![key] = val;
      return;
    }
  }

  /// Updates UI language (`en` or `ar`).
  Future<void> setLanguage(AppLanguage language) async {
    await _putValue(_keyLanguage, language.name);
    stateNotifier.value = state.copyWith(language: language);
  }

  /// Toggles a specific store on or off, preventing disabling the last remaining store.
  Future<bool> setStoreEnabled(String storeId, bool enabled) async {
    final current = Set<String>.from(state.enabledStoreIds);
    if (!enabled) {
      if (current.length <= 1 && current.contains(storeId)) {
        return false; // Prevent disabling the last store
      }
      current.remove(storeId);
    } else {
      current.add(storeId);
    }
    await _putValue(_keyEnabledStores, current.toList());
    stateNotifier.value = state.copyWith(enabledStoreIds: current);
    return true;
  }

  /// Overwrites enabled stores with [stores], ensuring at least one store is enabled.
  Future<void> setEnabledStores(Set<String> stores) async {
    final valid = stores.isEmpty ? Set<String>.from(kAllStoreIds) : Set<String>.from(stores);
    await _putValue(_keyEnabledStores, valid.toList());
    stateNotifier.value = state.copyWith(enabledStoreIds: valid);
  }

  /// Enables all 9 stores.
  Future<void> selectAllStores() async {
    await setEnabledStores(kAllStoreIds);
  }

  /// Enables only physical walk-in retail pharmacy chains.
  Future<void> selectWalkInOnly() async {
    await setEnabledStores(kWalkInStoreIds);
  }

  /// Enables only online beauty and specialty stores.
  Future<void> selectOnlineOnly() async {
    await setEnabledStores(kOnlineStoreIds);
  }
}
