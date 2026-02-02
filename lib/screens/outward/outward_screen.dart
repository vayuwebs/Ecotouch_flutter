import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/outward.dart';
import '../../providers/global_providers.dart';

import '../../widgets/status_badge.dart';
import '../main/tally_page_wrapper.dart';
import '../../providers/outward_providers.dart';
import 'outward_entry_screen.dart';

class OutwardScreen extends ConsumerStatefulWidget {
  const OutwardScreen({super.key});

  @override
  ConsumerState<OutwardScreen> createState() => _OutwardScreenState();
}

class _OutwardScreenState extends ConsumerState<OutwardScreen> {
  void _navigateToEntry({Outward? outward}) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => OutwardEntryScreen(outward: outward),
      ),
    )
        .then((_) {
      // Refresh list on return
      ref.invalidate(outwardListProvider(ref.read(selectedDateProvider)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final outwardAsync = ref.watch(outwardListProvider(selectedDate));

    return TallyPageWrapper(
      title: 'Outward Logistics',
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
              child: outwardAsync.when(
                data: (outwardList) {
                  if (outwardList.isEmpty) {
                    return const Center(
                        child: Text('No shipments recorded today.'));
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
                              label: Text('Product',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Bag Size',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Bags',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Total',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Notes',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Status',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: outwardList.map((outward) {
                          return DataRow(
                            onSelectChanged: (_) =>
                                _navigateToEntry(outward: outward),
                            cells: [
                              DataCell(Text(outward.productName ?? 'Unknown',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text('${outward.bagSize}')),
                              DataCell(Text('${outward.bagCount}')),
                              DataCell(
                                  Text(outward.totalWeight.toStringAsFixed(2))),
                              DataCell(Text(outward.notes ?? '')),
                              const DataCell(StatusBadge(
                                  label: 'Shipped', type: StatusType.success)),
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
