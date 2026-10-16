import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../services/cookie_bridge_service.dart';

/// Network helper providing configured [Dio] instances with host-scoped certificate policies
/// and automated [CookieBridgeService] synchronization.
///
/// Ensures compliance with endpoints requiring custom TLS verification (such as
/// stgprevapi.al-dawaa.com) while keeping other network traffic protected by standard CA verification
/// and managing persistent Cloudflare Turnstile clearance cookies.
class NetworkClientHelper {
  NetworkClientHelper._();

  /// Creates a standard [Dio] instance configured with timeouts, synchronized User-Agent,
  /// and [CookieBridgeService] cookie persistence.
  static Dio createDefaultClient({
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 15),
    CookieBridgeService? cookieBridge,
  }) {
    final bridge = cookieBridge ?? CookieBridgeService.instance;
    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'User-Agent': bridge.currentUserAgent,
        },
      ),
    );

    // Attach cookie manager for automated cookie preservation across requests
    dio.interceptors.add(bridge.dioCookieManager);

    return dio;
  }

  /// Configures [dio] with host-scoped certificate bypass strictly restricted to [allowedHosts].
  ///
  /// Prevents global TLS disabling by matching hostnames explicitly inside [badCertificateCallback].
  static void configureHostScopedSsl(Dio dio, List<String> allowedHosts) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          return allowedHosts.contains(host);
        };
        return client;
      },
    );
  }

  /// Convenience factory configuring a [Dio] client allowing `stgprevapi.al-dawaa.com`
  /// with synchronized cookie persistence.
  static Dio createAlDawaaClient({CookieBridgeService? cookieBridge}) {
    final dio = createDefaultClient(cookieBridge: cookieBridge);
    configureHostScopedSsl(dio, const ['stgprevapi.al-dawaa.com']);
    return dio;
  }

  /// Convenience factory configuring a [Dio] client allowing `kbeautykingdom.com`
  /// with synchronized cookie persistence.
  static Dio createKBeautyKingdomClient({CookieBridgeService? cookieBridge}) {
    final dio = createDefaultClient(cookieBridge: cookieBridge);
    configureHostScopedSsl(dio, const ['kbeautykingdom.com']);
    return dio;
  }

  /// True if native Chromium Cronet transport engine is supported on this platform.
  static bool get isCronetSupported => Platform.isAndroid;
}
