import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart' as app_date_utils;
import '../../database/repositories/attendance_repository.dart';
import '../../database/repositories/worker_repository.dart';
import '../../models/attendance.dart';
import '../../models/worker.dart';
import '../../providers/global_providers.dart';
import '../../widgets/status_badge.dart';
import '../../services/export_service.dart';
import '../../widgets/export_dialog.dart';

final attendanceListProvider =
    FutureProvider.family<List<Attendance>, DateTime>((ref, date) async {
  return await AttendanceRepository.getByDate(date);
});

final labourersProvider = FutureProvider<List<Worker>>((ref) async {
  return await WorkerRepository.getByType(WorkerType.labour);
});

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  int? _editingId;
  Worker? _selectedWorker;
  AttendanceStatus? _selectedStatus;
  final TextEditingController _timeInHourController = TextEditingController();
  final TextEditingController _timeInMinuteController = TextEditingController();
  DayPeriod _timeInPeriod = DayPeriod.am;

  final TextEditingController _timeOutHourController = TextEditingController();
  final TextEditingController _timeOutMinuteController =
      TextEditingController();
  DayPeriod _timeOutPeriod = DayPeriod.pm;

  @override
  void dispose() {
    _timeInHourController.dispose();
    _timeInMinuteController.dispose();
    _timeOutHourController.dispose();
    _timeOutMinuteController.dispose();
    super.dispose();
  }

  bool _isSubmitting = false;
  // ... (state variables)

  Future<void> _handleExport() async {
    final config = await showDialog<ExportConfig>(
      context: context,
      builder: (c) => const ExportDialog(title: 'Export Attendance'),
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
      // Custom
      if (config.customRange == null) return;
      start = config.customRange!.start;
      end = config.customRange!.end;
    }

    try {
      final data = await AttendanceRepository.getByDateRange(start, end);

      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('No attendance records found for selected period')),
          );
        }
        return;
      }

      final headers = ['Date', 'Worker Name', 'Status', 'Time In', 'Time Out'];
      final rows = data
          .map((e) => [
                app_date_utils.DateUtils.formatDate(e.date),
                e.workerName ?? 'Unknown',
                e.status.displayName,
                e.timeIn ?? '-',
                e.timeOut ?? '-'
              ])
          .toList();

      final title =
          'Attendance Report (${app_date_utils.DateUtils.formatDate(start)} - ${app_date_utils.DateUtils.formatDate(end)})';

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

      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report saved to: $path'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final attendanceAsync = ref.watch(attendanceListProvider(selectedDate));
    final labourersAsync = ref.watch(labourersProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Main Header
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance',
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mark and track daily worker attendance',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
                const Spacer(),

                // Export Button
                IconButton(
                  onPressed: _handleExport,
                  icon: const Icon(Icons.download),
                  tooltip: 'Export Report',
                  style: IconButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkSurfaceVariant
                            : AppColors.lightSurfaceVariant,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 12),

                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.lightSurfaceVariant,
                    borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 16,
                          color: Theme.of(context).textTheme.bodyMedium?.color),
                      const SizedBox(width: 8),
                      Text(
                        app_date_utils.DateUtils.formatDate(selectedDate),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT PANEL: Entry Form (Flex 4)
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.only(left: 32, right: 24, bottom: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _editingId == null
                                  ? 'Mark Attendance'
                                  : 'Edit Attendance',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontSize: 18),
                            ),
                            if (_editingId != null) const Spacer(),
                            if (_editingId != null)
                              TextButton.icon(
                                onPressed: _cancelEdit,
                                icon: const Icon(Icons.close, size: 16),
                                label: const Text('Cancel Edit'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Worker Dropdown
                        labourersAsync.when(
                          data: (workers) {
                            if (workers.isEmpty) {
                              return InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Select Worker',
                                  border: OutlineInputBorder(),
                                  helperText:
                                      'Add workers in Settings > Workers',
                                ),
                                child: Text(
                                  'No workers available',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.color),
                                ),
                              );
                            }

                            return DropdownButtonFormField<Worker>(
                              value: _selectedWorker,
                              decoration: const InputDecoration(
                                labelText: 'Select Worker',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              items: workers.map((worker) {
                                return DropdownMenuItem(
                                  value: worker,
                                  child: Text(worker.name),
                                );
                              }).toList(),
                              onChanged: (worker) {
                                setState(() => _selectedWorker = worker);
                              },
                            );
                          },
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => const Text('Error loading workers',
                              style: TextStyle(color: AppColors.error)),
                        ),

                        const SizedBox(height: 24),

                        // Status Radio Buttons
                        Text(
                          'Status',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatusRadio(
                                  AttendanceStatus.fullDay, 'Full Day'),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildStatusRadio(
                                  AttendanceStatus.halfDay, 'Half Day'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Time In Input
                        _buildTimeInput(
                          label: 'Time In',
                          hourController: _timeInHourController,
                          minuteController: _timeInMinuteController,
                          period: _timeInPeriod,
                          onPeriodChanged: (val) =>
                              setState(() => _timeInPeriod = val),
                        ),

                        const SizedBox(height: 24),

                        // Time Out Input
                        _buildTimeInput(
                          label: 'Time Out (Optional)',
                          hourController: _timeOutHourController,
                          minuteController: _timeOutMinuteController,
                          period: _timeOutPeriod,
                          onPeriodChanged: (val) =>
                              setState(() => _timeOutPeriod = val),
                          isOptional: true,
                          onClear: () {
                            _timeOutHourController.clear();
                            _timeOutMinuteController.clear();
                          },
                        ),

                        const SizedBox(height: 32),

                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _selectedWorker == null ||
                                    _selectedStatus == null ||
                                    _timeInHourController.text.isEmpty ||
                                    _isSubmitting
                                ? null
                                : _markAttendance,
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Icon(_editingId == null
                                    ? Icons.check
                                    : Icons.save),
                            label: Text(_isSubmitting
                                ? (_editingId == null
                                    ? 'Marking...'
                                    : 'Updating...')
                                : (_editingId == null
                                    ? 'Mark Attendance'
                                    : 'Update Attendance')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _editingId == null
                                  ? AppColors.success
                                  : AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: (_editingId == null
                                      ? AppColors.success
                                      : AppColors.primaryBlue)
                                  .withOpacity(0.5),
                              disabledForegroundColor:
                                  Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Vertical Divider
                Container(
                  width: 1,
                  color: Theme.of(context).dividerColor.withOpacity(0.2),
                ),

                // RIGHT PANEL: Log (Flex 6)
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 32, 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Log Header
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "Today's Attendance Log",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontSize: 18),
                            ),
                          ),
                          Divider(
                              height: 1, color: Theme.of(context).dividerColor),

                          Expanded(
                            child: attendanceAsync.when(
                              data: (attendanceList) {
                                if (attendanceList.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.event_note,
                                            size: 48,
                                            color: Theme.of(context)
                                                .hintColor
                                                .withOpacity(0.3)),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No attendance marked today',
                                          style: TextStyle(
                                              color:
                                                  Theme.of(context).hintColor),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: ListView.separated(
                                    itemCount: attendanceList.length,
                                    separatorBuilder: (c, i) => Divider(
                                        height: 1,
                                        indent: 0,
                                        endIndent: 0,
                                        color: Theme.of(context).dividerColor),
                                    itemBuilder: (context, index) {
                                      final attendance = attendanceList[index];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        child: Row(
                                          children: [
                                            // Worker Info
                                            Expanded(
                                              flex: 2,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    attendance.workerName ??
                                                        'Unknown',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 14),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  StatusBadge(
                                                    label: attendance
                                                        .status.displayName,
                                                    type: attendance.status ==
                                                            AttendanceStatus
                                                                .fullDay
                                                        ? StatusType.success
                                                        : StatusType.warning,
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Time In
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Time In',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Theme.of(context)
                                                            .hintColor),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    attendance.timeIn ?? '-',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w500),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Time Out
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Time Out',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Theme.of(context)
                                                            .hintColor),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    attendance.timeOut ?? '-',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w500),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Edit Button
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18),
                                              onPressed: () =>
                                                  _editAttendance(attendance),
                                              tooltip: 'Edit',
                                              color: AppColors.primaryBlue,
                                            ),

                                            // Delete Button
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18),
                                              onPressed: () =>
                                                  _deleteAttendance(attendance),
                                              tooltip: 'Delete',
                                              color: AppColors.error,
                                            ),

                                            const SizedBox(width: 8),

                                            // Action Button
                                            if (attendance.timeOut == null)
                                              TextButton.icon(
                                                onPressed: () =>
                                                    _updateTimeOut(attendance),
                                                icon: const Icon(Icons.logout,
                                                    size: 16),
                                                label: const Text('Mark Out'),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.primaryBlue,
                                                ),
                                              )
                                            else
                                              const StatusBadge(
                                                  label: 'Completed',
                                                  type: StatusType.neutral),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                              loading: () => const Center(
                                  child: CircularProgressIndicator()),
                              error: (error, stack) => Center(
                                child: Text('Error: $error',
                                    style: const TextStyle(
                                        color: AppColors.error)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRadio(AttendanceStatus value, String label) {
    final isSelected = _selectedStatus == value;
    return InkWell(
      onTap: () => setState(() => _selectedStatus = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryBlue.withOpacity(0.1)
              : Colors.transparent,
          border: Border.all(
            color: isSelected
                ? AppColors.primaryBlue
                : Theme.of(context).dividerColor,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radio<AttendanceStatus>(
              value: value,
              groupValue: _selectedStatus,
              onChanged: (val) {
                if (val != null) setState(() => _selectedStatus = val);
              },
              activeColor: AppColors.primaryBlue,
            ),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeInput({
    required String label,
    required TextEditingController hourController,
    required TextEditingController minuteController,
    required DayPeriod period,
    required ValueChanged<DayPeriod> onPeriodChanged,
    bool isOptional = false,
    VoidCallback? onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            if (isOptional &&
                onClear != null &&
                (hourController.text.isNotEmpty ||
                    minuteController.text.isNotEmpty))
              InkWell(
                onTap: onClear,
                child: Text(
                  'Clear',
                  style: TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Hour
            SizedBox(
              width: 70,
              child: TextFormField(
                controller: hourController,
                keyboardType: TextInputType.number,
                maxLength: 2,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: 'HH',
                  counterText: '',
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                ),
                onChanged: (val) {
                  if (val.length == 2) {
                    FocusScope.of(context).nextFocus();
                  }
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(':',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            // Minute
            SizedBox(
              width: 70,
              child: TextFormField(
                controller: minuteController,
                keyboardType: TextInputType.number,
                maxLength: 2,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: 'MM',
                  counterText: '',
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // AM/PM Toggle
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPeriodButton(
                      'AM', DayPeriod.am, period, onPeriodChanged),
                  Container(
                      width: 1,
                      height: 32,
                      color: Theme.of(context).dividerColor),
                  _buildPeriodButton(
                      'PM', DayPeriod.pm, period, onPeriodChanged),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPeriodButton(String text, DayPeriod value, DayPeriod groupValue,
      ValueChanged<DayPeriod> onChanged) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected
            ? AppColors.primaryBlue.withOpacity(0.1)
            : Colors.transparent,
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? AppColors.primaryBlue : null,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _markAttendance() async {
    if (_selectedWorker == null) return;

    setState(() => _isSubmitting = true);

    try {
      final selectedDate = ref.read(selectedDateProvider);

      String timeInStr = '';
      if (_timeInHourController.text.isNotEmpty &&
          _timeInMinuteController.text.isNotEmpty) {
        final h = int.tryParse(_timeInHourController.text) ?? 0;
        final m = int.tryParse(_timeInMinuteController.text) ?? 0;
        final tod = TimeOfDay(
            hour: _timeInPeriod == DayPeriod.pm && h != 12
                ? h + 12
                : (_timeInPeriod == DayPeriod.am && h == 12 ? 0 : h),
            minute: m);
        timeInStr = tod.format(context);
      }

      String? timeOutStr;
      if (_timeOutHourController.text.isNotEmpty &&
          _timeOutMinuteController.text.isNotEmpty) {
        final h = int.tryParse(_timeOutHourController.text) ?? 0;
        final m = int.tryParse(_timeOutMinuteController.text) ?? 0;
        final tod = TimeOfDay(
            hour: _timeOutPeriod == DayPeriod.pm && h != 12
                ? h + 12
                : (_timeOutPeriod == DayPeriod.am && h == 12 ? 0 : h),
            minute: m);
        timeOutStr = tod.format(context);
      }

      final attendance = Attendance(
        id: _editingId,
        workerId: _selectedWorker!.id!,
        date: selectedDate,
        status: _selectedStatus!,
        timeIn: timeInStr,
        timeOut: timeOutStr,
      );

      if (_editingId != null) {
        // UPDATE mode
        await AttendanceRepository.update(attendance);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Attendance updated successfully'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // INSERT mode
        await AttendanceRepository.insert(attendance);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Attendance marked successfully'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      ref.invalidate(attendanceListProvider(selectedDate));
      ref.invalidate(dashboardStatsProvider);

      if (mounted) {
        // Reset form to defaults
        _clearForm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _updateTimeOut(Attendance attendance) async {
    final timeOut = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogBackgroundColor: Theme.of(context).cardColor,
          ),
          child: child!,
        );
      },
    );

    if (timeOut != null && attendance.id != null) {
      try {
        final updatedAttendance = attendance.copyWith(
          timeOut: timeOut.format(context),
        );
        await AttendanceRepository.update(updatedAttendance);

        // Refresh the list
        final selectedDate = ref.read(selectedDateProvider);
        ref.invalidate(attendanceListProvider(selectedDate));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Time out updated'),
                backgroundColor: AppColors.success),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _editAttendance(Attendance attendance) async {
    // Find the worker from the list
    final labourers = await ref.read(labourersProvider.future);
    final worker = labourers.firstWhere(
      (w) => w.id == attendance.workerId,
      orElse: () => Worker(name: 'Unknown', type: WorkerType.labour),
    );

    if (attendance.timeIn != null) {
      // 09:30 AM
      // This parsing heavily depends on format.
      // Assuming "9:30 AM" or "09:30 AM" format from TimeOfDay.format(context) en_US usually
      // Ideally we parse properly. But for now let's try to be robust.
      // Actually simpler: just parse simple 12h format if possible or standard TimeOfDay
      // If the string is just HH:mm AM/PM

      // Let's rely on standard flutter TimeOfDay parsing from string if we had a helper, but we don't.
      // Let's implement manually based on "h:mm a" likely format

      // Heuristic parse:
      try {
        // Remove NBSP just in case
        String t = attendance.timeIn!.replaceAll('\u202F', ' ').trim();
        final spaceParts = t.split(' ');
        if (spaceParts.length == 2) {
          final timeParts = spaceParts[0].split(':');
          final period = spaceParts[1]; // AM or PM
          if (timeParts.length == 2) {
            _timeInHourController.text = timeParts[0];
            _timeInMinuteController.text = timeParts[1];
            _timeInPeriod =
                period.toUpperCase() == 'PM' ? DayPeriod.pm : DayPeriod.am;
          }
        }
      } catch (_) {}
    } else {
      _timeInHourController.clear();
      _timeInMinuteController.clear();
      _timeInPeriod = DayPeriod.am;
    }

    if (attendance.timeOut != null) {
      try {
        String t = attendance.timeOut!.replaceAll('\u202F', ' ').trim();
        final spaceParts = t.split(' ');
        if (spaceParts.length == 2) {
          final timeParts = spaceParts[0].split(':');
          final period = spaceParts[1]; // AM or PM
          if (timeParts.length == 2) {
            _timeOutHourController.text = timeParts[0];
            _timeOutMinuteController.text = timeParts[1];
            _timeOutPeriod =
                period.toUpperCase() == 'PM' ? DayPeriod.pm : DayPeriod.am;
          }
        }
      } catch (_) {}
    } else {
      _timeOutHourController.clear();
      _timeOutMinuteController.clear();
      _timeOutPeriod = DayPeriod.pm;
    }

    setState(() {
      _editingId = attendance.id;
      _selectedWorker = worker.id != null ? worker : null;
      _selectedStatus = attendance.status;
    });
  }

  void _cancelEdit() {
    _clearForm();
  }

  Future<void> _deleteAttendance(Attendance attendance) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Attendance'),
        content: Text(
            'Are you sure you want to delete attendance for ${attendance.workerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && attendance.id != null) {
      try {
        await AttendanceRepository.delete(attendance.id!);

        // If deleting the item currently being edited, clear the form
        if (_editingId == attendance.id) {
          _clearForm();
        }

        final selectedDate = ref.read(selectedDateProvider);
        ref.invalidate(attendanceListProvider(selectedDate));
        ref.invalidate(dashboardStatsProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Attendance deleted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _selectedWorker = null;
      _selectedStatus = null;
      _timeInHourController.clear();
      _timeInMinuteController.clear();
      _timeInPeriod = DayPeriod.am;
      _timeOutHourController.clear();
      _timeOutMinuteController.clear();
      _timeOutPeriod = DayPeriod.pm;
    });
  }
}
