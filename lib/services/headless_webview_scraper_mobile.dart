import 'dart:async';
import 'dart:io' as io;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../adapters/pharmacy_adapter.dart';
import 'cookie_bridge_service.dart';

/// Service providing silent background HTML scraping and cookie synchronization via [HeadlessInAppWebView].
///
/// Designed to execute on mobile platforms (Android/iOS) where native WebView engines
/// transparently pass Cloudflare Turnstile bot evaluations without displaying visual UI.
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

  /// Scrapes the rendered HTML content of [url] inside an invisible [HeadlessInAppWebView].
  ///
  /// Extracts cookies and synchronization tokens into [CookieBridgeService].
  /// Throws [CloudflareChallengeException] if an active, interactive Turnstile challenge
  /// widget requiring human captcha intervention is identified.
  Future<String?> scrapeHtml({
    required String storeId,
    required String url,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    // Check cached HTML first
    final cached = getCachedHtmlForUrl(url);
    if (cached != null) return cached;

    // HeadlessInAppWebView is only supported on mobile platforms
    if (!io.Platform.isAndroid && !io.Platform.isIOS) {
      return null;
    }

    final completer = Completer<String?>();
    HeadlessInAppWebView? headlessWebView;

    try {
      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          thirdPartyCookiesEnabled: true,
          useShouldOverrideUrlLoading: false,
          userAgent: CookieBridgeService.instance.currentUserAgent,
        ),
        onLoadStop: (controller, loadedUrl) async {
          final startTime = DateTime.now();

          // Wait up to 7 seconds until title does NOT contain challenge markers
          // AND document.readyState === 'complete'
          while (DateTime.now().difference(startTime).inSeconds < 7) {
            try {
              final title = await controller.getTitle() ?? '';
              final isChallenged = title.contains('Just a moment') ||
                  title.contains('Attention Required') ||
                  title.contains('Cloudflare');

              // Inspect DOM for active Turnstile widget requiring interactive click
              final dynamic hasActiveWidget = await controller.evaluateJavascript(
                source: '''
                  (function() {
                    return document.querySelector('#challenge-running') !== null ||
                           document.querySelector('.cf-turnstile') !== null ||
                           document.querySelector('#challenge-stage') !== null;
                  })()
                ''',
              );

              if (isChallenged && hasActiveWidget == true) {
                if (!completer.isCompleted) {
                  completer.completeError(
                    CloudflareChallengeException(
                      storeId: storeId,
                      challengeUrl: url,
                      message: 'Interactive Cloudflare Turnstile challenge requires user action',
                    ),
                  );
                }
                return;
              }

              final readyState = await controller.evaluateJavascript(source: 'document.readyState');
              if (!isChallenged && readyState == 'complete') {
                // Sync clearance cookies
                final webCookies = await CookieManager.instance().getCookies(
                  url: loadedUrl ?? WebUri(url),
                );
                if (webCookies.isNotEmpty) {
                  final ioCookies = webCookies.map((wc) {
                    final cookie = io.Cookie(wc.name, wc.value?.toString() ?? '');
                    if (wc.domain != null) cookie.domain = wc.domain!;
                    if (wc.path != null) cookie.path = wc.path!;
                    cookie.httpOnly = wc.isHttpOnly ?? false;
                    cookie.secure = wc.isSecure ?? false;
                    return cookie;
                  }).toList();
                  final uri = Uri.parse(url);
                  await CookieBridgeService.instance.saveCookies(uri, ioCookies);
                }

                // Sync UA
                final ua = await controller.evaluateJavascript(source: 'navigator.userAgent');
                if (ua is String && ua.isNotEmpty) {
                  CookieBridgeService.instance.setUserAgent(ua);
                }

                final html = await controller.getHtml();
                if (html != null && html.isNotEmpty) {
                  cacheHtmlForUrl(url, html);
                }
                if (!completer.isCompleted) {
                  completer.complete(html);
                }
                return;
              }
            } catch (_) {}

            await Future.delayed(const Duration(milliseconds: 500));
          }

          // Fallback if loop ended
          try {
            final html = await controller.getHtml();
            if (!completer.isCompleted) {
              completer.complete(html);
            }
          } catch (_) {
            if (!completer.isCompleted) completer.complete(null);
          }
        },
      );

      await headlessWebView.run();

      return await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
    } catch (e) {
      if (e is CloudflareChallengeException) rethrow;
      return null;
    } finally {
      await headlessWebView?.dispose();
    }
  }
}
