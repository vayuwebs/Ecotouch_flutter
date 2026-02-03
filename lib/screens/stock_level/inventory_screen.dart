import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../models/stock_item.dart';
import '../../models/stock_by_bag_size.dart';
import '../../services/stock_calculation_service.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/stat_card.dart';
import '../../providers/global_providers.dart';

enum StockViewType { rawMaterials, products }

final stockViewTypeProvider =
    StateProvider<StockViewType>((ref) => StockViewType.rawMaterials);

final rawMaterialStockProvider =
    FutureProvider.family<List<StockItem>, DateTime>((ref, date) async {
  return await StockCalculationService.getRawMaterialStockItems(date);
});

final productStockProvider =
    FutureProvider.family<List<StockItem>, DateTime>((ref, date) async {
  return await StockCalculationService.getProductStockItems(date);
});

final rawMaterialStockByBagSizeProvider =
    FutureProvider.family<List<StockByBagSize>, DateTime>((ref, date) async {
  return await StockCalculationService.calculateRawMaterialStockByBagSize(date);
});

final productStockByBagSizeProvider =
    FutureProvider.family<List<StockByBagSize>, DateTime>((ref, date) async {
  return await StockCalculationService.calculateProductStockByBagSize(date);
});

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final viewType = ref.watch(stockViewTypeProvider);

    final stockAsync = viewType == StockViewType.rawMaterials
        ? ref.watch(rawMaterialStockProvider(selectedDate))
        : ref.watch(productStockProvider(selectedDate));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Toggle
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inventory',
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Real-time inventory monitoring',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                      ),
                    ],
                  ),
                ),

                // Refresh and View Type Toggle - Centered
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkSurfaceVariant
                            : AppColors.lightSurfaceVariant,
                        borderRadius:
                            BorderRadius.circular(AppTheme.borderRadius),
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildToggleButton(
                            context,
                            'Raw Materials',
                            viewType == StockViewType.rawMaterials,
                            () => ref
                                .read(stockViewTypeProvider.notifier)
                                .state = StockViewType.rawMaterials,
                          ),
                          const SizedBox(width: 4),
                          _buildToggleButton(
                            context,
                            'Products',
                            viewType == StockViewType.products,
                            () => ref
                                .read(stockViewTypeProvider.notifier)
                                .state = StockViewType.products,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh Inventory',
                      onPressed: () {
                        ref.invalidate(rawMaterialStockProvider(selectedDate));
                        ref.invalidate(productStockProvider(selectedDate));
                        ref.invalidate(
                            rawMaterialStockByBagSizeProvider(selectedDate));
                        ref.invalidate(
                            productStockByBagSizeProvider(selectedDate));

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Inventory refreshed'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(milliseconds: 1000),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                // Spacer to balance
                const Expanded(child: SizedBox()),
              ],
            ),

            const SizedBox(height: 32),

            // Stock Summary Cards
            stockAsync.when(
              data: (stockItems) {
                final sufficient = stockItems
                    .where((s) => s.status == StockStatus.sufficient)
                    .length;
                final low =
                    stockItems.where((s) => s.status == StockStatus.low).length;
                final critical = stockItems
                    .where((s) => s.status == StockStatus.critical)
                    .length;

                return Row(
                  children: [
                    Expanded(
                      child: CompactStatCard(
                        icon: Icons.check_circle_outline,
                        color: AppColors.success,
                        label: 'Sufficient Stock',
                        value: sufficient.toString(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CompactStatCard(
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.warning,
                        label: 'Low Stock',
                        value: low.toString(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CompactStatCard(
                        icon: Icons.error_outline,
                        color: AppColors.error,
                        label: 'Critical / Out',
                        value: critical.toString(),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox(),
            ),

            const SizedBox(height: 32),

            // Stock Table
            Expanded(
              child: _buildStockTable(context, ref, selectedDate, viewType),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockTable(BuildContext context, WidgetRef ref,
      DateTime selectedDate, StockViewType viewType) {
    // We use the aggregated providers for the main list
    final stockAsync = viewType == StockViewType.rawMaterials
        ? ref.watch(rawMaterialStockProvider(selectedDate))
        : ref.watch(productStockProvider(selectedDate));

    return stockAsync.when(
      data: (stockItems) {
        if (stockItems.isEmpty) {
          return Card(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 64,
                      color:
                          Theme.of(context).iconTheme.color?.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'No items found',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                  ),
                ],
              ),
            ),
          );
        }

        return Card(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Current Inventory',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                          Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkSurfaceVariant
                              : AppColors.lightSurfaceVariant),
                      dataRowHeight: 60,
                      columns: const [
                        DataColumn(label: Text('Item Name')),
                        DataColumn(
                            label: Text('Total Stock')), // Absolute Quantity
                        DataColumn(label: Text('Status')),
                      ],
                      rows: stockItems.map((item) {
                        return DataRow(
                          onSelectChanged: (_) => _showStockDetails(
                              context, ref, item, selectedDate, viewType),
                          cells: [
                            DataCell(Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Theme.of(context).dividerColor),
                                  ),
                                  child: Icon(
                                    viewType == StockViewType.rawMaterials
                                        ? Icons.science_outlined
                                        : Icons.inventory_2_outlined,
                                    size: 20,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(item.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                              ],
                            )),
                            DataCell(
                              Text(
                                '${item.currentStock.toStringAsFixed(2)} ${item.unit}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryBlue),
                              ),
                            ),
                            DataCell(
                              StatusBadge(
                                label: item.status.displayName,
                                type: item.status == StockStatus.sufficient
                                    ? StatusType.available
                                    : item.status == StockStatus.low
                                        ? StatusType.low
                                        : StatusType.critical,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text('Error: $error',
            style: const TextStyle(color: AppColors.error)),
      ),
    );
  }

  Widget _buildStockDetailsContent(
      List<StockByBagSize> allStock, int materialId, String unit) {
    // Filter for selected item
    final details = allStock.where((s) => s.materialId == materialId).toList();

    if (details.isEmpty) {
      return const Text('No detailed breakdown available.');
    }

    // Group by Bag Size
    final Map<double, List<StockByBagSize>> grouped = {};
    for (var d in details) {
      grouped.putIfAbsent(d.bagSize, () => []).add(d);
    }

    // Sort sizes
    final sortedSizes = grouped.keys.toList()..sort();

    double grandTotal = 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Text('Bag Size (Batch Details)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13))),
              Expanded(
                  flex: 1,
                  child: Text('Count',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13))),
              Expanded(
                  flex: 1,
                  child: Text('Total Wt',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13))),
            ],
          ),
        ),
        const Divider(),

        // Grouped List
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: sortedSizes.map((size) {
              final batches = grouped[size]!;
              final totalCount = batches.fold(0, (sum, b) => sum + b.bagCount);
              final totalWeight =
                  batches.fold(0.0, (sum, b) => sum + b.totalWeight);
              grandTotal += totalWeight;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Group Header (Size Summary)
                  Container(
                    color: Colors.grey.shade100,
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            '$size $unit Bags',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '$totalCount pkts',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            totalWeight.toStringAsFixed(1),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Batches
                  ...batches.map((d) {
                    final dateStr = d.inwardDate != null
                        ? "${d.inwardDate!.day}/${d.inwardDate!.month}"
                        : "-";
                    return Padding(
                      padding: const EdgeInsets.only(
                          left: 16.0, right: 4.0, top: 2, bottom: 2),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              'Batch #${d.inwardEntryId ?? "?"} ($dateStr)',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              '${d.bagCount}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              d.totalWeight.toStringAsFixed(1),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  const Divider(height: 12),
                ],
              );
            }).toList(),
          ),
        ),

        const Divider(thickness: 1.5),

        // Grand Total
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Grand Total',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(
                '${grandTotal.toStringAsFixed(2)} $unit',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.primaryBlue),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showStockDetails(BuildContext context, WidgetRef ref, StockItem item,
      DateTime date, StockViewType viewType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              viewType == StockViewType.rawMaterials
                  ? Icons.science_outlined
                  : Icons.inventory_2_outlined,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(width: 8),
            Text(item.name),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400, // Fixed height for scrolling
          child: Consumer(
            builder: (context, ref, _) {
              final detailsAsync = viewType == StockViewType.rawMaterials
                  ? ref.watch(rawMaterialStockByBagSizeProvider(date))
                  : ref.watch(productStockByBagSizeProvider(date));

              return detailsAsync.when(
                data: (allStock) =>
                    _buildStockDetailsContent(allStock, item.id, item.unit),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, __) => Text('Error loading details: $e'),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(
      BuildContext context, String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.borderRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : Theme.of(context).textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
