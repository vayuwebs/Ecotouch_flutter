import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../providers/global_providers.dart';
import '../../widgets/stat_card.dart';
import 'widgets/production_graph_widget.dart';
import '../attendance/attendance_screen.dart';
import '../production/production_screen.dart';
import '../stock_level/inventory_screen.dart';
import '../main/tally_page_wrapper.dart';

// Providers for dashboard data
// Providers for dashboard data - Moved to global_providers.dart

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: statsAsync.when(
          data: (stats) => ListView(
            children: [
              // Header
              Row(
                children: [
                  Text(
                    'Dashboard Overview',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkSurfaceVariant
                          : AppColors.lightSurfaceVariant,
                      borderRadius:
                          BorderRadius.circular(AppTheme.borderRadius),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 16,
                            color:
                                Theme.of(context).textTheme.bodyMedium?.color),
                        const SizedBox(width: 8),
                        Text(
                          'Today',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Stat Cards
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.people_outline,
                      iconColor: AppColors.primaryBlue,
                      iconBackgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? AppColors.iconBackgroundBlue
                              : AppColors.lightIconBackgroundBlue,
                      title: 'Workers Present',
                      value: stats['workersPresent'].toString(),
                      subtitle: 'Active today',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const AttendanceScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: StatCard(
                      icon: Icons.factory_outlined,
                      iconColor: AppColors.success,
                      iconBackgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? AppColors.iconBackgroundGreen
                              : AppColors.lightIconBackgroundGreen,
                      title: 'Batches Produced',
                      value: stats['batchesProduced'].toString(),
                      subtitle: 'Units',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const ProductionScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: StatCard(
                      icon: Icons.inventory_2_outlined,
                      iconColor: stats['rawMaterialsLow'] > 0
                          ? AppColors.warning
                          : AppColors.success,
                      iconBackgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? (stats['rawMaterialsLow'] > 0
                                  ? AppColors.iconBackgroundOrange
                                  : AppColors.iconBackgroundGreen)
                              : (stats['rawMaterialsLow'] > 0
                                  ? AppColors.lightIconBackgroundOrange
                                  : AppColors.lightIconBackgroundGreen),
                      title: 'Raw Material',
                      value: stats['rawMaterialsLow'] == 0
                          ? 'Healthy'
                          : stats['rawMaterialsLow'].toString(),
                      subtitle: stats['rawMaterialsLow'] > 0
                          ? 'Low stock items'
                          : 'Stock levels sufficient',
                      onTap: () {
                        ref.read(stockViewTypeProvider.notifier).state =
                            StockViewType.rawMaterials;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const TallyPageWrapper(
                                  title: 'Inventory',
                                  child: InventoryScreen())),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: StatCard(
                      icon: Icons.inventory_outlined,
                      iconColor: stats['productsLow'] > 0
                          ? AppColors.warning
                          : AppColors.success,
                      iconBackgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? (stats['productsLow'] > 0
                                  ? AppColors.iconBackgroundOrange
                                  : AppColors.iconBackgroundGreen)
                              : (stats['productsLow'] > 0
                                  ? AppColors.lightIconBackgroundOrange
                                  : AppColors.lightIconBackgroundGreen),
                      title: 'Product Stock',
                      value: stats['productsLow'] == 0
                          ? 'Healthy'
                          : stats['productsLow'].toString(),
                      subtitle: stats['productsLow'] > 0
                          ? 'Low stock items'
                          : 'Stock levels sufficient',
                      onTap: () {
                        ref.read(stockViewTypeProvider.notifier).state =
                            StockViewType.products;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const TallyPageWrapper(
                                  title: 'Inventory',
                                  child: InventoryScreen())),
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Production Graph (Replaces Stock Alerts)
              // Production Graph
              SizedBox(
                height: 400,
                child: ProductionGraphWidget(
                    dailyStats: stats['productionHistory']),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Text('Error: $error',
                style: const TextStyle(color: AppColors.error)),
          ),
        ),
      ),
    );
  }
}
