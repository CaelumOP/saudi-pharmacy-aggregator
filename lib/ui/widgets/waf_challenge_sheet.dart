import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../services/cookie_bridge_service.dart';
import '../../services/headless_webview_scraper.dart';

/// Modal bottom sheet providing an interactive Cloudflare Turnstile verification challenge.
///
/// Loads the pharmacy's storefront challenge page, monitors cookie acquisition for `cf_clearance`,
/// synchronizes the browser User-Agent and cookies into [CookieBridgeService], and auto-dismisses.
class WafChallengeSheet extends StatefulWidget {
  /// Name of the pharmacy requiring challenge verification (e.g. "Al-Dawaa").
  final String storeName;

  /// Target challenge URL to load (e.g. "https://www.al-dawaa.com").
  final String challengeUrl;

  /// Optional callback invoked when challenge clearance has succeeded.
  final VoidCallback? onCleared;

  /// Creates a [WafChallengeSheet] for interactive Turnstile verification.
  const WafChallengeSheet({
    super.key,
    required this.storeName,
    required this.challengeUrl,
    this.onCleared,
  });

  /// Displays the challenge sheet inside a modal bottom sheet.
  static Future<bool?> show(
    BuildContext context, {
    required String storeName,
    required String challengeUrl,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WafChallengeSheet(
        storeName: storeName,
        challengeUrl: challengeUrl,
      ),
    );
  }

  @override
  State<WafChallengeSheet> createState() => _WafChallengeSheetState();
}

class _WafChallengeSheetState extends State<WafChallengeSheet> {
  InAppWebViewController? _webViewController;
  Timer? _cookiePollTimer;
  bool _isCheckingCookies = false;
  bool _hasCleared = false;

  bool get _isMobilePlatform => io.Platform.isAndroid || io.Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_isMobilePlatform) {
      _cookiePollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _checkClearanceCookies();
      });
    }
  }

  @override
  void dispose() {
    _cookiePollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkClearanceCookies() async {
    if (_isCheckingCookies || _hasCleared) return;
    _isCheckingCookies = true;

    try {
      final webCookieManager = CookieManager.instance();
      final webCookies = await webCookieManager.getCookies(
        url: WebUri(widget.challengeUrl),
      );

      final clearanceFound = webCookies.any(
        (c) => c.name == 'cf_clearance' && (c.value?.toString().isNotEmpty ?? false),
      );

      // Check if the page loaded normal storefront content without an active challenge
      String pageTitle = '';
      bool hasActiveChallengeWidget = false;
      if (_webViewController != null) {
        pageTitle = await _webViewController!.getTitle() ?? '';
        final dynamic widgetCheck = await _webViewController!.evaluateJavascript(
          source: '''
            (function() {
              return document.querySelector('#challenge-running') !== null ||
                     document.querySelector('.cf-turnstile') !== null ||
                     document.querySelector('#challenge-stage') !== null;
            })()
          ''',
        );
        hasActiveChallengeWidget = widgetCheck == true;
      }

      final isCloudflarePage = pageTitle.contains('Just a moment') ||
          pageTitle.contains('Attention Required') ||
          pageTitle.contains('Cloudflare');

      final isNormalPageLoaded = pageTitle.isNotEmpty && !isCloudflarePage && !hasActiveChallengeWidget;

      if ((clearanceFound || isNormalPageLoaded) && mounted) {
        _hasCleared = true;
        _cookiePollTimer?.cancel();

        // Convert and sync cookies to CookieBridgeService
        final ioCookies = webCookies.map((wc) {
          final cookie = io.Cookie(wc.name, wc.value?.toString() ?? '');
          if (wc.domain != null) cookie.domain = wc.domain!;
          if (wc.path != null) cookie.path = wc.path!;
          cookie.httpOnly = wc.isHttpOnly ?? false;
          cookie.secure = wc.isSecure ?? false;
          return cookie;
        }).toList();

        final uri = Uri.parse(widget.challengeUrl);
        await CookieBridgeService.instance.saveCookies(uri, ioCookies);

        // Sync browser User-Agent and cache verified HTML
        if (_webViewController != null) {
          final uaResult = await _webViewController!.evaluateJavascript(
            source: 'navigator.userAgent',
          );
          if (uaResult != null && uaResult is String) {
            CookieBridgeService.instance.setUserAgent(uaResult);
          }

          final html = await _webViewController!.getHtml();
          if (html != null && html.isNotEmpty) {
            HeadlessWebviewScraper.instance.cacheHtmlForUrl(widget.challengeUrl, html);
          }
        }

        widget.onCleared?.call();

        // If page loaded normally without requiring interactive challenge, wait 1500ms before dismissing
        if (isNormalPageLoaded && !clearanceFound) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }

        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (_) {
      // In-flight poll errors are silently retried on the next tick
    } finally {
      _isCheckingCookies = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.85;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.security, color: Colors.blueAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Verify ${widget.storeName}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content Area
          Expanded(
            child: _isMobilePlatform
                ? InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.challengeUrl)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      thirdPartyCookiesEnabled: true,
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                    onLoadStop: (controller, url) {
                      _checkClearanceCookies();
                    },
                  )
                : _buildDesktopFallbackView(),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopFallbackView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.desktop_windows, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Turnstile Challenge for ${widget.storeName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Interactive Cloudflare Turnstile verification runs via native mobile webview.\n'
              'On desktop or in test environments, secondary endpoints or recorded fixtures are used.',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                widget.onCleared?.call();
                Navigator.of(context).pop(true);
              },
              child: const Text('Dismiss & Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
