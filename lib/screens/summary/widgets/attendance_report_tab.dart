import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../theme/app_colors.dart';
import '../../../../database/database_service.dart';
import '../../../../utils/date_utils.dart' as app_date_utils;
import '../../../../providers/summary_providers.dart';
import '../../../../widgets/export_dialog.dart';
import '../../../../services/export_service.dart';

// Provider for attendance data
final attendanceReportProvider =
    FutureProvider.family<List<Map<String, dynamic>>, DateTimeRange>(
        (ref, range) async {
  final startStr = app_date_utils.DateUtils.formatDateForDatabase(range.start);
  final endStr = app_date_utils.DateUtils.formatDateForDatabase(range.end);

  // Get all workers first (assuming we have a workers table, or get distinct workers from attendance)
  // For now, getting distinct workers from attendance to ensure we show active ones
  // Ideal: SELECT * FROM workers

  // Join with workers table to get worker_name
  final records = await DatabaseService.rawQuery('''
    SELECT 
      a.worker_id,
      w.name as worker_name,
      a.date,
      a.status
    FROM attendance a
    JOIN workers w ON a.worker_id = w.id
    WHERE a.date BETWEEN ? AND ?
    ORDER BY w.name, a.date
  ''', [startStr, endStr]);

  return records;
});

class AttendanceReportTab extends ConsumerWidget {
  const AttendanceReportTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateRange = ref.watch(reportDateRangeProvider);
    final viewMode = ref.watch(reportViewModeProvider);
    final attendanceAsync = ref.watch(attendanceReportProvider(dateRange));

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
              const Spacer(),
              _buildExportButton(context),
            ],
          ),
        ),

        // Matrix
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: attendanceAsync.when(
              data: (data) => _buildAttendanceMatrix(context, data, dateRange),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error: $e')),
            ),
          ),
        ),
      ],
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
          value: currentMode == ReportViewMode.daily
              ? ReportViewMode.weekly
              : currentMode,
          icon: Icon(Icons.keyboard_arrow_down,
              size: 16, color: Theme.of(context).iconTheme.color),
          style: Theme.of(context).textTheme.bodyMedium,
          onChanged: (ReportViewMode? newValue) {
            if (newValue != null) {
              ref.read(reportViewModeProvider.notifier).state = newValue;
            }
          },
          items: ReportViewMode.values
              .where((m) => m != ReportViewMode.daily)
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
    // 1. Show Dialog to get config
    final config = await showDialog<ExportConfig>(
      context: context,
      builder: (c) => const ExportDialog(title: 'Export Attendance Matrix'),
    );

    if (config == null) return;

    // 2. Determine Date Range
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
      // 3. Fetch Data (Flat List)
      // We need raw data to pivot. Using the repo method.
      // Note: We need to import AttendanceRepository at the top of file if not present,
      // or use the provider if accessible.
      // Since this is a stateless widget, we can use the provider container or just static repo call.
      // Importing repo is cleaner here.

      // We need to fetch ALL attendance for this range.
      // Assuming AttendanceRepository is available (it was analyzed earlier).
      // We might need to add the import if it's missing.

      final records = await DatabaseService.rawQuery('''
        SELECT 
          a.date,
          w.name as worker_name,
          a.status
        FROM attendance a
        JOIN workers w ON a.worker_id = w.id
        WHERE a.date BETWEEN ? AND ?
        ORDER BY a.date ASC, w.id ASC
      ''', [
        app_date_utils.DateUtils.formatDateForDatabase(start),
        app_date_utils.DateUtils.formatDateForDatabase(end)
      ]);

      if (records.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No data found for selected period')));
        }
        return;
      }

      // 4. Pivot Data (Date x Worker)

      // Get all unique workers and dates
      final Set<String> workerNames = {};
      final Set<String> dates = {};
      // Map: Date -> WorkerName -> Status
      final Map<String, Map<String, String>> matrix = {};

      for (var row in records) {
        final date = (row['date'] as String).split('T')[0];
        final worker = row['worker_name'] as String;
        final status = row['status'] as String;

        workerNames.add(worker);
        dates.add(date);

        if (!matrix.containsKey(date)) {
          matrix[date] = {};
        }
        matrix[date]![worker] = status;
      }

      final sortedDates = dates.toList()..sort();
      final sortedWorkers = workerNames.toList()..sort();

      // 5. Prepare Headers
      final List<String> headers = [
        'Date',
        ...sortedWorkers,
        'Total Attendance'
      ];

      // 6. Prepare Rows
      final List<List<dynamic>> rows = [];

      for (var date in sortedDates) {
        final List<dynamic> row = [];
        row.add(app_date_utils.DateUtils.formatDate(
            DateTime.parse(date))); // Date Column

        int presentCount = 0;
        int halfDayCount = 0;

        for (var worker in sortedWorkers) {
          final status = matrix[date]?[worker];
          if (status == 'full_day') {
            row.add('Present');
            presentCount++;
          } else if (status == 'half_day') {
            row.add('Half Day');
            halfDayCount++;
          } else {
            row.add('-'); // Absent/Not Marked
          }
        }

        // Summary Column
        final List<String> summaryParts = [];
        if (presentCount > 0) summaryParts.add('Present:$presentCount');
        if (halfDayCount > 0) summaryParts.add('Half Day:$halfDayCount');
        row.add(summaryParts.isEmpty ? '-' : summaryParts.join(' '));

        rows.add(row);
      }

      // 7. Export
      final title =
          'Attendance Matrix (${app_date_utils.DateUtils.formatDate(start)} - ${app_date_utils.DateUtils.formatDate(end)})';

      String? path;
      if (config.format == ExportFormat.excel) {
        path = await ExportService().exportToExcel(
            title: title,
            headers: headers,
            data: rows,
            sheetName: 'Attendance Matrix');
      } else {
        path = await ExportService()
            .exportToPdf(title: title, headers: headers, data: rows);
      }

      if (context.mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Exported to $path'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  Widget _buildAttendanceMatrix(BuildContext context,
      List<Map<String, dynamic>> rawData, DateTimeRange range) {
    // Process data into a worker-date map
    final Map<int, String> workerNames = {};
    final Map<int, int> presentCounts = {};
    final Map<int, int> halfDayCounts = {};

    for (var row in rawData) {
      final workerId = row['worker_id'] as int;
      final workerName = row['worker_name'] as String? ?? 'Unknown';
      final status = row['status'] as String;

      workerNames[workerId] = workerName;

      if (status == 'full_day') {
        presentCounts[workerId] = (presentCounts[workerId] ?? 0) + 1;
      } else if (status == 'half_day') {
        halfDayCounts[workerId] = (halfDayCounts[workerId] ?? 0) + 1;
      }
    }

    // Calculate total days in range
    final totalDays = range.end.difference(range.start).inDays + 1;

    return Column(
      children: [
        // Header Row
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 0),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: Theme.of(context).dividerColor.withOpacity(0.1))),
          ),
          child: Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text('WORKER NAME',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withOpacity(0.7))),
                  )),
              Expanded(
                  flex: 1,
                  child: Center(
                      child: Text('PRESENT',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withOpacity(0.7))))),
              Expanded(
                  flex: 1,
                  child: Center(
                      child: Text('HALF-DAY',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withOpacity(0.7))))),
              Expanded(
                  flex: 1,
                  child: Center(
                      child: Text('ABSENT',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withOpacity(0.7))))),
              Expanded(
                  flex: 2, // Slightly wider for "Total Present"
                  child: Center(
                      child: Text('TOTAL PRESENT',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withOpacity(0.7))))),
            ],
          ),
        ),

        // List
        Expanded(
          child: ListView.builder(
            itemCount: workerNames.length,
            itemBuilder: (context, index) {
              final workerId = workerNames.keys.elementAt(index);
              final name = workerNames[workerId]!;
              final present = presentCounts[workerId] ?? 0;
              final halfDay = halfDayCounts[workerId] ?? 0;
              // Absent = Total Possible Days - (Present + Half Day)
              // Note: This logic assumes everyday is a working day.
              final attendedDays = present +
                  halfDay; // Treat half day as attendance for "days shown up"? Or strict time?
              // User request: "total present(present+half day)". So that's the last column.
              // Absent should probably correspond to days NOT in status.
              final absent = totalDays - (present + halfDay);
              // Note: If absent is negative (e.g. data outside range? shouldn't happen due to SQL), clamp to 0.
              final safeAbsent = absent < 0 ? 0 : absent;

              final totalPresentScore =
                  present + halfDay; // "total present(present+half day)"

              return Container(
                height: 50,
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: Theme.of(context)
                              .dividerColor
                              .withOpacity(0.05))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: Theme.of(context)
                                  .dividerColor
                                  .withOpacity(0.1),
                              child: Text(
                                name.substring(0, 2).toUpperCase(),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Center(
                        child: Text('$present',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.success)),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Center(
                        child: Text('$halfDay',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning)),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Center(
                        child: Text('$safeAbsent',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.error)),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .dividerColor
                                .withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$totalPresentScore',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Footer (Active Workers count)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(
                    color: Theme.of(context).dividerColor.withOpacity(0.1))),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TOTAL WORKERS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withOpacity(0.7))),
                  const SizedBox(height: 4),
                  Text('${workerNames.length}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              // We could add aggregates for total present days etc if needed
            ],
          ),
        ),
      ],
    );
  }
}
