import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'widgets/workers_management.dart';
import 'widgets/raw_materials_management.dart';
import 'widgets/categories_management.dart';
import 'widgets/vehicles_management.dart';
import 'widgets/unit_conversions_management.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedSettingIndex = 0;

  final List<_SettingItem> _settingItems = [
    _SettingItem(
        icon: Icons.people_outline,
        label: 'Workers',
        description: 'Manage workforce'),
    _SettingItem(
        icon: Icons.inventory_2_outlined,
        label: 'Raw Materials',
        description: 'Stock items & units'),
    _SettingItem(
        icon: Icons.category_outlined,
        label: 'Categories',
        description: 'Product types'),
    _SettingItem(
        icon: Icons.local_shipping_outlined,
        label: 'Vehicles',
        description: 'Logistics fleet'),
    _SettingItem(
        icon: Icons.swap_horiz,
        label: 'Unit Conversions',
        description: 'Define conversion rates'),
  ];

  final List<Widget> _settingPanels = const [
    WorkersManagement(),
    RawMaterialsManagement(),
    CategoriesManagement(),
    VehiclesManagement(),
    UnitConversionsManagement(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // Settings Sidebar
          _buildSettingsSidebar(),

          // Settings Content
          Expanded(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: _settingPanels[_selectedSettingIndex],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border:
            Border(right: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                const Icon(Icons.admin_panel_settings,
                    color: AppColors.primaryBlue, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _settingItems.length,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _settingItems[index];
                final isSelected = _selectedSettingIndex == index;

                return InkWell(
                  onTap: () => setState(() => _selectedSettingIndex = index),
                  borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryBlue.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(AppTheme.borderRadius),
                      border: isSelected
                          ? Border.all(
                              color: AppColors.primaryBlue.withOpacity(0.3))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.icon,
                          color: isSelected
                              ? AppColors.primaryBlue
                              : Theme.of(context)
                                  .iconTheme
                                  .color
                                  ?.withOpacity(0.7),
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.primaryBlue
                                      : Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                item.description,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.primaryBlue.withOpacity(0.8)
                                      : Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.color,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.chevron_right,
                              size: 16, color: AppColors.primaryBlue),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'v1.0.0',
              style: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingItem {
  final IconData icon;
  final String label;
  final String description;

  _SettingItem({
    required this.icon,
    required this.label,
    required this.description,
  });
}
