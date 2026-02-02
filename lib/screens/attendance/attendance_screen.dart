import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../main/tally_page_wrapper.dart';
import '../../utils/date_utils.dart' as app_date_utils;
import '../../database/repositories/attendance_repository.dart';
import '../../database/repositories/worker_repository.dart';
import '../../models/attendance.dart';
import '../../models/worker.dart';
import '../../providers/global_providers.dart';
import '../../services/export_service.dart';
import '../../widgets/export_dialog.dart';

// --- DATA PROVIDERS ---
final attendanceListProvider =
    FutureProvider.family<List<Attendance>, DateTime>((ref, date) async {
  return await AttendanceRepository.getByDate(date);
});

final labourersProvider = FutureProvider<List<Worker>>((ref) async {
  return await WorkerRepository.getByType(WorkerType.labour);
});

// --- LOCAL DATA MODEL FOR REGISTER ---
enum RegisterStatus { present, halfDay, absent }

class TimeInputData {
  String hh;
  String mm;
  String period; // "AM" or "PM"

  TimeInputData({this.hh = '', this.mm = '', this.period = 'AM'});

  static TimeInputData? fromString(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      final dt = DateFormat.jm().parse(timeStr);
      final hh = DateFormat('hh').format(dt);
      final mm = DateFormat('mm').format(dt);
      final a = DateFormat('a').format(dt);
      return TimeInputData(hh: hh, mm: mm, period: a);
    } catch (_) {
      try {
        final dt = DateFormat("HH:mm").parse(timeStr);
        final hh = DateFormat('hh').format(dt);
        final mm = DateFormat('mm').format(dt);
        final a = DateFormat('a').format(dt);
        return TimeInputData(hh: hh, mm: mm, period: a);
      } catch (e) {
        return TimeInputData();
      }
    }
  }

  String toStringFormatted() {
    if (hh.isEmpty || mm.isEmpty) return '';
    return "$hh:$mm $period";
  }
}

class RegisterRow {
  final Worker worker;
  int? attendanceId;
  RegisterStatus status;

  TimeInputData timeIn;
  TimeInputData timeOut;

  RegisterRow({
    required this.worker,
    this.attendanceId,
    this.status = RegisterStatus.absent,
    TimeInputData? initialTimeIn,
    TimeInputData? initialTimeOut,
  })  : timeIn = initialTimeIn ?? TimeInputData(),
        timeOut = initialTimeOut ?? TimeInputData();
}

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  // State
  bool _isLoading = true;
  bool _isSaving = false;
  List<RegisterRow> _rows = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadData());
  }

  // Effect to reload when date changes
  void _loadData() async {
    final selectedDate = ref.read(selectedDateProvider);

    setState(() {
      _isLoading = true;
      _error = null;
      _rows = [];
    });

    try {
      final workers = await WorkerRepository.getByType(WorkerType.labour);
      final attendance = await AttendanceRepository.getByDate(selectedDate);

      final newRows = <RegisterRow>[];

      for (var worker in workers) {
        final record =
            attendance.where((a) => a.workerId == worker.id).firstOrNull;

        RegisterStatus status = record?.status == AttendanceStatus.fullDay
            ? RegisterStatus.present
            : (record?.status == AttendanceStatus.halfDay
                ? RegisterStatus.halfDay
                : RegisterStatus.absent);

        // If no record, default to absent
        if (record == null) status = RegisterStatus.absent;

        TimeInputData? tIn;
        TimeInputData? tOut;

        if (record != null) {
          tIn = TimeInputData.fromString(record.timeIn);
          tOut = TimeInputData.fromString(record.timeOut);
        }

        newRows.add(RegisterRow(
          worker: worker,
          attendanceId: record?.id,
          status: status,
          initialTimeIn: tIn,
          initialTimeOut: tOut,
        ));
      }

      if (mounted) {
        setState(() {
          _rows = newRows;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedDateProvider, (previous, next) {
      if (previous != next) {
        _loadData();
      }
    });

    final total = _rows.length;
    final present = _rows
        .where((r) =>
            r.status == RegisterStatus.present ||
            r.status == RegisterStatus.halfDay)
        .length;
    final absent = _rows.where((r) => r.status == RegisterStatus.absent).length;

    return TallyPageWrapper(
      title: 'Attendance Register',
      child: Column(
        children: [
          // 1. Stats Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                _buildStatCard(context, "Total Workers", total.toString()),
                const SizedBox(width: 24),
                _buildStatCard(context, "Present", present.toString(),
                    color: Colors.green),
                const SizedBox(width: 24),
                _buildStatCard(context, "Absent", absent.toString(),
                    color: Colors.red),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveAll,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_isSaving ? "Saving..." : "Save Register"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _handleExport,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text("Export"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ),

          // 2. Data List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text("Error: $_error",
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)))
                    : _buildRegisterList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value,
      {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border:
            Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w300,
                  color:
                      color ?? Theme.of(context).textTheme.bodyLarge?.color)),
        ],
      ),
    );
  }

  Widget _buildRegisterList() {
    if (_rows.isEmpty) {
      return Center(
          child: Text("No workers found.",
              style: TextStyle(color: Theme.of(context).hintColor)));
    }

    return ListView.builder(
      itemCount: _rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return SizedBox(height: 50, child: _buildListHeader());
        final row = _rows[index - 1];
        return SizedBox(
            key: ValueKey(row.worker.id),
            height: 60,
            child: _buildListRow(row)); // Standard height
      },
    );
  }

  Widget _buildListHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).canvasColor,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: const Row(
        children: [
          Expanded(
              flex: 3,
              child: Text("Worker Name",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
              flex: 4,
              child: Text("Status",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
              flex: 2,
              child: Text("Time In",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
              flex: 2,
              child: Text("Time Out",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildListRow(RegisterRow row) {
    bool isAbsent = row.status == RegisterStatus.absent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.5),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          // Name
          Expanded(
            flex: 3,
            child: Text(
              row.worker.name,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
            ),
          ),

          // Status Toggle
          Expanded(
            flex: 4,
            child: Row(
              children: [
                _buildStatusChip(
                    row, RegisterStatus.present, "Present", Colors.green),
                const SizedBox(width: 8),
                _buildStatusChip(
                    row, RegisterStatus.halfDay, "Half Day", Colors.orange),
                const SizedBox(width: 8),
                _buildStatusChip(
                    row, RegisterStatus.absent, "Absent", Colors.red),
              ],
            ),
          ),

          // Time In
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: InlineTimeInput(
                data: row.timeIn,
                enabled: !isAbsent,
              ),
            ),
          ),

          // Time Out
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: InlineTimeInput(
                data: row.timeOut,
                enabled: !isAbsent,
              ),
            ),
          ),

          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
      RegisterRow row, RegisterStatus status, String label, Color color) {
    final isSelected = row.status == status;
    return InkWell(
      onTap: () {
        setState(() {
          row.status = status;
          if (status == RegisterStatus.present && row.timeIn.hh.isEmpty) {
            row.timeIn = TimeInputData(hh: '09', mm: '00', period: 'AM');
          }
          if (status == RegisterStatus.halfDay && row.timeIn.hh.isEmpty) {
            row.timeIn = TimeInputData(hh: '09', mm: '00', period: 'AM');
          }
          if (status == RegisterStatus.absent) {
            row.timeIn = TimeInputData();
            row.timeOut = TimeInputData();
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
              color: isSelected ? color : Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? color : Theme.of(context).hintColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    try {
      final date = ref.read(selectedDateProvider);

      for (var row in _rows) {
        if (row.status == RegisterStatus.absent) {
          if (row.attendanceId != null) {
            await AttendanceRepository.delete(row.attendanceId!);
            row.attendanceId = null;
          }
        } else {
          String? timeInStr = row.timeIn.toStringFormatted();
          String? timeOutStr = row.timeOut.toStringFormatted();

          final attendance = Attendance(
            id: row.attendanceId,
            workerId: row.worker.id!,
            date: date,
            status: row.status == RegisterStatus.present
                ? AttendanceStatus.fullDay
                : AttendanceStatus.halfDay,
            timeIn: timeInStr.isEmpty ? null : timeInStr,
            timeOut: timeOutStr.isEmpty ? null : timeOutStr,
          );

          if (row.attendanceId != null) {
            await AttendanceRepository.update(attendance);
          } else {
            final newId = await AttendanceRepository.insert(attendance);
            row.attendanceId = newId;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text("Attendance Register Saved"),
              backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Error saving: $e"),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

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
      if (config.customRange == null) return;
      start = config.customRange!.start;
      end = config.customRange!.end;
    }

    try {
      final data = await AttendanceRepository.getByDateRange(start, end);
      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('No attendance records found for selected period')));
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
      if (config.format == ExportFormat.excel)
        path = await ExportService()
            .exportToExcel(title: title, headers: headers, data: rows);
      else
        path = await ExportService()
            .exportToPdf(title: title, headers: headers, data: rows);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Report saved to: $path'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error));
    }
  }
}

// --- CUSTOM INLINE TIME INPUT WIDGET (UNIFIED - HORIZONTAL TOGGLE) ---
class InlineTimeInput extends StatefulWidget {
  final TimeInputData data;
  final bool enabled;

  const InlineTimeInput({super.key, required this.data, this.enabled = true});

  @override
  State<InlineTimeInput> createState() => _InlineTimeInputState();
}

class _InlineTimeInputState extends State<InlineTimeInput> {
  late TextEditingController _hhCtrl;
  late TextEditingController _mmCtrl;
  late FocusNode _hhFocus;
  late FocusNode _mmFocus;

  @override
  void initState() {
    super.initState();
    _hhCtrl = TextEditingController(text: widget.data.hh);
    _mmCtrl = TextEditingController(text: widget.data.mm);
    _hhFocus = FocusNode();
    _mmFocus = FocusNode();

    _hhCtrl.addListener(() {
      widget.data.hh = _hhCtrl.text;
      if (_hhCtrl.text.length == 2 && int.tryParse(_hhCtrl.text) != null) {
        _mmFocus.requestFocus();
      }
    });

    _mmCtrl.addListener(() {
      widget.data.mm = _mmCtrl.text;
    });

    _hhFocus.addListener(() => setState(() {}));
    _mmFocus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(InlineTimeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data) {
      if (_hhCtrl.text != widget.data.hh) _hhCtrl.text = widget.data.hh;
      if (_mmCtrl.text != widget.data.mm) _mmCtrl.text = widget.data.mm;
    }
  }

  @override
  void dispose() {
    _hhCtrl.dispose();
    _mmCtrl.dispose();
    _hhFocus.dispose();
    _mmFocus.dispose();
    super.dispose();
  }

  void _setPeriod(String period) {
    if (!widget.enabled) return;
    setState(() {
      widget.data.period = period;
    });
  }

  @override
  Widget build(BuildContext context) {
    // LAYOUT: [ HH : MM ] (Spacer) [ AM PM Toggle ]
    const double height = 40;
    final bool isFocused = _hhFocus.hasFocus || _mmFocus.hasFocus;

    // Theme Colors
    final Color borderColor =
        isFocused ? AppColors.primaryBlue : Theme.of(context).dividerColor;
    final Color bgColor = widget.enabled
        ? Theme.of(context).cardColor
        : Theme.of(context).disabledColor.withOpacity(0.05);

    if (!widget.enabled) {
      return Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.5)),
        ),
        child:
            Text("-", style: TextStyle(color: Theme.of(context).disabledColor)),
      );
    }

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: isFocused ? 1.5 : 1.0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        // mainAxisSize: MainAxisSize.min, // ALLOW TO EXPAND
        children: [
          // --- TIME SECTION [ HH : MM ] ---
          Row(
            children: [
              // HH
              SizedBox(
                width: 24,
                child: TextField(
                  controller: _hhCtrl,
                  focusNode: _hhFocus,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  maxLength: 2,
                  cursorColor: AppColors.primaryBlue,
                  decoration: const InputDecoration(
                    filled: false,
                    counterText: "",
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: "HH",
                    hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Text(":",
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ),

              // MM
              SizedBox(
                width: 24,
                child: TextField(
                  controller: _mmCtrl,
                  focusNode: _mmFocus,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  maxLength: 2,
                  cursorColor: AppColors.primaryBlue,
                  decoration: const InputDecoration(
                    filled: false,
                    counterText: "",
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: "MM",
                    hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),

          const Spacer(), // PUSH TO RIGHT

          // --- HORIZONTAL AM/PM TOGGLE ---
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).disabledColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                _buildToggleOption(context, "AM"),
                _buildToggleOption(context, "PM"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption(BuildContext context, String label) {
    final bool isSelected = widget.data.period == label;
    final activeColor = AppColors.primaryBlue;
    final activeText = Colors.white;
    final inactiveText = Theme.of(context).hintColor;

    return InkWell(
      onTap: () => _setPeriod(label),
      canRequestFocus: true, // Participate in tab traversal
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? activeText : inactiveText,
          ),
        ),
      ),
    );
  }
}
