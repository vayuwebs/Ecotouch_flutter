import 'package:flutter/material.dart';
import '../main/tally_page_wrapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/global_providers.dart';
import '../../utils/date_utils.dart' as app_date_utils;
import '../../models/inward.dart';
import '../../providers/inward_providers.dart';
import 'inward_entry_screen.dart';

class InwardScreen extends ConsumerStatefulWidget {
  const InwardScreen({super.key});

  @override
  ConsumerState<InwardScreen> createState() => _InwardScreenState();
}

class _InwardScreenState extends ConsumerState<InwardScreen> {
  void _navigateToEntry({Inward? inward}) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => InwardEntryScreen(inward: inward),
      ),
    )
        .then((_) {
      // Refresh list on return
      ref.invalidate(inwardListProvider(ref.read(selectedDateProvider)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final inwardAsync = ref.watch(inwardListProvider(selectedDate));

    return TallyPageWrapper(
      title: 'Inward / Supply',
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
                const SizedBox(width: 16),
                Text(
                  'Raw Material Inward',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                // Search bar could go here
                SizedBox(
                  width: 250,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                )
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
              child: inwardAsync.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(
                        child: Text('No inward entries found for this date.'));
                  }

                  return SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SizedBox(
                      width: double.infinity,
                      child: DataTable(
                        headingRowColor:
                            MaterialStateProperty.all(Colors.grey.shade50),
                        columns: const [
                          DataColumn(
                              label: Text('Reference',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Date',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Material',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Pack Size',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Quantity (Bags)',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Total',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Notes',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: list.map((inward) {
                          return DataRow(
                            onSelectChanged: (_) =>
                                _navigateToEntry(inward: inward),
                            cells: [
                              DataCell(Text('IN-${inward.id}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF714B67)))),
                              DataCell(Text(app_date_utils.DateUtils.formatDate(
                                  inward.date))),
                              DataCell(Text(inward.materialName ?? 'Unknown',
                                  style: const TextStyle(
                                      color: Color(0xFF008784)))),
                              DataCell(Text('${inward.bagSize}')),
                              DataCell(Text('${inward.bagCount}')),
                              DataCell(
                                  Text(inward.totalWeight.toStringAsFixed(2))),
                              DataCell(Text(inward.notes ?? '')),
                            ],
                          );
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
