import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Modal dialog providing camera-based GTIN barcode scanning with hardware acceleration and preset fallbacks.
///
/// Uses [MobileScanner] for hardware-accelerated EAN/GTIN recognition on mobile devices,
/// while offering quick preset selection and manual text entry for rapid testing.
class BarcodeScannerModal extends StatefulWidget {
  /// Callback invoked when a valid barcode or query is selected.
  final ValueChanged<String> onBarcodeScanned;

  /// Creates a [BarcodeScannerModal].
  const BarcodeScannerModal({
    super.key,
    required this.onBarcodeScanned,
  });

  /// Displays the barcode scanner as a full-screen modal bottom sheet.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BarcodeScannerModal(
        onBarcodeScanned: (gtin) => Navigator.of(ctx).pop(gtin),
      ),
    );
  }

  @override
  State<BarcodeScannerModal> createState() => _BarcodeScannerModalState();
}

class _BarcodeScannerModalState extends State<BarcodeScannerModal> {
  late final MobileScannerController _controller;
  final TextEditingController _manualInputController = TextEditingController();
  bool _isScanned = false;

  bool get _isCameraSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Common Saudi market sample barcodes and SKUs for rapid testing
  static const List<({String label, String gtin, String description})> _presets = [
    (
      label: 'Cetaphil Cleanser',
      gtin: '3499320017046',
      description: 'Cetaphil Gentle Skin Cleanser 473ml (EAN-13)'
    ),
    (
      label: 'Panadol Extra 24s',
      gtin: '6285096003799',
      description: 'Panadol Extra 500mg 24 Tablets (EAN-13)'
    ),
    (
      label: 'Panadol Advance',
      gtin: '102546',
      description: 'Panadol Advance 24 Tablets (Store SKU)'
    ),
    (
      label: 'Cetaphil Cream',
      gtin: '100436',
      description: 'Cetaphil Cream 453g (Store SKU)'
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Allow MobileScanner widget to manage startup automatically with autoStart: true
    _controller = MobileScannerController(
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
      ],
      detectionSpeed: DetectionSpeed.normal,
      autoStart: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        _isScanned = true;
        widget.onBarcodeScanned(code);
        break;
      }
    }
  }

  void _submitManual() {
    if (_isScanned) return;
    final code = _manualInputController.text.trim();
    if (code.isNotEmpty) {
      _isScanned = true;
      widget.onBarcodeScanned(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.85;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sheetBg = isDark ? const Color(0xFF1E2926) : Colors.white;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF111827);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF4B5563);
    final fallbackBg = isDark ? const Color(0xFF111827) : Colors.grey.shade100;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    Icon(
                      Icons.qr_code_scanner,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Scan Barcode (GTIN / EAN)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close, color: primaryTextColor),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade200),

          // Camera View or Desktop Fallback
          Expanded(
            flex: 3,
            child: _isCameraSupported
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error, child) {
                          return Container(
                            color: isDark ? const Color(0xFF111827) : Colors.black87,
                            padding: const EdgeInsets.all(20),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.amber, size: 48),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Camera Error: ${error.errorCode.name}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (error.errorDetails?.message != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      error.errorDetails!.message!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () => _controller.start(),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry Camera'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      // Target bounding frame
                      Container(
                        width: 260,
                        height: 160,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.8),
                            width: 2.5,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ],
                  )
                : Container(
                    color: fallbackBg,
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.camera_alt_outlined,
                            size: 48,
                            color: secondaryTextColor,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Camera Barcode Scanner',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Hardware camera scanning runs on Android/iOS devices.\nEnter or select a sample barcode below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Manual Entry & Quick Presets Section
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Manual input row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualInputController,
                          style: TextStyle(color: primaryTextColor),
                          decoration: InputDecoration(
                            hintText: 'Enter barcode or SKU (e.g. 3499320017046)',
                            hintStyle: TextStyle(color: secondaryTextColor),
                            prefixIcon: Icon(Icons.edit, color: secondaryTextColor),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onSubmitted: (_) => _submitManual(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _submitManual,
                        child: const Text('Search'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Text(
                    'Quick Presets (Real Saudi Pharmacy Items):',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presets.map((preset) {
                      return ActionChip(
                        avatar: const Icon(Icons.qr_code, size: 16),
                        label: Text('${preset.label} (${preset.gtin})'),
                        tooltip: preset.description,
                        onPressed: () {
                          if (_isScanned) return;
                          _isScanned = true;
                          widget.onBarcodeScanned(preset.gtin);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
