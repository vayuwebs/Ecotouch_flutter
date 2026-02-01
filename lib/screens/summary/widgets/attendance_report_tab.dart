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
    final Map<int, Map<String, String>> workerAttendance = {};
    final Map<int, String> workerNames = {};
    final Map<int, int> workerTotalPresent = {};

    for (var row in rawData) {
      final workerId = row['worker_id'] as int;
      final workerName = row['worker_name'] as String? ?? 'Unknown';
      final dateStr =
          (row['date'] as String).split('T')[0]; // Format: YYYY-MM-DD
      final status = row['status'] as String;

      workerNames[workerId] = workerName;

      if (!workerAttendance.containsKey(workerId)) {
        workerAttendance[workerId] = {};
        workerTotalPresent[workerId] = 0;
      }

      workerAttendance[workerId]![dateStr] = status;
      if (status == 'full_day') {
        workerTotalPresent[workerId] = (workerTotalPresent[workerId] ?? 0) + 1;
      }
      // Half day logic could be +0.5 if required
    }

    // Generate list of days in range
    final daysCount = range.end.difference(range.start).inDays + 1;
    final days = List.generate(
        daysCount, (index) => range.start.add(Duration(days: index)));

    // For large ranges (Monthly/Yearly), we might need to handle horizontal scrolling better
    // But for now, we'll try to fit or let it overflow if using scroll view?
    // Using SingleChildScrollView horizontally for the matrix part if needed.

    return Column(
      children: [
        // Header Row - Wrapped in ScrollView sync? simpler to just make the whole table scrollable horizontally
        // But headers need to stay fixed if optimizing. For simplicity now given requirements:
        // We will make the central part scrollable horizontally.

        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            trackVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 280.0 +
                    (days.length *
                        60.0), // Fixed width: 200(Name) + 80(Total) + days*60
                child: Column(
                  children: [
                    Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: Theme.of(context)
                                    .dividerColor
                                    .withOpacity(0.1))),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                              width: 200,
                              child: Padding(
                                padding: EdgeInsets.only(left: 24),
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('WORKER NAME',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold))),
                              )),
                          ...days.map((date) => SizedBox(
                                width: 60,
                                child: Center(
                                  child: Text(
                                    '${date.day}/${date.month.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.color
                                          ?.withOpacity(0.7),
                                    ),
                                  ),
                                ),
                              )),
                          const SizedBox(
                              width: 80,
                              child: Center(
                                  child: Text('TOTAL',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: workerNames.length,
                        itemBuilder: (context, index) {
                          final workerId = workerNames.keys.elementAt(index);
                          final name = workerNames[workerId]!;
                          final attendance = workerAttendance[workerId] ?? {};
                          final total = workerTotalPresent[workerId] ?? 0;

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
                                SizedBox(
                                  width: 200,
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
                                ...days.map((date) {
                                  final dateStr = app_date_utils.DateUtils
                                      .formatDateForDatabase(date);
                                  final status = attendance[dateStr];
                                  return SizedBox(
                                    width: 60,
                                    child: Center(
                                        child:
                                            _buildStatusBadge(context, status)),
                                  );
                                }),
                                SizedBox(
                                  width: 80,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .dividerColor
                                            .withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$total',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
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
                  ],
                ),
              ),
            ),
          ),
        ),

        // Footer (Active Workers count) - No Navigation
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
                  Text('TOTAL ACTIVE WORKERS',
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
              const SizedBox(width: 48),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AVG ATTENDANCE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withOpacity(0.7))),
                  const SizedBox(height: 4),
                  const Text('92.4%',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context, String? status) {
    if (status == null) {
      return Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        child:
            Text('—', style: TextStyle(color: Theme.of(context).disabledColor)),
      );
    }

    Color bgColor;
    Color textColor;
    String text;

    if (status == 'full_day') {
      bgColor = AppColors.success.withOpacity(0.1);
      textColor = AppColors.success;
      text = 'P';
    } else if (status == 'half_day') {
      bgColor = AppColors.warning.withOpacity(0.1);
      textColor = AppColors.warning;
      text = 'H';
    } else {
      bgColor = AppColors.error.withOpacity(0.1);
      textColor = AppColors.error;
      text = 'A';
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
