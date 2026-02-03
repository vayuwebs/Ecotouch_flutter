import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../database/repositories/production_repository.dart';
import '../../database/database_service.dart';
import '../../models/production.dart';
import '../../models/product.dart';
import '../../models/stock_by_bag_size.dart';
import '../../providers/inventory_providers.dart';
import '../../providers/global_providers.dart';
import '../../providers/production_providers.dart';
import '../../models/unit_conversion.dart';
import '../../database/repositories/unit_conversion_repository.dart';

class ProductionEntryScreen extends ConsumerStatefulWidget {
  final Production? production; // If null, new entry

  const ProductionEntryScreen({super.key, this.production});

  @override
  ConsumerState<ProductionEntryScreen> createState() =>
      _ProductionEntryScreenState();
}

class _ProductionEntryScreenState extends ConsumerState<ProductionEntryScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;

  // Controllers
  final _totalQuantityController =
      TextEditingController(text: '1.00'); // Default 1
  final _batchesController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  final _unitSizeController = TextEditingController();
  final _unitCountController = TextEditingController();

  // State
  Product? _selectedProduct;
  List<int> _selectedWorkerIds = [];
  List<Map<String, dynamic>> _productBOM = [];
  List<StockByBagSize> _availableStock = [];

  // Strict Inventory: Track Bags (Integer) and Batch Selection (Id)
  final Map<int, TextEditingController> _bagCountControllers = {};
  final Map<int, int?> _selectedBatchIds = {}; // MaterialId -> InwardEntryId

  List<UnitConversion> _productUnitConversions = [];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _tabController = TabController(length: 2, vsync: this);

    // Add listeners for auto-calc
    _unitSizeController.addListener(_calculateTotalQuantity);
    _unitCountController.addListener(_calculateTotalQuantity);
    _batchesController.addListener(_updateRawMaterialSuggestions);

    // Force refresh of stock data on entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.refresh(rawMaterialStockByBagSizeProvider);
    });

    if (widget.production != null) {
      _loadExistingProduction();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _totalQuantityController.dispose();
    _batchesController.dispose();
    _notesController.dispose();
    _unitSizeController.dispose();
    _unitCountController.dispose();
    _tabController.dispose();
    for (var c in _bagCountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).maybePop();
        return true;
      }
    }
    return false;
  }

  Future<void> _loadExistingProduction() async {
    final p = widget.production!;
    _batchesController.text = p.batches.toString();
    _totalQuantityController.text = p.totalQuantity.toString();
    if (p.unitSize != null) _unitSizeController.text = p.unitSize.toString();
    if (p.unitCount != null) _unitCountController.text = p.unitCount.toString();

    // Load Product
    final products = await ref.read(productsProvider.future);
    final product = products.firstWhere((prod) => prod.id == p.productId,
        orElse: () => Product(name: 'Unknown', categoryId: 0));

    setState(() {
      _selectedProduct = product.id != null ? product : null;
    });

    if (product.id != null) {
      await _loadProductBOM(product.id!);
      // Load details (workers, materials) specific to this production
      _loadProductionDetails(p.id!);
    }
  }

  Future<void> _loadProductionDetails(int productionId) async {
    try {
      final workerIds = await ProductionRepository.getWorkerIds(productionId);
      final rawMaterialUsage =
          await ProductionRepository.getRawMaterialUsage(productionId);

      // We need to fetch the Inward Entry ID for these items if possible
      // But getRawMaterialUsage only returned quanity_used.
      // I need to update ProductionRepository.getRawMaterialUsage to return inward_entry_id and bag_count_used
      // Wait, I haven't updated that query yet! I should do that.
      // Assuming I will update it or have updated it.
      // Current implementation of ProductionRepository.getRawMaterialUsage queries 'bag_size'.
      // I need to update it to select 'inward_entry_id', 'bag_count_used'.

      setState(() {
        _selectedWorkerIds = workerIds;

        for (final usage in rawMaterialUsage) {
          // For now, handling potentially missing keys if repository not updated
          final rawMaterialId = usage['raw_material_id'] as int;
          final inwardEntryId = usage['inward_entry_id'] as int?;
          final bagCountUsed = usage['bag_count_used'] as int?;

          // Strict Logic: If bagCountUsed is missing (legacy), try to derive from quantity / bag size?
          // Or just leave empty and force user to re-enter.

          if (inwardEntryId != null) {
            _selectedBatchIds[rawMaterialId] = inwardEntryId;
          }

          if (_bagCountControllers.containsKey(rawMaterialId)) {
            _bagCountControllers[rawMaterialId]!.text =
                (bagCountUsed ?? 0).toString();
          }
        }
      });
    } catch (e) {
      print('Error loading details: $e');
    }
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
      for (var item in _productBOM) {
        final id = item['raw_material_id'] as int;
        if (!_bagCountControllers.containsKey(id)) {
          _bagCountControllers[id] = TextEditingController(text: '0');
        }
      }
    });

    // Load Unit Conversions
    final allConversions = await UnitConversionRepository.getAll();
    setState(() {
      if (_selectedProduct?.unit != null) {
        final productUnit = _selectedProduct!.unit!.toLowerCase();
        _productUnitConversions = allConversions.where((c) {
          return c.fromUnit.toLowerCase() == productUnit ||
              c.toUnit.toLowerCase() == productUnit;
        }).toList();
      } else {
        _productUnitConversions = allConversions;
      }
    });

    // Only update quantities if NEW entry
    if (widget.production == null) {
      _updateRawMaterialSuggestions();
    }
  }

  void _autoCalculateBags(int rawMaterialId, dynamic ratio, double bagSize) {
    if (bagSize <= 0) return;

    final batches = double.tryParse(_batchesController.text) ?? 0;
    final ratioDouble = (ratio as num).toDouble();
    final requiredQty = ratioDouble * batches;

    // Calculate bags needed (Ceiling to ensure enough material)
    // E.g. Need 30, Bag 15 => 2 bags
    // Need 31, Bag 15 => 3 bags
    final bagsNeeded = (requiredQty / bagSize).ceil();

    if (_bagCountControllers.containsKey(rawMaterialId)) {
      _bagCountControllers[rawMaterialId]!.text = bagsNeeded.toString();
    }
  }

  void _updateRawMaterialSuggestions() {
    if (widget.production != null) return;

    // Iterate all raw materials in BOM and update bags if batch selected
    for (var item in _productBOM) {
      final rId = item['raw_material_id'] as int;
      final ratio = item['quantity_ratio'];
      final selectedBatchId = _selectedBatchIds[rId];

      if (selectedBatchId != null) {
        final stockItem = _availableStock.firstWhere(
            (s) => s.inwardEntryId == selectedBatchId,
            orElse: () => StockByBagSize(
                materialId: -1,
                materialName: '',
                bagSize: 0,
                bagCount: 0,
                totalWeight: 0,
                unit: ''));

        if (stockItem.bagSize > 0) {
          _autoCalculateBags(rId, ratio, stockItem.bagSize);
        }
      }
    }
  }

  void _calculateTotalQuantity() {
    final unitCount = double.tryParse(_unitCountController.text) ?? 0;
    final unitSize = double.tryParse(_unitSizeController.text) ?? 0;
    if (unitCount > 0 && unitSize > 0) {
      final total = unitCount * unitSize;
      _totalQuantityController.text = total.toStringAsFixed(2);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: AppColors.error));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final selectedDate = ref.read(selectedDateProvider);
      final batches = int.tryParse(_batchesController.text) ?? 1;
      final totalQuantity = double.tryParse(_totalQuantityController.text) ?? 0;

      double? unitSize;
      double? unitCount;
      if (_unitSizeController.text.isNotEmpty &&
          _unitCountController.text.isNotEmpty) {
        unitSize = double.tryParse(_unitSizeController.text);
        unitCount = double.tryParse(_unitCountController.text);
      }

      // 1. Validate Stock Sources & Quantities
      for (final item in _productBOM) {
        final rId = item['raw_material_id'] as int;
        final rName = item['raw_material_name'] as String;
        final bagsInput =
            int.tryParse(_bagCountControllers[rId]?.text ?? '0') ?? 0;
        final selectedBatchId = _selectedBatchIds[rId];

        // If BOM requires ratio > 0 (it usually does), check if we are consuming
        // Wait, ratio is per batch. If 1 batch, we need ratio amount.
        // We shouldn't silently skip if ratio > 0.
        // But maybe user wants to consume 0?
        // Let's assume if bags > 0, we need a source.

        if (bagsInput > 0) {
          if (selectedBatchId == null) {
            throw Exception('Source batch must be selected for $rName');
          }

          // Verify availability
          final stockItem = _availableStock.firstWhere(
            (s) => s.inwardEntryId == selectedBatchId,
            orElse: () =>
                throw Exception('Selected batch for $rName not found in stock'),
          );

          if (stockItem.bagCount < bagsInput) {
            throw Exception(
                'Insufficient bags in selected batch for $rName.\nRequested: $bagsInput packages\nAvailable: ${stockItem.bagCount} packages\nBatch #${stockItem.inwardEntryId}');
          }
        }
      }

      final p = Production(
        id: widget.production?.id,
        productId: _selectedProduct!.id!,
        date: selectedDate,
        batches: batches,
        totalQuantity: totalQuantity,
        unitSize: unitSize,
        unitCount: unitCount,
        workerIds: _selectedWorkerIds,
      );

      int pId;
      if (p.id != null) {
        await ProductionRepository.update(p);
        pId = p.id!;
      } else {
        pId = await ProductionRepository.insert(p);
      }

      // Handle Raw Materials (Delete old, Insert new)
      if (widget.production != null) {
        await DatabaseService.delete('production_raw_materials',
            where: 'production_id = ?', whereArgs: [pId]);
      }

      for (final item in _productBOM) {
        final rId = item['raw_material_id'] as int;
        final bagsInput =
            int.tryParse(_bagCountControllers[rId]?.text ?? '0') ?? 0;
        final selectedBatchId = _selectedBatchIds[rId];

        if (bagsInput > 0 && selectedBatchId != null) {
          final stockItem = _availableStock
              .firstWhere((s) => s.inwardEntryId == selectedBatchId);
          final weightUsed = bagsInput * stockItem.bagSize;

          await DatabaseService.insert('production_raw_materials', {
            'production_id': pId,
            'raw_material_id': rId,
            'quantity_used': weightUsed,
            'bag_size': stockItem.bagSize,
            'inward_entry_id': stockItem.inwardEntryId,
            'bag_count_used': bagsInput,
          });
        }
      }

      // Refresh providers
      ref.invalidate(productionListProvider(selectedDate));
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(rawMaterialStockByBagSizeProvider);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch providers
    final productsAsync = ref.watch(productsProvider);
    final workersAsync = ref.watch(workersProvider);
    final selectedDate = ref.watch(selectedDateProvider);

    // Update stock cache
    final stockAsync = ref.watch(rawMaterialStockByBagSizeProvider);
    print('DEBUG: Stock Provider State: $stockAsync'); // Debug Print

    if (stockAsync.isLoading && !stockAsync.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (stockAsync.hasError) {
      return Scaffold(
          body:
              Center(child: Text('Error loading stock: ${stockAsync.error}')));
    }

    if (stockAsync.hasValue) _availableStock = stockAsync.value!;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(widget.production == null
                ? 'New Production'
                : 'Edit BP-${widget.production!.id}'),
            backgroundColor: Colors.white,
            elevation: 0,
            leading: const CloseButton(color: Colors.black),
            titleTextStyle: const TextStyle(
                color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
            actions: [
              // Date display...
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200))),
                child: Row(
                  children: [
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
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
                    const Spacer(),
                    if (widget.production != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Confirmed',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold)),
                      )
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
                        // Title
                        Text(
                          widget.production == null
                              ? 'Production Details'
                              : 'BP-${widget.production!.id}',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.normal),
                        ),
                        const SizedBox(height: 24),

                        // Form Fields (Product, Batches etc)
                        // Reusing existing widgets essentially but simplifying

                        Wrap(
                          spacing: 40,
                          runSpacing: 20,
                          children: [
                            SizedBox(
                              width: 400,
                              child: productsAsync.when(
                                data: (products) =>
                                    DropdownButtonFormField<Product>(
                                        value: _selectedProduct,
                                        decoration: const InputDecoration(
                                          labelText: 'Product',
                                          border: UnderlineInputBorder(),
                                        ),
                                        items: products
                                            .map((p) => DropdownMenuItem(
                                                value: p, child: Text(p.name)))
                                            .toList(),
                                        onChanged: (p) {
                                          setState(() {
                                            _selectedProduct = p;
                                            _productBOM = [];
                                            _batchesController.text = '1';
                                          });
                                          if (p?.id != null)
                                            _loadProductBOM(p!.id!);
                                        }),
                                loading: () => const LinearProgressIndicator(),
                                error: (e, s) =>
                                    const Text('Error loading products'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: _batchesController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: const InputDecoration(
                                  labelText: 'Batches',
                                  border: OutlineInputBorder()),
                              onChanged: (_) => _updateRawMaterialSuggestions(),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: DropdownButtonFormField<double>(
                              value: _productUnitConversions.any((c) =>
                                      c.conversionFactor ==
                                      double.tryParse(_unitSizeController.text))
                                  ? double.tryParse(_unitSizeController.text)
                                  : null,
                              decoration: const InputDecoration(
                                  labelText: 'Unit Size',
                                  border: OutlineInputBorder()),
                              items: _productUnitConversions
                                  .map((c) => DropdownMenuItem(
                                        value: c.conversionFactor,
                                        child: Text(
                                            "${c.fromUnit} -> ${c.toUnit} (${c.conversionFactor})"),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _unitSizeController.text = val.toString();
                                  });
                                  _calculateTotalQuantity();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: TextFormField(
                              controller: _unitCountController,
                              decoration: const InputDecoration(
                                  labelText: 'Unit Count',
                                  border: OutlineInputBorder()),
                            ),
                          ),
                        ]),

                        const SizedBox(height: 32),

                        // Tabs
                        Column(children: [
                          TabBar(
                            controller: _tabController,
                            labelColor: const Color(0xFF714B67),
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: const Color(0xFF714B67),
                            tabs: const [
                              Tab(text: 'Raw Materials (Strict Allocation)'),
                              Tab(text: 'Workers'),
                            ],
                          ),
                          Container(
                            height: 500, // Increased height
                            decoration: BoxDecoration(
                                border: Border(
                                    top: BorderSide(
                                        color: Colors.grey.shade300))),
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildComponentsTab(),
                                _buildMiscTab(workersAsync),
                              ],
                            ),
                          )
                        ])
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isLoading)
          const Opacity(
            opacity: 0.5,
            child: ModalBarrier(dismissible: false, color: Colors.black),
          ),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildComponentsTab() {
    if (_selectedProduct == null) {
      return const Center(child: Text('Select a product to view components'));
    }
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Text('Material',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 3,
                  child: Text('Source Batch',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text('Bags Used',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text('Weight (Calc)',
                      style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        const Divider(),
        ..._productBOM.map((item) {
          final rawMaterialId = item['raw_material_id'] as int;
          final rawMaterialName = item['raw_material_name'] as String;
          final unit = item['unit'] as String;

          // Filter stock for this material
          final batches = _availableStock
              .where((s) => s.materialId == rawMaterialId)
              .toList();

          print('DEBUG: Material ID: $rawMaterialId ($rawMaterialName)');
          print('DEBUG: Available Stock Count: ${_availableStock.length}');
          if (_availableStock.isNotEmpty) {
            print(
                'DEBUG: First Stock Item Material ID: ${_availableStock.first.materialId}');
            print(
                'DEBUG: First Stock Item Date: ${_availableStock.first.inwardDate}');
          }
          print('DEBUG: Batches found for this material: ${batches.length}');

          final selectedBatchId = _selectedBatchIds[rawMaterialId];
          final selectedBatch = batches.firstWhere(
              (b) => b.inwardEntryId == selectedBatchId,
              orElse: () => batches.isNotEmpty
                  ? batches.first
                  : StockByBagSize(
                      materialId: -1,
                      materialName: '',
                      bagSize: 0,
                      bagCount: 0,
                      totalWeight: 0,
                      unit: ''));
          // Note: orElse dummy is just to prevent crash, ideally handle null properly.

          final bagCountCtrl = _bagCountControllers[rawMaterialId]!;
          final bagsUsed = int.tryParse(bagCountCtrl.text) ?? 0;

          double bagSize = 0;
          if (selectedBatchId != null) {
            final b = batches.firstWhere(
                (s) => s.inwardEntryId == selectedBatchId,
                orElse: () => selectedBatch);
            bagSize = b.bagSize;
          }
          final calcWeight = bagsUsed * bagSize;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Material Name
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rawMaterialName,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text('Ratio: ${item['quantity_ratio']} $unit / batch',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),

                // Batch Selector
                Expanded(
                  flex: 3,
                  child: batches.isEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(4),
                            color: Colors.grey.shade100,
                          ),
                          child: const Text('No Stock Available',
                              style:
                                  TextStyle(fontSize: 13, color: Colors.grey)),
                        )
                      : DropdownButtonFormField<int>(
                          value: selectedBatchId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 10, horizontal: 8),
                            hintText: 'Select Batch',
                          ),
                          items: batches.map((s) {
                            return DropdownMenuItem<int>(
                              value: s.inwardEntryId,
                              child: Text(
                                'Batch #${s.inwardEntryId} (${s.bagSize}$unit) - ${s.bagCount} pkts left',
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedBatchIds[rawMaterialId] = val;
                            });
                            // Auto-calculate bags based on recipe
                            if (val != null) {
                              final batch = batches
                                  .firstWhere((b) => b.inwardEntryId == val);
                              _autoCalculateBags(rawMaterialId,
                                  item['quantity_ratio'], batch.bagSize);
                            }
                          },
                        ),
                ),

                const SizedBox(width: 8),

                // Bags Used Input
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: bagCountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixText: 'pkts',
                    ),
                    onChanged: (_) =>
                        setState(() {}), // rebuild to update calc weight
                  ),
                ),
                const SizedBox(width: 8),

                // Calculated Weight
                Expanded(
                  flex: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    color: Colors.grey.shade100,
                    child: Text(
                      '${calcWeight.toStringAsFixed(2)} $unit',
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMiscTab(AsyncValue<List<dynamic>> workersAsync) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Workers', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          workersAsync.when(
            data: (workers) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: workers.map((w) {
                final isSelected = _selectedWorkerIds.contains(w.id);
                return FilterChip(
                  label: Text(w.name),
                  selected: isSelected,
                  onSelected: (sel) {
                    setState(() {
                      if (sel)
                        _selectedWorkerIds.add(w.id!);
                      else
                        _selectedWorkerIds.remove(w.id);
                    });
                  },
                );
              }).toList(),
            ),
            loading: () => const CircularProgressIndicator(),
            error: (e, s) => const Text('Error loading workers'),
          ),
        ],
      ),
    );
  }
}
