import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart' as app_date_utils;
import '../../utils/validators.dart';
import '../../database/repositories/trip_repository.dart';
import '../../models/trip.dart';
import '../../providers/global_providers.dart';
import '../../widgets/status_badge.dart';
import '../../services/export_service.dart';
import '../../widgets/export_dialog.dart';

final tripsListProvider =
    FutureProvider.family<List<Trip>, DateTime>((ref, date) async {
  return await TripRepository.getByDate(date);
});

class LogisticsScreen extends ConsumerStatefulWidget {
  const LogisticsScreen({super.key});

  @override
  ConsumerState<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends ConsumerState<LogisticsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _destinationController = TextEditingController();
  final _startKmController = TextEditingController();
  final _endKmController = TextEditingController();
  final _fuelCostController = TextEditingController();
  final _otherCostController = TextEditingController();

  int? _editingId;
  int? _selectedVehicleId;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  @override
  void dispose() {
    _destinationController.dispose();
    _startKmController.dispose();
    _endKmController.dispose();
    _fuelCostController.dispose();
    _otherCostController.dispose();
    super.dispose();
  }

  Future<void> _selectTime(bool isStart) async {
    final initialTime = isStart
        ? (_startTime ?? TimeOfDay.now())
        : (_endTime ?? TimeOfDay.now());

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return 'Select Time';
    return time.format(context);
  }
  // ... (existing state variables)

  Future<void> _handleExport() async {
    final config = await showDialog<ExportConfig>(
      context: context,
      builder: (c) => const ExportDialog(title: 'Export Trip Logs'),
    );

    if (config == null) return;

    DateTime start;
    DateTime end;

    if (config.scope == ExportScope.day) {
      start = config.date!;
      end = config.date!;
    } else if (config.scope == ExportScope.week) {
      // Calculate week range (Monday to Sunday)
      final date = config.date!;
      start = date.subtract(Duration(days: date.weekday - 1));
      end = start.add(const Duration(days: 6));
    } else if (config.scope == ExportScope.month) {
      start = config.date!;
      end = DateTime(start.year, start.month + 1, 0);
    } else {
      start = config.customRange!.start;
      end = config.customRange!.end;
    }

    try {
      final data = await TripRepository.getByDateRange(start, end);

      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No trip records found for selected period')),
          );
        }
        return;
      }

      final headers = [
        'Date',
        'Vehicle',
        'Reg. Number',
        'Destination',
        'Start Km',
        'End Km',
        'Distance',
        'Time',
        'Fuel Cost',
        'Other Cost'
      ];

      final rows = data
          .map((e) => [
                app_date_utils.DateUtils.formatDate(e.date),
                e.vehicleName ?? 'Unknown',
                e.vehicleRegistrationNumber ?? '-',
                e.destination,
                e.startKm.toString(),
                e.endKm.toString(),
                e.totalDistance.toStringAsFixed(1),
                '${e.startTime ?? ''} - ${e.endTime ?? ''}',
                e.fuelCost.toStringAsFixed(0),
                e.otherCost.toStringAsFixed(0),
              ])
          .toList();

      final title =
          'Logistics Report (${app_date_utils.DateUtils.formatDate(start)} - ${app_date_utils.DateUtils.formatDate(end)})';

      if (config.format == ExportFormat.excel) {
        await ExportService().exportToExcel(
          title: title,
          headers: headers,
          data: rows,
        );
      } else {
        await ExportService().exportToPdf(
          title: title,
          headers: headers,
          data: rows,
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
    final tripsAsync = ref.watch(tripsListProvider(selectedDate));
    final vehiclesAsync = ref.watch(vehiclesProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Header (Unchanged mostly)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Logistics Management',
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage vehicle trips, odometer readings, and costs',
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _editingId == null
                                    ? 'New Trip Entry'
                                    : 'Edit Trip Entry',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontSize: 18),
                              ),
                              if (_editingId != null) const Spacer(),
                              if (_editingId != null)
                                TextButton.icon(
                                  onPressed: _clearForm,
                                  icon: const Icon(Icons.close, size: 16),
                                  label: const Text('Cancel Edit'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Vehicle Dropdown
                          vehiclesAsync.when(
                            data: (vehicles) => DropdownButtonFormField<int>(
                              value: _selectedVehicleId,
                              decoration: const InputDecoration(
                                labelText: 'Vehicle *',
                                hintText: 'Select vehicle...',
                                border: OutlineInputBorder(),
                              ),
                              items: vehicles.map((vehicle) {
                                return DropdownMenuItem<int>(
                                  value: vehicle['id'] as int?,
                                  child: Text(
                                      '${vehicle['name']} (${vehicle['registration_number']})'),
                                );
                              }).toList(),
                              onChanged: _onVehicleSelected,
                              validator: (value) => value == null
                                  ? 'Please select a vehicle'
                                  : null,
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (_, __) =>
                                const Text('Error loading vehicles'),
                          ),

                          const SizedBox(height: 20),

                          // Destination
                          TextFormField(
                            controller: _destinationController,
                            decoration: const InputDecoration(
                              labelText: 'Destination *',
                              helperText: 'Delivery/Trip location',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => Validators.required(value,
                                fieldName: 'Destination'),
                          ),

                          const SizedBox(height: 20),

                          // Odometer Readings
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _startKmController,
                                  decoration: const InputDecoration(
                                    labelText: 'Start Odometer (km)',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) =>
                                      Validators.nonNegativeNumber(value,
                                          fieldName: 'Start Km'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _endKmController,
                                  decoration: const InputDecoration(
                                    labelText: 'End Odometer (km)',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  // Not strictly required if trip is in progress
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Times
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => _selectTime(true),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Start Time',
                                      border: OutlineInputBorder(),
                                      suffixIcon: Icon(Icons.access_time),
                                    ),
                                    child: Text(_formatTime(_startTime)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: InkWell(
                                  onTap: () => _selectTime(false),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'End Time',
                                      border: OutlineInputBorder(),
                                      suffixIcon: Icon(Icons.access_time),
                                    ),
                                    child: Text(_formatTime(_endTime)),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Costs
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _fuelCostController,
                                  decoration: const InputDecoration(
                                    labelText: 'Fuel Cost',
                                    prefixText: '₹ ',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _otherCostController,
                                  decoration: const InputDecoration(
                                    labelText: 'Other Costs',
                                    prefixText: '₹ ',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _submitEntry,
                              icon: Icon(_editingId == null
                                  ? Icons.local_shipping
                                  : Icons.save),
                              label: Text(_editingId == null
                                  ? 'Log Trip'
                                  : 'Update Trip'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _editingId == null
                                    ? AppColors.primaryBlue
                                    : AppColors.success,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
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
                            child: Row(
                              children: [
                                Text(
                                  'Trips Log (Today)',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontSize: 18),
                                ),
                                const Spacer(),
                                StatusBadge(
                                  label:
                                      '${tripsAsync.value?.length ?? 0} Trips',
                                  type: StatusType.neutral,
                                ),
                              ],
                            ),
                          ),
                          Divider(
                              height: 1, color: Theme.of(context).dividerColor),

                          // Table
                          Expanded(
                            child: tripsAsync.when(
                              data: (trips) {
                                if (trips.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.directions_bus_outlined,
                                            size: 48,
                                            color: Theme.of(context)
                                                .hintColor
                                                .withOpacity(0.3)),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No trips recorded today',
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
                                    itemCount: trips.length,
                                    separatorBuilder: (c, i) => Divider(
                                        height: 1,
                                        indent: 0,
                                        endIndent: 0,
                                        color: Theme.of(context).dividerColor),
                                    itemBuilder: (context, index) {
                                      final trip = trips[index];
                                      final totalCost = trip.totalCost;
                                      final distance = trip.totalDistance;

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        child: Row(
                                          children: [
                                            // Vehicle Info
                                            Expanded(
                                              flex: 2,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    trip.vehicleName ??
                                                        'Unknown',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    trip.vehicleRegistrationNumber ??
                                                        '-',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Theme.of(context)
                                                            .hintColor),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Destination & Time
                                            Expanded(
                                              flex: 3,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    trip.destination,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        fontSize: 13),
                                                  ),
                                                  Text(
                                                    '${trip.startTime ?? '-'} to ${trip.endTime ?? '-'}',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Theme.of(context)
                                                            .hintColor),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Stats (Km / Cost)
                                            Expanded(
                                              flex: 2,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    '${distance.toStringAsFixed(1)} km',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                  if (totalCost > 0)
                                                    Text(
                                                      '₹${totalCost.toStringAsFixed(0)}',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              AppColors.error),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18),
                                              onPressed: () => _editTrip(trip),
                                              tooltip: 'Edit',
                                              color: AppColors.primaryBlue,
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18),
                                              onPressed: () =>
                                                  _deleteTrip(trip),
                                              tooltip: 'Delete',
                                              color: AppColors.error,
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                              loading: () => const Center(
                                  child: CircularProgressIndicator()),
                              error: (e, s) => Center(child: Text('Error: $e')),
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

  Future<void> _submitEntry() async {
    if (!_formKey.currentState!.validate() || _selectedVehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final selectedDate = ref.read(selectedDateProvider);
      final startKm = double.tryParse(_startKmController.text) ?? 0;
      final endKm = double.tryParse(_endKmController.text) ?? 0;
      final fuelCost = double.tryParse(_fuelCostController.text) ?? 0;
      final otherCost = double.tryParse(_otherCostController.text) ?? 0;

      // Validation
      if (fuelCost < 0 || otherCost < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Costs cannot be negative'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (endKm > 0 && startKm > endKm) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Start odometer cannot be greater than End odometer'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final trip = Trip(
        id: _editingId,
        vehicleId: _selectedVehicleId!,
        date: selectedDate,
        destination: _destinationController.text.trim(),
        startKm: startKm,
        endKm: endKm,
        startTime: _startTime != null
            ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
            : null,
        endTime: _endTime != null
            ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}'
            : null,
        fuelCost: fuelCost,
        otherCost: otherCost,
      );

      if (_editingId != null) {
        await TripRepository.update(trip);
      } else {
        await TripRepository.insert(trip);
      }

      ref.invalidate(tripsListProvider(selectedDate));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_editingId != null
                ? 'Trip updated successfully'
                : 'Trip logged successfully'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Reset form
        _clearForm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _editTrip(Trip trip) {
    setState(() {
      _editingId = trip.id;
      _selectedVehicleId = trip.vehicleId;
      _destinationController.text = trip.destination;
      _startKmController.text =
          trip.startKm == 0 ? '' : trip.startKm.toString();
      _endKmController.text = trip.endKm == 0 ? '' : trip.endKm.toString();
      _fuelCostController.text =
          trip.fuelCost == 0 ? '' : trip.fuelCost.toString();
      _otherCostController.text =
          trip.otherCost == 0 ? '' : trip.otherCost.toString();

      if (trip.startTime != null && trip.startTime!.contains(':')) {
        final parts = trip.startTime!.split(':');
        _startTime =
            TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } else {
        _startTime = null;
      }

      if (trip.endTime != null && trip.endTime!.contains(':')) {
        final parts = trip.endTime!.split(':');
        _endTime =
            TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } else {
        _endTime = null;
      }
    });
  }

  Future<void> _deleteTrip(Trip trip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip'),
        content: Text('Delete trip for ${trip.vehicleName}?'),
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

    if (confirm == true && trip.id != null) {
      await TripRepository.delete(trip.id!);

      if (_editingId == trip.id) {
        _clearForm();
      }

      final selectedDate = ref.read(selectedDateProvider);
      ref.invalidate(tripsListProvider(selectedDate));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Trip deleted'),
              backgroundColor: AppColors.success),
        );
      }
    }
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _selectedVehicleId = null;
      _destinationController.clear();
      _startKmController.clear();
      _endKmController.clear();
      _fuelCostController.clear();
      _otherCostController.clear();
      _startTime = null;
      _endTime = null;
    });
  }

  Future<void> _onVehicleSelected(int? id) async {
    setState(() => _selectedVehicleId = id);

    // Only prefill if creating a new entry and a vehicle is selected
    if (_editingId == null && id != null) {
      final lastTrip = await TripRepository.getLastTripForVehicle(id);
      if (lastTrip != null && mounted) {
        setState(() {
          _startKmController.text = lastTrip.endKm.toString();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Start Odometer set to ${lastTrip.endKm} (from last trip)'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
