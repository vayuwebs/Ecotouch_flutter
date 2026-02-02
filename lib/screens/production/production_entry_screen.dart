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
  final Map<int, TextEditingController> _rawMaterialQuantityControllers = {};
  final Map<int, double?> _selectedBagSizes = {};
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
    for (var c in _rawMaterialQuantityControllers.values) {
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

      setState(() {
        _selectedWorkerIds = workerIds;

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
        if (!_rawMaterialQuantityControllers.containsKey(id)) {
          _rawMaterialQuantityControllers[id] = TextEditingController();
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
      _updateRawMaterialQuantities();
    }
  }

  void _updateRawMaterialQuantities() {
    if (widget.production != null) return;

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

      // Stock Check
      for (final item in _productBOM) {
        final rId = item['raw_material_id'] as int;
        final rName = item['raw_material_name'] as String;
        final qtyRequired = double.tryParse(
                _rawMaterialQuantityControllers[rId]?.text ?? '0') ??
            0;
        final selectedBagSize = _selectedBagSizes[rId];

        if (qtyRequired > 0) {
          if (selectedBagSize == null) {
            // Should force selection? Or assume valid if logic allows?
            // If strictly enforcing positive stock, we need a source.
            throw Exception('Please select a stock source for $rName');
          }

          final stockItem = _availableStock.firstWhere(
            (s) => s.materialId == rId && s.bagSize == selectedBagSize,
            orElse: () => StockByBagSize(
              materialId: rId,
              materialName: rName,
              bagSize: selectedBagSize,
              bagCount: 0,
              totalWeight: 0,
              unit: '',
            ),
          );

          // Calculate required bags
          // If bagSize is 0, division by zero! Check logic.
          // Assuming bagSize > 0.
          if (selectedBagSize > 0) {
            // We compare against bagCount (int).
            // Since we can use partial bags in production (maybe?), we compare total weight?
            // But stock is "bagCount" packs.
            // If bagCount is 10. We have 10 bags.
            // If we need 10.5 bags, we don't have enough.
            // Let's rely on totalWeight vs quantity?
            // stockItem.totalWeight comes from DB.
            // Check: StockByBagSize factory usually calculates totalWeight = bagCount * bagSize.

            // STRICT CHECK:
            // If implementation allows partial usage of a bag, calculate total weight available.
            // Total Available = stockItem.bagCount * stockItem.bagSize;
            // Total Required = qtyRequired;

            final totalAvailable = stockItem.bagCount * stockItem.bagSize;
            // Allow a small epsilon for float precision?
            if (totalAvailable < (qtyRequired - 0.001)) {
              throw Exception(
                  'Insufficient stock for $rName. Required: $qtyRequired, Available: $totalAvailable (Source: $selectedBagSize)');
            }
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

      // Handle Raw Materials
      // First delete old usage if editing
      if (widget.production != null) {
        await DatabaseService.delete('production_raw_materials',
            where: 'production_id = ?', whereArgs: [pId]);
      }

      for (final item in _productBOM) {
        final rId = item['raw_material_id'] as int;
        final qty = double.tryParse(
                _rawMaterialQuantityControllers[rId]?.text ?? '0') ??
            0;
        final bag = _selectedBagSizes[rId];
        if (qty > 0) {
          await DatabaseService.insert('production_raw_materials', {
            'production_id': pId,
            'raw_material_id': rId,
            'quantity_used': qty,
            'bag_size': bag,
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
    if (stockAsync.hasValue) _availableStock = stockAsync.value!;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(widget.production == null
                ? 'New'
                : 'BP-${widget.production!.id}'),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.production == null
                            ? Colors.blue.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                          widget.production == null ? 'Draft' : 'Confirmed',
                          style: TextStyle(
                              color: widget.production == null
                                  ? Colors.blue
                                  : Colors.green,
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
                        // Title / Name
                        Text(
                          widget.production == null
                              ? 'Draft'
                              : 'BP-${widget.production!.id}',
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.normal),
                        ),
                        const SizedBox(height: 24),

                        // Top Form Grid
                        Wrap(
                          spacing: 40,
                          runSpacing: 20,
                          children: [
                            // Product
                            SizedBox(
                              width: 400,
                              child: productsAsync.when(
                                data: (products) =>
                                    DropdownButtonFormField<Product>(
                                        value: _selectedProduct,
                                        decoration: const InputDecoration(
                                          labelText: 'Product',
                                          border: UnderlineInputBorder(),
                                          contentPadding: EdgeInsets.zero,
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

                        const SizedBox(height: 20),

                        // Batches & Units Row
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: _batchesController,
                              decoration: const InputDecoration(
                                  labelText: 'Operation Count (Batches)',
                                  border: OutlineInputBorder()),
                              onChanged: (_) => _updateRawMaterialQuantities(),
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
                              items: _productUnitConversions.isEmpty
                                  ? [
                                      const DropdownMenuItem(
                                          value: null,
                                          enabled: false,
                                          child: Text("No units available"))
                                    ]
                                  : (() {
                                      final seenFactors = <double>{};
                                      return _productUnitConversions
                                          .where((c) => seenFactors
                                              .add(c.conversionFactor))
                                          .map((c) => DropdownMenuItem(
                                                value: c.conversionFactor,
                                                child: Text(
                                                    "${c.fromUnit} -> ${c.toUnit} (${c.conversionFactor})"),
                                              ))
                                          .toList();
                                    })(),
                              onChanged: _productUnitConversions.isEmpty
                                  ? null
                                  : (val) {
                                      if (val != null) {
                                        setState(() {
                                          _unitSizeController.text =
                                              val.toString();
                                        });
                                        // Trigger calculation
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
                        Column(
                          children: [
                            TabBar(
                              controller: _tabController,
                              labelColor: const Color(0xFF714B67),
                              unselectedLabelColor: Colors.grey,
                              indicatorColor: const Color(0xFF714B67),
                              isScrollable: true,
                              tabs: const [
                                Tab(text: 'Components'),
                                Tab(text: 'Workers'),
                              ],
                            ),
                            Container(
                              height: 400,
                              decoration: BoxDecoration(
                                  border: Border(
                                      top: BorderSide(
                                          color: Colors.grey.shade300))),
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  // TAB 1: Components (BOM)
                                  _buildComponentsTab(),

                                  // TAB 2: Misc (Workers, Notes)
                                  _buildMiscTab(workersAsync),
                                ],
                              ),
                            )
                          ],
                        ),
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
        // Header
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Text('Product',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text('To Consume',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text('Stock Source',
                      style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        const Divider(),

        ..._productBOM.map((item) {
          final rawMaterialId = item['raw_material_id'] as int;
          final rawMaterialName = item['raw_material_name'] as String;
          final unit = item['unit'] as String;
          final options = _availableStock
              .where((s) => s.materialId == rawMaterialId)
              .toList();

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(rawMaterialName),
                ),
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          controller:
                              _rawMaterialQuantityControllers[rawMaterialId],
                          decoration: const InputDecoration(
                              isDense: true, border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(unit, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<double>(
                    value: _selectedBagSizes[rawMaterialId],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: 'Source',
                    ),
                    items: options
                        .map((s) => DropdownMenuItem(
                              value: s.bagSize,
                              child: Text(
                                  '${s.bagSize} ($unit) - ${s.bagCount} avail'),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedBagSizes[rawMaterialId] = v),
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
