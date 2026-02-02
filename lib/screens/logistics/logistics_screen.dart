import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/global_providers.dart';
import '../../models/trip.dart';
import '../../theme/app_colors.dart';

import '../../utils/date_utils.dart' as app_date_utils;

import '../../services/export_service.dart';
import '../../widgets/export_dialog.dart';
import '../../database/repositories/trip_repository.dart';
import '../main/tally_page_wrapper.dart';
import '../../providers/logistics_providers.dart';
import 'logistics_entry_screen.dart';

class LogisticsScreen extends ConsumerStatefulWidget {
  const LogisticsScreen({super.key});

  @override
  ConsumerState<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends ConsumerState<LogisticsScreen> {
  void _navigateToEntry({Trip? trip}) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => LogisticsEntryScreen(trip: trip),
      ),
    )
        .then((_) {
      // Refresh list on return
      ref.invalidate(tripsListProvider(ref.read(selectedDateProvider)));
    });
  }

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

  Future<void> _deleteTrip(Trip trip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip?'),
        content:
            const Text('Are you sure you want to delete this trip record?'),
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

    if (confirm == true) {
      await TripRepository.delete(trip.id!);
      ref.invalidate(tripsListProvider(ref.read(selectedDateProvider)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final tripsAsync = ref.watch(tripsListProvider(selectedDate));

    return TallyPageWrapper(
      title: 'Logistics Management',
      child: Column(
        children: [
          // Header Actions
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: () => _navigateToEntry(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF714B67),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text('New'),
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
              ],
            ),
          ),

          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(4),
              ),
              child: tripsAsync.when(
                data: (trips) {
                  if (trips.isEmpty) {
                    return const Center(
                        child: Text('No trips recorded today.',
                            style: TextStyle(color: Colors.grey)));
                  }

                  return SingleChildScrollView(
                    child: SizedBox(
                      width: double.infinity,
                      child: DataTable(
                        headingRowColor:
                            MaterialStateProperty.all(Colors.grey.shade50),
                        columns: const [
                          DataColumn(
                              label: Text('Vehicle',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Destination',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Distance',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Time',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Cost',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Actions',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: trips.map((trip) {
                          return DataRow(
                              onSelectChanged: (_) =>
                                  _navigateToEntry(trip: trip),
                              cells: [
                                DataCell(Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(trip.vehicleName ?? 'Unknown',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(trip.vehicleRegistrationNumber ?? '-',
                                        style: const TextStyle(
                                            fontSize: 10, color: Colors.grey)),
                                  ],
                                )),
                                DataCell(Text(trip.destination)),
                                DataCell(Text(
                                    '${trip.totalDistance.toStringAsFixed(1)} km')),
                                DataCell(Text(
                                    '${trip.startTime ?? '-'} - ${trip.endTime ?? '-'}')),
                                DataCell(Text(
                                    '₹${trip.totalCost.toStringAsFixed(0)}')),
                                DataCell(Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: AppColors.error, size: 18),
                                      onPressed: () => _deleteTrip(trip),
                                    )
                                  ],
                                )),
                              ]);
                        }).toList(),
                      ),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text('Error: $e')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
