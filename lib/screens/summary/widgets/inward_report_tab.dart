import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../theme/app_colors.dart';
import '../../../../providers/summary_providers.dart';
import '../../../../services/export_service.dart';
import '../../../../widgets/export_dialog.dart';
import '../../../../utils/date_utils.dart' as app_date_utils;
import '../../../../models/inward.dart';
import '../../../../database/repositories/inward_repository.dart';

class InwardReportTab extends ConsumerWidget {
  const InwardReportTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateRange = ref.watch(reportDateRangeProvider);
    final viewMode = ref.watch(reportViewModeProvider);
    final dataAsync = ref.watch(inwardReportProvider);

    return Column(
      children: [
        // Controls (Unchanged)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              _buildViewSelector(context, ref, viewMode),
              const SizedBox(width: 16),
              _buildDateNavigator(context, ref, dateRange),
              const Spacer(),
              _buildExportButton(context),
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
                    final totalValue =
                        (totals['total_value'] as num?)?.toDouble() ?? 0.0;
                    final totalQty =
                        (totals['total_quantity'] as num?)?.toDouble() ?? 0.0;
                    final totalEntries = (totals['total_entries'] as int?) ?? 0;

                    return Row(
                      children: [
                        Expanded(
                            child: _buildMetricCard(
                                context,
                                'Total Weight',
                                '${totalValue.toStringAsFixed(2)}',
                                'kg',
                                Icons.scale,
                                AppColors.success)),
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildMetricCard(
                                context,
                                'Total Packs',
                                '${totalQty.toStringAsFixed(0)}',
                                'packs',
                                Icons.inventory_2,
                                AppColors.info)),
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildMetricCard(
                                context,
                                'Total Entries',
                                '$totalEntries',
                                'records',
                                Icons.receipt_long,
                                AppColors.warning)),
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
                                    'INWARD STOCK SUMMARY',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Grouped List Body (Unchanged)
                      dataAsync.when(
                        data: (data) {
                          final list = data['data'] as List<Inward>;
                          if (list.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                  child: Text(
                                      "No inward records found for this period.")),
                            );
                          }

                          // Grouping Logic (Duplicated for rendering)
                          final Map<String, Map<String, dynamic>> grouped = {};

                          for (var item in list) {
                            final name = item.materialName ?? 'Unknown';
                            final weight = item.totalWeight;
                            final count = item.bagCount.toDouble();
                            final size = item.bagSize;

                            if (!grouped.containsKey(name)) {
                              grouped[name] = {
                                'total_weight': 0.0,
                                'total_count': 0.0,
                                'sizes': <double, Map<String, double>>{},
                                'unit': item.materialUnit ?? ''
                              };
                            }

                            grouped[name]!['total_weight'] += weight;
                            grouped[name]!['total_count'] += count;

                            final sizes = grouped[name]!['sizes']
                                as Map<double, Map<String, double>>;
                            if (!sizes.containsKey(size)) {
                              sizes[size] = {'count': 0.0, 'weight': 0.0};
                            }
                            sizes[size]!['count'] =
                                (sizes[size]!['count'] ?? 0) + count;
                            sizes[size]!['weight'] =
                                (sizes[size]!['weight'] ?? 0) + weight;
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
                              final totalWeight =
                                  group['total_weight'] as double;
                              final totalCount = group['total_count'] as double;
                              final unit = 'packs';
                              final sizes = group['sizes']
                                  as Map<double, Map<String, double>>;

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
                                      totalWeight, totalCount, unit, sizes),
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
                                              '${totalWeight.toStringAsFixed(1)} kg ($totalCount $unit)',
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

  Widget _buildExportButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _handleExport(context),
      icon: const Icon(Icons.download, size: 18),
      label: const Text('Export Report'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  Future<void> _handleExport(BuildContext context) async {
    final config = await showDialog<ExportConfig>(
      context: context,
      builder: (c) => const ExportDialog(
          title: 'Export Inward Summary', showScopeSelector: true),
    );

    if (config == null) return;

    DateTime start;
    DateTime end;

    if (config.scope == ExportScope.day) {
      start = config.date!;
      end = config.date!;
    } else if (config.scope == ExportScope.month) {
      start = config.date!;
      end = DateTime(start.year, start.month + 1, 0);
    } else if (config.scope == ExportScope.week) {
      start = app_date_utils.DateUtils.getStartOfWeek(config.date!);
      end = app_date_utils.DateUtils.getEndOfWeek(config.date!);
    } else {
      if (config.customRange == null) return;
      start = config.customRange!.start;
      end = config.customRange!.end;
    }

    try {
      final list = await InwardRepository.getByDateRange(start, end);

      if (list.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No data found for selected period')));
        }
        return;
      }

      // Group Data
      final Map<String, Map<String, dynamic>> grouped = {};
      for (var item in list) {
        final name = item.materialName ?? 'Unknown';
        final weight = item.totalWeight;
        final count = item.bagCount.toDouble();
        final size = item.bagSize;

        if (!grouped.containsKey(name)) {
          grouped[name] = {'sizes': <double, Map<String, double>>{}};
        }

        final sizes =
            grouped[name]!['sizes'] as Map<double, Map<String, double>>;
        if (!sizes.containsKey(size)) {
          sizes[size] = {'count': 0.0, 'weight': 0.0};
        }
        sizes[size]!['count'] = (sizes[size]!['count'] ?? 0) + count;
        sizes[size]!['weight'] = (sizes[size]!['weight'] ?? 0) + weight;
      }

      // Build Rows
      final List<List<dynamic>> rows = [];
      for (var name in grouped.keys) {
        final sizes =
            grouped[name]!['sizes'] as Map<double, Map<String, double>>;
        for (var size in sizes.keys) {
          final stats = sizes[size]!;
          rows.add([
            name,
            size,
            stats['count']!.toStringAsFixed(0),
            stats['weight']!.toStringAsFixed(1)
          ]);
        }
      }

      final headers = [
        'Material Name',
        'Pack Size (kg)',
        'Count',
        'Weight (kg)'
      ];
      final title =
          'Inward Summary (${app_date_utils.DateUtils.formatDate(start)} - ${app_date_utils.DateUtils.formatDate(end)})';

      String? path;
      if (config.format == ExportFormat.excel) {
        path = await ExportService().exportToExcel(
          title: title,
          headers: headers,
          data: rows,
        );
      } else {
        path = await ExportService().exportToPdf(
          title: title,
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  // ... (dialog logic remains)

  // ... (build helpers remain)

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

  void _showDetailDialog(BuildContext context, String name, double totalWeight,
      double totalCount, String unit, Map<double, Map<String, double>> sizes) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Details for $name'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total Weight: ${totalWeight.toStringAsFixed(2)} kg'),
              Text('Total Count: ${totalCount.toStringAsFixed(0)} $unit'),
              const Divider(),
              const Text('By Pack Size:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...sizes.entries.map((e) {
                final size = e.key;
                final qty = e.value['count'] as double;
                final weight = e.value['weight'] as double;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                      '$size kg: ${qty.toStringAsFixed(0)} packs (${weight.toStringAsFixed(1)} kg)'),
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
