import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/app_settings_repository.dart';
import 'services/pharmacy_aggregator_orchestrator.dart';
import 'services/watchlist_repository.dart';
import 'ui/screens/home_comparison_screen.dart';

/// Entrypoint launching the application frame immediately without blocking on disk I/O.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Run the app immediately so the native platform window renders its first frame without delay
  runApp(const PharmacyApp());
}

/// Root application widget configuring Material 3 theme, localization, and comparison deck.
class PharmacyApp extends StatefulWidget {
  /// Aggregator orchestrator managing cross-pharmacy search streams.
  final PharmacyAggregatorOrchestrator? orchestrator;

  /// Watchlist and history repository.
  final WatchlistRepository? watchlistRepository;

  /// User settings and preferences repository.
  final AppSettingsRepository? settingsRepository;

  /// Creates the [PharmacyApp].
  const PharmacyApp({
    super.key,
    this.orchestrator,
    this.watchlistRepository,
    this.settingsRepository,
  });

  @override
  State<PharmacyApp> createState() => _PharmacyAppState();
}

class _PharmacyAppState extends State<PharmacyApp> {
  late final PharmacyAggregatorOrchestrator _orchestrator;
  late final WatchlistRepository _watchlistRepo;
  late final AppSettingsRepository _settingsRepo;

  @override
  void initState() {
    super.initState();
    _settingsRepo = widget.settingsRepository ?? AppSettingsRepository.instance;
    _orchestrator = widget.orchestrator ?? PharmacyAggregatorOrchestrator();
    _watchlistRepo = widget.watchlistRepository ?? WatchlistRepository();

    // Sync enabled stores to orchestrator
    _orchestrator.enabledStoreIds = _settingsRepo.state.enabledStoreIds;
    _settingsRepo.stateNotifier.addListener(_onSettingsChanged);

    // Only perform async Hive setup when using default persistence to prevent file lock hangs
    if (widget.watchlistRepository == null && widget.settingsRepository == null) {
      _initHiveAsync();
    }
  }

  void _onSettingsChanged() {
    _orchestrator.enabledStoreIds = _settingsRepo.state.enabledStoreIds;
  }

  @override
  void dispose() {
    _settingsRepo.stateNotifier.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// Initializes Hive storage asynchronously with a 3-second timeout and in-memory fallback.
  Future<void> _initHiveAsync() async {
    try {
      await Future.any([
        _loadHive(),
        Future.delayed(const Duration(seconds: 3), () {
          throw TimeoutException('Hive initialization timed out after 3 seconds');
        }),
      ]);
    } catch (e) {
      // In case of a locked .lock file or disk timeout, gracefully retain in-memory fallback
      debugPrint('[Persistence] Hive initialization fallback active: $e');
      _watchlistRepo.initInMemory();
      _settingsRepo.initInMemory();
    }
  }

  Future<void> _loadHive() async {
    await Hive.initFlutter();
    await _watchlistRepo.init();
    await _settingsRepo.init();
    _orchestrator.enabledStoreIds = _settingsRepo.state.enabledStoreIds;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettingsState>(
      valueListenable: _settingsRepo.stateNotifier,
      builder: (context, settingsState, _) {
        final isRtl = settingsState.isArabic;

        return MaterialApp(
          title: isRtl ? 'عروض الصيدليات والعناية' : 'Saudi Pharmacy Deals',
          debugShowCheckedModeBanner: false,
          locale: Locale(settingsState.language.name),
          builder: (context, child) {
            return Directionality(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00796B), // Deep medical teal
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF0F172A),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF26A69A),
              brightness: Brightness.dark,
            ),
          ),
          themeMode: ThemeMode.system,
          home: HomeComparisonScreen(
            orchestrator: _orchestrator,
            watchlistRepository: _watchlistRepo,
            settingsRepository: _settingsRepo,
          ),
        );
      },
    );
  }
}
