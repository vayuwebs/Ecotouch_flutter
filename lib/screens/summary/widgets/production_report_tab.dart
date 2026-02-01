import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../theme/app_colors.dart';
import '../../../../providers/summary_providers.dart';
import '../../../../services/export_service.dart';
import '../../../../widgets/export_dialog.dart';
import '../../../../utils/date_utils.dart' as app_date_utils;
import '../../../../models/production.dart';
import '../../../../models/production.dart';

class ProductionReportTab extends ConsumerWidget {
  const ProductionReportTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateRange = ref.watch(reportDateRangeProvider);
    final viewMode = ref.watch(reportViewModeProvider);
    final dataAsync = ref.watch(productionReportProvider);

    return Column(
      children: [
        // Controls
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              _buildViewSelector(context, ref, viewMode),
              const SizedBox(width: 16),
              _buildDateNavigator(context, ref, dateRange),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Metrics Cards (Unchanged)
                dataAsync.when(
                  data: (data) {
                    final totals = data['totals'];
                    final totalQty =
                        (totals['total_quantity'] as num?)?.toDouble() ?? 0.0;
                    final totalBatches = (totals['total_batches'] as int?) ?? 0;
                    final avgYield =
                        totalBatches > 0 ? totalQty / totalBatches : 0.0;

                    return Row(
                      children: [
                        Expanded(
                            child: _buildMetricCard(
                                context,
                                'Total Production',
                                '${totalQty.toStringAsFixed(0)}',
                                'units',
                                Icons.factory,
                                AppColors.info)),
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildMetricCard(
                                context,
                                'Total Batches',
                                '$totalBatches',
                                'batches',
                                Icons.layers,
                                AppColors.warning)),
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildMetricCard(
                                context,
                                'Avg Yield',
                                '${avgYield.toStringAsFixed(1)}',
                                'pack/batch',
                                Icons.analytics,
                                AppColors.chartSecondary)),
                      ],
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox(),
                ),

                const SizedBox(height: 24),

                // List Section
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context).dividerColor.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryBlue
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.arrow_drop_down,
                                        color: AppColors.primaryBlue),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'PRODUCTION SUMMARY',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                            _buildExportAction(
                                Icons.table_view,
                                'Export',
                                AppColors.success,
                                () => _handleExport(context, dataAsync)),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Grouped List Body (Unchanged)
                      dataAsync.when(
                        data: (data) {
                          final list = data['data'] as List<Production>;
                          if (list.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                  child: Text(
                                      "No production records found for this period.")),
                            );
                          }

                          // Grouping Logic
                          // Map<ProductName, {total_quantity, total_batches, sizes: Map<BagSize, {count, batches}>}>
                          final Map<String, Map<String, dynamic>> grouped = {};

                          for (var item in list) {
                            final name = item.productName ?? 'Unknown';
                            final qty = item.totalQuantity;
                            final batches = item.batches;
                            final size = item.unitSize ?? 0.0;

                            if (!grouped.containsKey(name)) {
                              grouped[name] = {
                                'total_quantity': 0.0,
                                'total_batches': 0,
                                'sizes': <double, Map<String, dynamic>>{}
                              };
                            }

                            grouped[name]!['total_quantity'] += qty;
                            grouped[name]!['total_batches'] += batches;

                            final sizes = grouped[name]!['sizes']
                                as Map<double, Map<String, dynamic>>;
                            if (!sizes.containsKey(size)) {
                              sizes[size] = {'quantity': 0.0, 'batches': 0};
                            }
                            sizes[size]!['quantity'] =
                                (sizes[size]!['quantity'] ?? 0.0) + qty;
                            sizes[size]!['batches'] =
                                (sizes[size]!['batches'] ?? 0) + batches;
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: grouped.length,
                            separatorBuilder: (c, i) => Divider(
                                height: 1,
                                color: Theme.of(context)
                                    .dividerColor
                                    .withOpacity(0.05)),
                            itemBuilder: (context, index) {
                              final name = grouped.keys.elementAt(index);
                              final group = grouped[name]!;
                              final totalQty =
                                  group['total_quantity'] as double;
                              final totalBatches =
                                  group['total_batches'] as int;
                              final sizes = group['sizes']
                                  as Map<double, Map<String, dynamic>>;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                      color: Theme.of(context)
                                          .dividerColor
                                          .withOpacity(0.1)),
                                ),
                                child: InkWell(
                                  onTap: () => _showDetailDialog(context, name,
                                      totalQty, totalBatches, sizes),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(name,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${totalQty.toStringAsFixed(0)} units ($totalBatches batches)',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.color
                                                      ?.withOpacity(0.7)),
                                            ),
                                          ],
                                        ),
                                        Icon(Icons.chevron_right,
                                            size: 20,
                                            color: Theme.of(context).hintColor),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        loading: () => const SizedBox(
                            height: 200,
                            child: Center(child: CircularProgressIndicator())),
                        error: (e, s) =>
                            Center(child: Text('Error loading data: $e')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleExport(
      BuildContext context, AsyncValue<Map<String, dynamic>> dataAsync) async {
    final data = dataAsync.value;
    if (data == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No data to export')));
      return;
    }

    final config = await showDialog<ExportConfig>(
      context: context,
      builder: (c) => const ExportDialog(
          title: 'Export Production Summary', showScopeSelector: false),
    );

    if (config == null) return;

    final list = data['data'] as List<Production>;

    // Group Data for Export
    final Map<String, Map<String, dynamic>> grouped = {};
    for (var item in list) {
      final name = item.productName ?? 'Unknown';
      final qty = item.totalQuantity;
      final size = item.unitSize ?? 0.0;

      if (!grouped.containsKey(name)) {
        grouped[name] = {'sizes': <double, double>{}};
      }

      final sizes = grouped[name]!['sizes'] as Map<double, double>;
      sizes[size] = (sizes[size] ?? 0.0) + qty;
    }

    // Build Rows
    final List<List<dynamic>> rows = [];
    for (var name in grouped.keys) {
      final sizes = grouped[name]!['sizes'] as Map<double, double>;
      for (var size in sizes.keys) {
        final qty = sizes[size]!;
        final boxes = size > 0 ? (qty / size) : 0.0;
        rows.add([name, size, boxes.toStringAsFixed(1), qty]);
      }
    }

    final headers = [
      'Product Name',
      'Box Size (pcs)',
      'Boxes',
      'Total Quantity'
    ];

    String? path;
    if (config.format == ExportFormat.excel) {
      path = await ExportService().exportToExcel(
        title: 'Production Summary',
        headers: headers,
        data: rows,
      );
    } else {
      path = await ExportService().exportToPdf(
        title: 'Production Summary',
        headers: headers,
        data: rows,
      );
    }

    if (context.mounted && path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report saved to: $path'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ... (dialog logic remains)

  // ... (build helpers remain)

  Widget _buildExportAction(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(4),
          color: color.withOpacity(0.05),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _col(BuildContext context, String text, int flex,
      {TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).hintColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String text, int flex,
      {TextAlign align = TextAlign.left, bool isBold = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          color: isBold
              ? Theme.of(context).textTheme.bodyLarge?.color
              : Theme.of(context).textTheme.bodyMedium?.color,
        ),
      ),
    );
  }

  Widget _buildViewSelector(
      BuildContext context, WidgetRef ref, ReportViewMode currentMode) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border:
            Border.all(color: Theme.of(context).dividerColor.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ReportViewMode>(
          value: currentMode,
          icon: Icon(Icons.keyboard_arrow_down,
              size: 16, color: Theme.of(context).iconTheme.color),
          style: Theme.of(context).textTheme.bodyMedium,
          onChanged: (ReportViewMode? newValue) {
            if (newValue != null) {
              ref.read(reportViewModeProvider.notifier).state = newValue;
            }
          },
          items: ReportViewMode.values
              .map<DropdownMenuItem<ReportViewMode>>((ReportViewMode mode) {
            return DropdownMenuItem<ReportViewMode>(
              value: mode,
              child: Text(mode.label),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDateNavigator(
      BuildContext context, WidgetRef ref, DateTimeRange range) {
    final navigate = ref.read(reportNavigationProvider);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border:
            Border.all(color: Theme.of(context).dividerColor.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: () => navigate(false),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(
                    color: Theme.of(context).dividerColor.withOpacity(0.2)),
              ),
            ),
            child: Text(
              '${app_date_utils.DateUtils.formatDate(range.start)} - ${app_date_utils.DateUtils.formatDate(range.end)}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: () => navigate(true),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(BuildContext context, String title, String value,
      String unit, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text(unit,
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).hintColor)),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetailDialog(BuildContext context, String name, double totalQty,
      int totalBatches, Map<double, Map<String, dynamic>> sizes) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Details for $name'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total Quantity: ${totalQty.toStringAsFixed(0)}'),
              Text('Total Batches: $totalBatches'),
              const Divider(),
              const Text('By Box Size:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...sizes.entries.map((e) {
                final size = e.key;
                final qty = e.value['quantity'] as double;
                final batches = e.value['batches'] as int;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                      '$size size: ${qty.toStringAsFixed(0)} units ($batches batches)'),
                );
              }),
            ],
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
}
