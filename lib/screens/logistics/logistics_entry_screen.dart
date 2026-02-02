import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';
import '../../database/repositories/trip_repository.dart';
import '../../models/trip.dart';
import '../../providers/global_providers.dart';
import '../../providers/logistics_providers.dart';

class LogisticsEntryScreen extends ConsumerStatefulWidget {
  final Trip? trip;

  const LogisticsEntryScreen({super.key, this.trip});

  @override
  ConsumerState<LogisticsEntryScreen> createState() =>
      _LogisticsEntryScreenState();
}

class _LogisticsEntryScreenState extends ConsumerState<LogisticsEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _destinationController = TextEditingController();
  final _startKmController = TextEditingController();
  final _endKmController = TextEditingController();
  final _fuelCostController = TextEditingController();
  final _otherCostController = TextEditingController();

  int? _selectedVehicleId;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  @override
  void initState() {
    super.initState();
    if (widget.trip != null) {
      _loadExistingTrip();
    }
  }

  void _loadExistingTrip() {
    final trip = widget.trip!;
    _selectedVehicleId = trip.vehicleId;
    _destinationController.text = trip.destination;
    _startKmController.text = trip.startKm == 0 ? '' : trip.startKm.toString();
    _endKmController.text = trip.endKm == 0 ? '' : trip.endKm.toString();
    _fuelCostController.text =
        trip.fuelCost == 0 ? '' : trip.fuelCost.toString();
    _otherCostController.text =
        trip.otherCost == 0 ? '' : trip.otherCost.toString();

    if (trip.startTime != null && trip.startTime!.contains(':')) {
      final parts = trip.startTime!.split(':');
      _startTime =
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    if (trip.endTime != null && trip.endTime!.contains(':')) {
      final parts = trip.endTime!.split(':');
      _endTime =
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
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

  @override
  void dispose() {
    _destinationController.dispose();
    _startKmController.dispose();
    _endKmController.dispose();
    _fuelCostController.dispose();
    _otherCostController.dispose();
    super.dispose();
  }

  Future<void> _submitEntry() async {
    if (!_formKey.currentState!.validate() || _selectedVehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields'),
          backgroundColor: AppColors.error,
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
            ),
          );
        }
        return;
      }

      final trip = Trip(
        id: widget.trip?.id,
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

      if (widget.trip != null) {
        await TripRepository.update(trip);
      } else {
        await TripRepository.insert(trip);
      }

      ref.invalidate(tripsListProvider(selectedDate));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.trip != null
                ? 'Trip updated successfully'
                : 'Trip logged successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesProvider);
    final selectedDate = ref.watch(selectedDateProvider);

    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(widget.trip == null ? 'New Trip Entry' : 'Edit Trip'),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: const CloseButton(color: Colors.black),
          titleTextStyle: const TextStyle(
              color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Text(
                  "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Header Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: Colors.grey.shade200))),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: _submitEntry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF714B67),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Confirm'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Discard')),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                          onChanged: (val) =>
                              setState(() => _selectedVehicleId = val),
                          validator: (value) =>
                              value == null ? 'Please select a vehicle' : null,
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) => const Text('Error loading vehicles'),
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
                    ],
                  ),
                ),
              ),
            ),
          ],
        ));
  }
}
