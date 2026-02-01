import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart' as app_date_utils;
import '../../providers/settings_providers.dart';
import '../../utils/validators.dart';
import '../../database/repositories/production_repository.dart';
import '../../database/repositories/worker_repository.dart';
import '../../models/production.dart';
import '../../models/product.dart';
import '../../models/worker.dart';
import '../../providers/global_providers.dart';
import '../../providers/inventory_providers.dart';
import '../../providers/summary_providers.dart';
import '../../services/export_service.dart';
import '../../services/stock_calculation_service.dart';
import '../../database/database_service.dart';
import '../../widgets/export_dialog.dart';
import '../../widgets/status_badge.dart';
import '../../models/stock_by_bag_size.dart';

final productionListProvider =
    FutureProvider.family<List<Production>, DateTime>((ref, date) async {
  return await ProductionRepository.getByDate(date);
});

class ProductionScreen extends ConsumerStatefulWidget {
  const ProductionScreen({super.key});

  @override
  ConsumerState<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends ConsumerState<ProductionScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _totalQuantityController = TextEditingController();
  final _batchesController = TextEditingController();
  final _notesController = TextEditingController();
  final _unitSizeController = TextEditingController();
  final _unitCountController =
      TextEditingController(); // For pieces/packs count

  // State
  int? _editingId;
  Product? _selectedProduct;
  List<int> _selectedWorkerIds = [];
  List<Map<String, dynamic>> _productBOM = [];
  List<StockByBagSize> _availableStock = [];
  Map<int, TextEditingController> _rawMaterialQuantityControllers = {};
  String? _convertedUnit;
  // Dynamic bag sizes for multi-bag production
  Map<int, double?> _selectedBagSizes = {};

  @override
  void dispose() {
    _totalQuantityController.dispose();
    _batchesController.dispose();
    _notesController.dispose();
    _unitSizeController.dispose();
    _unitCountController.dispose();
    for (var controller in _rawMaterialQuantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProductBOM(int productId) async {
    final recipe = await DatabaseService.rawQuery('''
      SELECT prm.raw_material_id, prm.quantity_ratio, rm.name as raw_material_name, rm.unit
      FROM product_raw_materials prm
      INNER JOIN raw_materials rm ON prm.raw_material_id = rm.id
      WHERE prm.product_id = ?
    ''', [productId]);

    setState(() {
      _productBOM = recipe.map((r) => Map<String, dynamic>.from(r)).toList();

      // Initialize controllers for manual override
      for (var item in _productBOM) {
        final id = item['raw_material_id'] as int;
        if (!_rawMaterialQuantityControllers.containsKey(id)) {
          _rawMaterialQuantityControllers[id] = TextEditingController();
        }
      }
    });

    _updateRawMaterialQuantities();
  }

  void _loadConvertedUnit(Product product) {
    // Placeholder unit logic
    setState(() {
      _convertedUnit = product.unit; // Or converted
    });
  }

  void _updateRawMaterialQuantities() {
    final batches = double.tryParse(_batchesController.text) ?? 0;

    for (var item in _productBOM) {
      final rawMaterialId = item['raw_material_id'] as int;
      final ratio = (item['quantity_ratio'] as num).toDouble();
      final totalRequired = ratio * batches;

      if (_rawMaterialQuantityControllers.containsKey(rawMaterialId)) {
        _rawMaterialQuantityControllers[rawMaterialId]!.text =
            totalRequired.toStringAsFixed(2);
      }
    }

    // _calculateTotalQuantity(); // Total no longer depends on batches
  }

  void _calculateTotalQuantity() {
    final unitCount = double.tryParse(_unitCountController.text) ?? 0;
    final unitSize = double.tryParse(_unitSizeController.text) ?? 1;
    final total = unitCount * unitSize;
    _totalQuantityController.text = total.toStringAsFixed(2);
  }

  Future<void> _handleExport() async {
    final config = await showDialog<ExportConfig>(
      context: context,
      builder: (c) => const ExportDialog(title: 'Export Production History'),
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
      // Custom range or fallback
      if (config.customRange == null) return;
      start = config.customRange!.start;
      end = config.customRange!.end;
    }

    try {
      final data = await ProductionRepository.getByDateRange(start, end);
      final workers = await WorkerRepository.getAll();
      final workerMap = {for (var w in workers) w.id: w.name};

      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('No production records found for selected period')),
          );
        }
        return;
      }

      final headers = [
        'Date',
        'Batch ID',
        'Product Name',
        'Pack Size',
        'Counts',
        'Total Qty',
        'Unit',
        'Workers'
      ];

      final rows = data.map((e) {
        final workerNames =
            e.workerIds?.map((id) => workerMap[id] ?? 'Unknown').join(', ') ??
                'None';

        return [
          app_date_utils.DateUtils.formatDate(e.date),
          'B-${e.id}',
          e.productName ?? 'Unknown',
          e.unitSize?.toString() ?? '-',
          e.unitCount?.toString() ?? e.batches.toString(),
          e.totalQuantity.toStringAsFixed(2),
          e.innerUnit ?? e.productUnit ?? '',
          workerNames
        ];
      }).toList();

      final title =
          'Production Report (${app_date_utils.DateUtils.formatDate(start)} - ${app_date_utils.DateUtils.formatDate(end)})';

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
    final productionAsync = ref.watch(productionListProvider(selectedDate));
    final productsAsync = ref.watch(productsProvider);
    final workersAsync = ref.watch(workersProvider);

    // Update local stock cache from provider
    final stockAsync = ref.watch(rawMaterialStockByBagSizeProvider);
    if (stockAsync.hasValue) {
      _availableStock = stockAsync.value!;
    }

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
                      'Batch Production Entry',
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Configure and initiate a new production run',
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
                                    ? 'New Batch Configuration'
                                    : 'Edit Batch Configuration',
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

                          // Product Selection
                          productsAsync.when(
                            data: (products) {
                              if (products.isEmpty)
                                return const Text('No products available');

                              return DropdownButtonFormField<Product>(
                                value: _selectedProduct,
                                decoration: const InputDecoration(
                                  labelText: 'Product SKU',
                                  hintText: 'Select product...',
                                  border: OutlineInputBorder(),
                                ),
                                items: products.map((product) {
                                  return DropdownMenuItem(
                                    value: product,
                                    child: Text(product.name),
                                  );
                                }).toList(),
                                onChanged: (product) {
                                  setState(() {
                                    _selectedProduct = product;
                                    _productBOM = [];
                                    _batchesController.clear();
                                    _totalQuantityController.clear();
                                    _convertedUnit = null;
                                  });
                                  if (product?.id != null) {
                                    _loadProductBOM(product!.id!);
                                    _loadConvertedUnit(product);
                                  }
                                },
                                validator: (value) => value == null
                                    ? 'Please select a product'
                                    : null,
                              );
                            },
                            loading: () => const LinearProgressIndicator(),
                            error: (_, __) =>
                                const Text('Error loading products'),
                          ),

                          const SizedBox(height: 20),

                          // Batches & Qty
                          // Batches
                          TextFormField(
                            controller: _batchesController,
                            decoration: const InputDecoration(
                              labelText: 'Number of Batches',
                              suffixText: 'Units',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) => Validators.positiveInteger(
                                value,
                                fieldName: 'Batches'),
                            onChanged: (_) => _updateRawMaterialQuantities(),
                          ),

                          const SizedBox(height: 16),

                          // Output Configuration
                          if (_selectedProduct?.unit != null &&
                              _selectedProduct!.unit!.isNotEmpty)
                            Consumer(builder: (context, ref, child) {
                              final conversionsAsync =
                                  ref.watch(unitConversionsProvider);

                              return conversionsAsync.when(
                                data: (conversions) {
                                  // Filter conversions for current product unit
                                  // Case-insensitive check for Source Unit (e.g. 'Bag')
                                  final relevantConversions = conversions
                                      .where((c) =>
                                          c.fromUnit.trim().toLowerCase() ==
                                          _selectedProduct!.unit!
                                              .trim()
                                              .toLowerCase())
                                      .toList();

                                  return Row(
                                    children: [
                                      Expanded(
                                        child: relevantConversions.isNotEmpty
                                            ? DropdownButtonFormField<double>(
                                                decoration: InputDecoration(
                                                  labelText:
                                                      'Size per ${_selectedProduct!.unit!}',
                                                  helperText: _convertedUnit !=
                                                          null
                                                      ? 'Unit size ($_convertedUnit)'
                                                      : 'Select standard size',
                                                  border:
                                                      const OutlineInputBorder(),
                                                ),
                                                value: double.tryParse(
                                                    _unitSizeController.text),
                                                items: relevantConversions
                                                    .map((c) {
                                                  return DropdownMenuItem<
                                                      double>(
                                                    value: c.conversionFactor,
                                                    child: Text(
                                                        '${c.conversionFactor} ${c.toUnit}'),
                                                  );
                                                }).toList(),
                                                onChanged: (value) {
                                                  if (value != null) {
                                                    setState(() {
                                                      _unitSizeController.text =
                                                          value.toString();
                                                      // Find the conversion to get the unit name
                                                      final selected =
                                                          relevantConversions
                                                              .firstWhere((c) =>
                                                                  c.conversionFactor ==
                                                                  value);
                                                      _convertedUnit =
                                                          selected.toUnit;
                                                    });
                                                    _calculateTotalQuantity();
                                                  }
                                                },
                                                validator: (value) =>
                                                    value == null
                                                        ? 'Select size'
                                                        : null,
                                              )
                                            : TextFormField(
                                                controller: _unitSizeController,
                                                decoration: InputDecoration(
                                                  labelText:
                                                      'Size per ${_selectedProduct!.unit!}', // e.g., Size per Pack
                                                  helperText: _convertedUnit !=
                                                          null
                                                      ? 'Unit size ($_convertedUnit)'
                                                      : 'Unit size',
                                                  border:
                                                      const OutlineInputBorder(),
                                                ),
                                                keyboardType:
                                                    TextInputType.number,
                                                onChanged: (_) =>
                                                    _calculateTotalQuantity(),
                                                validator: (value) =>
                                                    Validators.positiveNumber(
                                                        value,
                                                        fieldName: 'Unit Size'),
                                              ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _unitCountController,
                                          decoration: InputDecoration(
                                            labelText:
                                                'No. of ${_selectedProduct!.unit!}', // e.g., No. of Packs
                                            helperText: 'Count',
                                            border: const OutlineInputBorder(),
                                          ),
                                          keyboardType: TextInputType.number,
                                          onChanged: (_) =>
                                              _calculateTotalQuantity(),
                                          validator: (value) =>
                                              Validators.positiveNumber(value,
                                                  fieldName: 'Count'),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                                loading: () => const LinearProgressIndicator(),
                                error: (_, __) =>
                                    const Text('Error loading units'),
                              );
                            })
                          else
                            TextFormField(
                              controller: _totalQuantityController,
                              decoration: const InputDecoration(
                                labelText: 'Total Output',
                                suffixText: 'Qty',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) => Validators.positiveNumber(
                                  value,
                                  fieldName: 'Total Quantity'),
                            ),

                          // Display Total if using Units
                          if (_selectedProduct?.unit != null &&
                              _selectedProduct!.unit!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _totalQuantityController,
                                  builder: (context, value, child) {
                                    return Text(
                                      'Total Output: ${value.text.isEmpty ? '0' : value.text} ${_convertedUnit ?? _selectedProduct?.unit ?? ''}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primaryBlue),
                                    );
                                  },
                                ),
                              ),
                            ),

                          const SizedBox(height: 24),

                          // Workers Assignment
                          Text(
                            'Assign Shift Workers',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          workersAsync.when(
                            data: (workers) {
                              if (workers.isEmpty) {
                                return const Text('No active workers available',
                                    style: TextStyle(
                                        color: AppColors.textSecondary));
                              }

                              return Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.borderRadius),
                                  color: (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? AppColors.darkSurfaceVariant
                                          : AppColors.lightSurfaceVariant)
                                      .withOpacity(0.5),
                                ),
                                height: 150, // Reduced height for split view
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: workers.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final worker = workers[index];
                                    final isSelected =
                                        _selectedWorkerIds.contains(worker.id);
                                    return CheckboxListTile(
                                      value: isSelected,
                                      onChanged: (selected) {
                                        setState(() {
                                          if (selected == true) {
                                            _selectedWorkerIds.add(worker.id!);
                                          } else {
                                            _selectedWorkerIds
                                                .remove(worker.id);
                                          }
                                        });
                                      },
                                      title: Text(worker.name,
                                          style: const TextStyle(fontSize: 14)),
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      visualDensity: VisualDensity.compact,
                                    );
                                  },
                                ),
                              );
                            },
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (_, __) =>
                                const Text('Error loading workers'),
                          ),

                          const SizedBox(height: 24),

                          // Raw Material Requirements (Vertical Stack now)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? AppColors.darkSurfaceVariant
                                      : AppColors.lightSurfaceVariant)
                                  .withOpacity(0.3),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.borderRadius),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.science_outlined,
                                        color: AppColors.primaryBlue, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Raw Material Requirements',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (_productBOM.isEmpty)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Text(
                                        'Select a product first',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.color,
                                            fontSize: 13),
                                      ),
                                    ),
                                  )
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: _productBOM.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final item = _productBOM[index];
                                      final rawMaterialId =
                                          item['raw_material_id'] as int;
                                      final rawMaterialName =
                                          item['raw_material_name'] as String;
                                      final unit = item['unit'] as String;

                                      // Get stock options for this material
                                      final options = _availableStock
                                          .where((s) =>
                                              s.materialId == rawMaterialId)
                                          .toList();

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      rawMaterialName,
                                                      style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w500),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    // Bag Size Dropdown
                                                    if (options.isEmpty)
                                                      const Text(
                                                        'No stock available',
                                                        style: TextStyle(
                                                            color:
                                                                AppColors.error,
                                                            fontSize: 11),
                                                      )
                                                    else
                                                      DropdownButtonFormField<
                                                          double>(
                                                        value:
                                                            _selectedBagSizes[
                                                                rawMaterialId],
                                                        isDense: true,
                                                        decoration:
                                                            InputDecoration(
                                                          contentPadding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 8),
                                                          border: OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4)),
                                                          labelText:
                                                              'Source Batch',
                                                          labelStyle:
                                                              const TextStyle(
                                                                  fontSize: 11),
                                                        ),
                                                        items: options
                                                            .map((stock) {
                                                          return DropdownMenuItem<
                                                              double>(
                                                            value:
                                                                stock.bagSize,
                                                            child: Text(
                                                              '${stock.bagSize} $unit Pack (${stock.bagCount} avail)',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          12),
                                                            ),
                                                          );
                                                        }).toList(),
                                                        onChanged: (value) {
                                                          setState(() {
                                                            _selectedBagSizes[
                                                                    rawMaterialId] =
                                                                value;
                                                          });
                                                        },
                                                        validator: (value) =>
                                                            value == null
                                                                ? 'Select batch'
                                                                : null,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              SizedBox(
                                                width: 100,
                                                child: TextFormField(
                                                  controller:
                                                      _rawMaterialQuantityControllers[
                                                          rawMaterialId],
                                                  style: const TextStyle(
                                                      fontSize: 13),
                                                  decoration: InputDecoration(
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 8,
                                                            vertical: 12),
                                                    suffixText: unit,
                                                    labelText: 'Qty Used',
                                                    labelStyle: const TextStyle(
                                                        fontSize: 11),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                  ),
                                                  keyboardType:
                                                      TextInputType.number,
                                                  textAlign: TextAlign.end,
                                                  validator: (value) =>
                                                      Validators.positiveNumber(
                                                          value,
                                                          fieldName: 'Qty'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _submitEntry,
                              icon: Icon(_editingId == null
                                  ? Icons.add_circle_outline
                                  : Icons.save),
                              label: Text(_editingId == null
                                  ? 'Create Batch Entry'
                                  : 'Update Batch Entry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _editingId == null
                                    ? AppColors.primaryBlue
                                    : AppColors.success,
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.bold),
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
                                  "Today's Production Log",
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontSize: 18),
                                ),
                                const Spacer(),
                                SizedBox(
                                  width: 220,
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: 'Search batch...',
                                      prefixIcon:
                                          const Icon(Icons.search, size: 18),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 10, horizontal: 12),
                                      fillColor: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      filled: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppTheme.borderRadius),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(
                              height: 1, color: Theme.of(context).dividerColor),

                          Expanded(
                            child: productionAsync.when(
                              data: (productionList) {
                                if (productionList.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.assignment_outlined,
                                            size: 48,
                                            color: Theme.of(context)
                                                .hintColor
                                                .withOpacity(0.3)),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No production recorded today',
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
                                    itemCount: productionList.length,
                                    separatorBuilder: (c, i) => Divider(
                                        height: 1,
                                        indent: 0,
                                        endIndent: 0,
                                        color: Theme.of(context).dividerColor),
                                    itemBuilder: (context, index) {
                                      final production = productionList[index];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        child: Row(
                                          children: [
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '#B-${production.id}',
                                                  style: const TextStyle(
                                                      fontFamily: 'Monospace',
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13),
                                                ),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primaryBlue
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                    production.productName ??
                                                        'Unknown',
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors
                                                            .primaryBlue,
                                                        fontWeight:
                                                            FontWeight.w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 24),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                          '${production.totalQuantity} ${production.innerUnit ?? production.productUnit ?? 'Units'}',
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                          'in ${production.batches} batches',
                                                          style: TextStyle(
                                                              color: Theme.of(
                                                                      context)
                                                                  .hintColor,
                                                              fontSize: 12)),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.people,
                                                          size: 14,
                                                          color:
                                                              Theme.of(context)
                                                                  .hintColor),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '${production.workerIds?.length ?? 0} Workers',
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            color: Theme.of(
                                                                    context)
                                                                .hintColor),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                StatusBadge(
                                                    label: 'Completed',
                                                    type: StatusType.success),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.edit_outlined,
                                                          size: 18),
                                                      onPressed: () =>
                                                          _editProduction(
                                                              production),
                                                      tooltip: 'Edit',
                                                      color:
                                                          AppColors.primaryBlue,
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
                                                          _deleteProduction(
                                                              production),
                                                      tooltip: 'Delete',
                                                      color: AppColors.error,
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            )
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
    if (!_formKey.currentState!.validate() || _selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_selectedWorkerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please assign at least one worker'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final selectedDate = ref.read(selectedDateProvider);
      final batches = int.parse(_batchesController.text);
      final totalQuantity = double.parse(_totalQuantityController.text);

      double? unitSize;
      double? unitCount;
      if (_selectedProduct?.unit != null &&
          _selectedProduct!.unit!.isNotEmpty) {
        if (_unitSizeController.text.isNotEmpty &&
            _unitCountController.text.isNotEmpty) {
          unitSize = double.parse(_unitSizeController.text);
          unitCount = double.parse(_unitCountController.text);
        }
      }

      // Validate raw material stock availability
      if (_productBOM.isNotEmpty) {
        final currentStock =
            await StockCalculationService.calculateRawMaterialStock(
                selectedDate);

        for (final item in _productBOM) {
          final rawMaterialId = item['raw_material_id'] as int;
          final rawMaterialName = item['raw_material_name'] as String;
          final requiredQty = double.parse(
              _rawMaterialQuantityControllers[rawMaterialId]!.text);
          final availableQty = currentStock[rawMaterialId] ?? 0;

          if (availableQty < requiredQty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Insufficient stock for $rawMaterialName. Required: $requiredQty, Available: ${availableQty.toStringAsFixed(2)}',
                  ),
                  backgroundColor: AppColors.error,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            return;
          }
        }
      }

      final production = Production(
        id: _editingId,
        productId: _selectedProduct!.id!,
        date: selectedDate,
        batches: batches,
        totalQuantity: totalQuantity,
        unitSize: unitSize,
        unitCount: unitCount,
        workerIds: _selectedWorkerIds.toList(),
      );

      int productionId;
      if (_editingId != null) {
        // UPDATE MODE
        // Repository handles worker updates now
        await ProductionRepository.update(production);
        productionId = _editingId!;
      } else {
        // INSERT MODE
        // Use Repository instead of direct DB insert
        productionId = await ProductionRepository.insert(production);
      }

      // Repository handles worker associations now.
      // We only need to handle Raw Materials manually if Repository doesn't support them fully yet.
      // (Checking Repository: it handles workers, but NOT raw_materials in insert/update methods?
      //  Wait, let's check ProductionRepository code.)

      // Based on my view of ProductionRepository, it handles WORKERS but NOT raw_materials yet?
      // Correct. ProductionRepository.insert/update only deals with 'production' and 'production_workers'.
      // So we MUST keep the raw material logic below, but remove the worker logic.

      // ... removed worker insertion loop ...

      // Insert raw material usage
      for (final item in _productBOM) {
        final rawMaterialId = item['raw_material_id'] as int;
        final quantityUsed =
            double.parse(_rawMaterialQuantityControllers[rawMaterialId]!.text);
        final bagSize = _selectedBagSizes[rawMaterialId];

        await DatabaseService.insert('production_raw_materials', {
          'production_id': productionId,
          'raw_material_id': rawMaterialId,
          'quantity_used': quantityUsed,
          'bag_size': bagSize,
        });
      }

      print('DEBUG: Invalidating providers for date $selectedDate');
      ref.invalidate(productionListProvider(selectedDate));
      ref.invalidate(dashboardStatsProvider);

      // Invalidate stock providers to refresh stock levels
      ref.invalidate(rawMaterialStockProvider);
      ref.invalidate(productStockProvider);
      ref.invalidate(rawMaterialStockByBagSizeProvider);
      ref.invalidate(productStockByBagSizeProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_editingId != null
                ? 'Production batch updated successfully'
                : 'Production batch recorded successfully'),
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

  void _editProduction(Production production) async {
    // 1. Set basic fields
    setState(() {
      _editingId = production.id;
      _batchesController.text = production.batches.toString();
      _totalQuantityController.text = production.totalQuantity.toString();

      if (production.unitSize != null) {
        _unitSizeController.text = production.unitSize.toString();
      } else {
        _unitSizeController.clear();
      }

      if (production.unitCount != null) {
        _unitCountController.text = production.unitCount.toString();
      } else {
        _unitCountController.clear();
      }
    });

    // 2. Load Product
    final products = await ref.read(productsProvider.future);
    final product = products.firstWhere(
      (p) => p.id == production.productId,
      orElse: () => Product(name: 'Unknown', categoryId: 0),
    );

    setState(() {
      _selectedProduct = product.id != null ? product : null;
    });

    // 3. Load BOM (this creates controllers)
    if (product.id != null) {
      await _loadProductBOM(product.id!);
    }

    // 4. Load & Set Relations (Workers and Raw Materials used)
    try {
      if (production.id == null) return;

      // Workers
      final workerIds = await ProductionRepository.getWorkerIds(production.id!);

      // Raw Materials Usage
      final rawMaterialUsage =
          await ProductionRepository.getRawMaterialUsage(production.id!);

      setState(() {
        _selectedWorkerIds.clear();
        _selectedWorkerIds.addAll(workerIds);

        // Update controllers with actual usage from DB instead of calculated
        for (final usage in rawMaterialUsage) {
          final rawMaterialId = usage['raw_material_id'] as int;
          final quantityUsed = (usage['quantity_used'] as num).toDouble();
          final bagSize = (usage['bag_size'] as num?)?.toDouble();

          if (_rawMaterialQuantityControllers.containsKey(rawMaterialId)) {
            _rawMaterialQuantityControllers[rawMaterialId]!.text =
                quantityUsed.toString();
          }
          _selectedBagSizes[rawMaterialId] = bagSize;
        }
      });
    } catch (e) {
      print('Error loading production details: $e');
    }
  }

  Future<void> _deleteProduction(Production production) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Production'),
        content: Text('Delete production batch #${production.id}?'),
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

    if (confirm == true && production.id != null) {
      try {
        final selectedDate = ref.read(selectedDateProvider);
        await ProductionRepository.delete(production.id!);

        if (_editingId == production.id) {
          _clearForm();
        }

        ref.invalidate(productionListProvider(selectedDate));
        ref.invalidate(dashboardStatsProvider);
        ref.invalidate(rawMaterialStockProvider);
        ref.invalidate(productStockProvider);
        ref.invalidate(rawMaterialStockByBagSizeProvider);
        ref.invalidate(productStockByBagSizeProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Production batch deleted'),
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

  void _clearForm() {
    setState(() {
      _editingId = null;
      _selectedProduct = null;
      _batchesController.clear();
      _totalQuantityController.clear();
      _unitSizeController.clear();
      _unitCountController.clear();
      _selectedWorkerIds.clear();
      _productBOM = [];
      for (final controller in _rawMaterialQuantityControllers.values) {
        controller.dispose();
      }
      _rawMaterialQuantityControllers.clear();
    });
  }
}
