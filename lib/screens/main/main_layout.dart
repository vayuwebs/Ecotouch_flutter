import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/global_providers.dart';
import '../../theme/app_colors.dart';
import '../../utils/constants.dart';
import '../dashboard/dashboard_screen.dart';
import '../attendance/attendance_screen.dart';
import '../inward/inward_screen.dart';
import '../production/production_screen.dart';
import '../outward/outward_screen.dart';
import '../outward/outward_screen.dart';
import '../stock_level/inventory_screen.dart';
import '../logistics/logistics_screen.dart';
import '../summary/summary_screen.dart';
import '../settings/settings_screen.dart';

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  int _selectedIndex = 0;
  bool _isSidebarCollapsed = false;

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Dashboard'),
    _NavItem(icon: Icons.people_outline, selectedIcon: Icons.people, label: 'Attendance'),
    _NavItem(icon: Icons.arrow_circle_down_outlined, selectedIcon: Icons.arrow_circle_down, label: 'Inward'),
    _NavItem(icon: Icons.factory_outlined, selectedIcon: Icons.factory, label: 'Production'),
    _NavItem(icon: Icons.arrow_circle_up_outlined, selectedIcon: Icons.arrow_circle_up, label: 'Outward'),
    _NavItem(icon: Icons.local_shipping_outlined, selectedIcon: Icons.local_shipping, label: 'Logistics'),
    _NavItem(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: 'Inventory'),
    _NavItem(icon: Icons.summarize_outlined, selectedIcon: Icons.summarize, label: 'Summary'),
    _NavItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Settings'),
  ];

  final List<Widget> _screens = const [
    DashboardScreen(),
    AttendanceScreen(),
    InwardScreen(),
    ProductionScreen(),
    OutwardScreen(),
    LogisticsScreen(),
    InventoryScreen(),
    SummaryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(),
          
          // Main Content
          Expanded(
            child: Column(
              children: [
                // Top Bar
                _buildTopBar(),
                
                // Content Area
                Expanded(
                  child: ClipRect(
                    child: _screens[_selectedIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final width = _isSidebarCollapsed 
        ? AppConstants.sidebarCollapsedWidth 
        : AppConstants.sidebarWidth;
    
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Logo/Header
          Container(
            height: AppConstants.topBarHeight,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: _isSidebarCollapsed ? 0 : 20),
            child: Row(
              mainAxisAlignment: _isSidebarCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.eco, color: AppColors.primaryBlue, size: 24),
                ),
                if (!_isSidebarCollapsed) ...[
                  const SizedBox(width: 12),
                  Text(
                    'EcoTouch',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Divider(height: 1, color: Theme.of(context).dividerColor), // Removed as requested
          const SizedBox(height: 16),
          
          // Navigation Items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final isSelected = _selectedIndex == index;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _selectedIndex = index),
                      borderRadius: BorderRadius.circular(8),
                      hoverColor: Theme.of(context).hoverColor,
                      child: Container(
                        height: 48,
                        padding: EdgeInsets.symmetric(
                          horizontal: _isSidebarCollapsed ? 0 : 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primaryBlue : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: _isSidebarCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                          children: [
                            Icon(
                              isSelected ? item.selectedIcon : item.icon,
                              color: isSelected ? Colors.white : Theme.of(context).iconTheme.color,
                              size: 22,
                            ),
                            if (!_isSidebarCollapsed) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Collapse Button
          // const Divider(height: 1, color: AppColors.border), // Removed as requested
          InkWell(
            onTap: () => setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: Icon(
                _isSidebarCollapsed ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final selectedDate = ref.watch(selectedDateProvider);

    return Container(
      height: AppConstants.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Current Screen Title
          Text(
            _navItems[_selectedIndex].label,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          
          const Spacer(),

          // Today Button
          InkWell(
            onTap: () {
              final now = DateTime.now();
              ref.read(selectedDateProvider.notifier).state = DateTime(now.year, now.month, now.day);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.3)),
              ),
              child: Text(
                'Today',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 16),

          // Date Selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today, size: 16, color: Theme.of(context).iconTheme.color),
                const SizedBox(width: 8),
                Text(
                  '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                  style: TextStyle(fontWeight: FontWeight.w500, color: Theme.of(context).textTheme.bodyMedium?.color),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: Theme.of(context).colorScheme.copyWith(
                              primary: AppColors.primaryBlue,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      ref.read(selectedDateProvider.notifier).state = picked;
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Icon(Icons.edit, size: 16, color: AppColors.primaryBlue),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 24),
          
          // User Profile / Settings
          CircleAvatar(
            backgroundColor: Theme.of(context).cardColor,
            radius: 18,
            child: Icon(Icons.person, size: 20, color: Theme.of(context).iconTheme.color),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  _NavItem({
    required this.icon, 
    required this.selectedIcon, 
    required this.label,
  });
}
