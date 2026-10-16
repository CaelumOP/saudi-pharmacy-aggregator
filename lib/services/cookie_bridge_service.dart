import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

/// Singleton bridge coordinating cookies and User-Agent headers across HTTP and WebView layers.
///
/// Ensures Cloudflare `cf_clearance` cookies and their associated Chromium User-Agent strings
/// obtained from in-app WebView challenges are synchronized into Dio's network requests.
class CookieBridgeService {
  static final CookieBridgeService instance = CookieBridgeService._();

  CookieJar _cookieJar;
  String _currentUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  CookieBridgeService._() : _cookieJar = CookieJar();

  /// Visible for testing to inject custom or mock [CookieJar] instances.
  CookieBridgeService.withJar(this._cookieJar);

  /// Active [CookieJar] managing in-memory or persisted cookies.
  CookieJar get cookieJar => _cookieJar;

  /// Active User-Agent matching the browser fingerprint required by Cloudflare Turnstile.
  String get currentUserAgent => _currentUserAgent;

  /// Creates a [CookieManager] interceptor attaching this bridge's cookies to [Dio].
  CookieManager get dioCookieManager => CookieManager(_cookieJar);

  /// Updates the active [CookieJar], for example when switching to [PersistCookieJar] on device.
  void setCookieJar(CookieJar jar) {
    _cookieJar = jar;
  }

  /// Sets the active User-Agent string synchronized from the WebView session.
  void setUserAgent(String userAgent) {
    if (userAgent.trim().isNotEmpty) {
      _currentUserAgent = userAgent.trim();
    }
  }

  /// Saves cookies for [uri] into the cookie jar.
  Future<void> saveCookies(Uri uri, List<Cookie> cookies) async {
    await _cookieJar.saveFromResponse(uri, cookies);
  }

  /// Retrieves cookies stored for [uri].
  Future<List<Cookie>> loadCookies(Uri uri) async {
    return _cookieJar.loadForRequest(uri);
  }

  /// Checks whether a valid Cloudflare clearance cookie (`cf_clearance`) exists for [uri].
  Future<bool> hasCfClearance(Uri uri) async {
    final cookies = await loadCookies(uri);
    return cookies.any((c) => c.name == 'cf_clearance' && c.value.isNotEmpty);
  }

  /// Clears all cookies from the active jar.
  Future<void> clearCookies() async {
    await _cookieJar.deleteAll();
  }
}
