import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/app_settings_repository.dart';

/// Interactive modal bottom sheet allowing the user to configure app language
/// and enable/disable individual comparison stores.
class SettingsBottomSheet extends StatelessWidget {
  /// Optional repository instance.
  final AppSettingsRepository? repository;

  /// Callback invoked whenever enabled stores change so parent screen can refresh immediately.
  final VoidCallback? onSettingsChanged;

  /// Creates a [SettingsBottomSheet] instance.
  const SettingsBottomSheet({
    super.key,
    this.repository,
    this.onSettingsChanged,
  });

  /// Displays the settings bottom sheet.
  static Future<void> show(
    BuildContext context, {
    AppSettingsRepository? repository,
    VoidCallback? onSettingsChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SettingsBottomSheet(
        repository: repository,
        onSettingsChanged: onSettingsChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? AppSettingsRepository.instance;

    return ValueListenableBuilder<AppSettingsState>(
      valueListenable: repo.stateNotifier,
      builder: (context, state, _) {
        final strings = AppStrings(state.language);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final cardBg = isDark ? const Color(0xFF1E293B) : Colors.grey.shade50;
        final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
        final subtitleText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
        final accentGreen = const Color(0xFF10B981);

        return Directionality(
          textDirection: state.isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top drag handle
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Header with title and close button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.tune_rounded, size: 22, color: Color(0xFF10B981)),
                      const SizedBox(width: 10),
                      Text(
                        strings.settingsTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: primaryText,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        color: subtitleText,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Scrollable content
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    children: [
                      // SECTION 1: LANGUAGE SELECTION
                      Text(
                        strings.languageSectionTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primaryText,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _LanguageOption(
                                label: strings.englishLanguage,
                                isSelected: state.language == AppLanguage.en,
                                onTap: () {
                                  repo.setLanguage(AppLanguage.en);
                                  onSettingsChanged?.call();
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _LanguageOption(
                                label: strings.arabicLanguage,
                                isSelected: state.language == AppLanguage.ar,
                                onTap: () {
                                  repo.setLanguage(AppLanguage.ar);
                                  onSettingsChanged?.call();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // SECTION 2: ACTIVE STORES
                      Row(
                        children: [
                          Text(
                            strings.activeStoresSectionTitle,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: primaryText,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${state.enabledStoreIds.length} / ${kAllStoreIds.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: accentGreen,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        strings.storesSubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: subtitleText,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Quick filter presets
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PresetChip(
                            label: strings.selectAllStores,
                            onTap: () {
                              repo.selectAllStores();
                              onSettingsChanged?.call();
                            },
                          ),
                          _PresetChip(
                            label: strings.selectWalkInOnly,
                            onTap: () {
                              repo.selectWalkInOnly();
                              onSettingsChanged?.call();
                            },
                          ),
                          _PresetChip(
                            label: strings.selectOnlineOnly,
                            onTap: () {
                              repo.selectOnlineOnly();
                              onSettingsChanged?.call();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Group 1: Walk-In Pharmacies
                      _StoreGroupHeader(
                        icon: Icons.local_pharmacy_outlined,
                        title: strings.walkInGroupHeader,
                        color: const Color(0xFF0284C7),
                      ),
                      const SizedBox(height: 8),
                      ...kWalkInStoreIds.map(
                        (storeId) => _StoreToggleTile(
                          storeId: storeId,
                          name: strings.storeName(storeId),
                          isEnabled: state.isStoreEnabled(storeId),
                          canDisable: state.enabledStoreIds.length > 1 || !state.isStoreEnabled(storeId),
                          onToggle: (val) async {
                            final success = await repo.setStoreEnabled(storeId, val);
                            if (!success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(strings.atLeastOneStoreError),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            } else {
                              onSettingsChanged?.call();
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Group 2: Online & K-Beauty Stores
                      _StoreGroupHeader(
                        icon: Icons.storefront_outlined,
                        title: strings.onlineGroupHeader,
                        color: const Color(0xFF8B5CF6),
                      ),
                      const SizedBox(height: 8),
                      ...kOnlineStoreIds.map(
                        (storeId) => _StoreToggleTile(
                          storeId: storeId,
                          name: strings.storeName(storeId),
                          isEnabled: state.isStoreEnabled(storeId),
                          canDisable: state.enabledStoreIds.length > 1 || !state.isStoreEnabled(storeId),
                          onToggle: (val) async {
                            final success = await repo.setStoreEnabled(storeId, val);
                            if (!success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(strings.atLeastOneStoreError),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            } else {
                              onSettingsChanged?.call();
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF10B981)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
        ),
      ),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
      side: BorderSide(
        color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onPressed: onTap,
    );
  }
}

class _StoreGroupHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _StoreGroupHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

class _StoreToggleTile extends StatelessWidget {
  final String storeId;
  final String name;
  final bool isEnabled;
  final bool canDisable;
  final ValueChanged<bool> onToggle;

  const _StoreToggleTile({
    required this.storeId,
    required this.name,
    required this.isEnabled,
    required this.canDisable,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF1E293B) : Colors.grey.shade50;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: isEnabled ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2),
            child: Text(
              name.isNotEmpty ? name.substring(0, 1) : 'S',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isEnabled ? const Color(0xFF10B981) : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isEnabled ? FontWeight.w700 : FontWeight.w500,
                color: isEnabled ? primaryText : (isDark ? const Color(0xFF64748B) : Colors.grey),
              ),
            ),
          ),
          Switch(
            value: isEnabled,
            activeThumbColor: const Color(0xFF10B981),
            onChanged: (val) {
              if (!val && !canDisable) {
                onToggle(val); // Will trigger error message
                return;
              }
              onToggle(val);
            },
          ),
        ],
      ),
    );
  }
}
