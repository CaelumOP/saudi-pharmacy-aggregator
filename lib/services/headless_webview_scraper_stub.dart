import 'dart:async';

/// Pure Dart/CLI stub for headless WebView scraper on non-Flutter environments.
class HeadlessWebviewScraper {
  static final HeadlessWebviewScraper instance = HeadlessWebviewScraper._();

  HeadlessWebviewScraper._();

  final Map<String, ({String html, DateTime time})> _htmlCache = {};

  /// Caches rendered HTML for a URL (e.g. from [WafChallengeSheet]).
  void cacheHtmlForUrl(String url, String html) {
    _htmlCache[url] = (html: html, time: DateTime.now());
  }

  /// Retrieves cached HTML if available and under 90 seconds old.
  String? getCachedHtmlForUrl(String url) {
    final entry = _htmlCache[url];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.time).inSeconds > 90) {
      _htmlCache.remove(url);
      return null;
    }
    return entry.html;
  }

  /// Always returns null on CLI/desktop where WebView is unavailable.
  Future<String?> scrapeHtml({
    required String storeId,
    required String url,
    Duration timeout = const Duration(seconds: 7),
  }) async =>
      null;
}
