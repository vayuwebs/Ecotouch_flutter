import 'package:flutter/material.dart';
import '../main/tally_page_wrapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/production.dart';
import '../../providers/global_providers.dart';
import '../../utils/date_utils.dart' as app_date_utils;
import 'production_entry_screen.dart';

import '../../providers/production_providers.dart';

class ProductionScreen extends ConsumerStatefulWidget {
  const ProductionScreen({super.key});

  @override
  ConsumerState<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends ConsumerState<ProductionScreen> {
  void _navigateToEntry({Production? production}) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => ProductionEntryScreen(production: production),
      ),
    )
        .then((_) {
      // Refresh list on return
      ref.invalidate(productionListProvider(ref.read(selectedDateProvider)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final productionAsync = ref.watch(productionListProvider(selectedDate));

    return TallyPageWrapper(
      title: 'Manufacturing Orders',
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
                  'Manufacturing Orders',
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
              child: productionAsync.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(
                        child: Text(
                            'No manufacturing orders found for this date.'));
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
                              label: Text('Product',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Next Activity',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Source',
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold))), // Workers?
                          DataColumn(
                              label: Text('Quantity',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('State',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: list.map((p) {
                          return DataRow(
                            onSelectChanged: (_) =>
                                _navigateToEntry(production: p),
                            cells: [
                              DataCell(Text('BP-${p.id}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF714B67)))),
                              DataCell(Text(
                                  app_date_utils.DateUtils.formatDate(p.date))),
                              DataCell(Text(p.productName ?? 'Unknown',
                                  style: const TextStyle(
                                      color: Color(0xFF008784)))), // Odoo teal
                              const DataCell(Icon(Icons.access_time,
                                  size: 16, color: Colors.grey)), // Placeholder
                              const DataCell(Text('')), // Placeholder source
                              DataCell(
                                  Text(p.totalQuantity.toStringAsFixed(2))),
                              DataCell(Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('Done',
                                    style: TextStyle(
                                        color: Colors.green.shade800,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              )),
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
