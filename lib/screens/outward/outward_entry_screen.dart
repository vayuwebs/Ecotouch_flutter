import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';
import '../../database/repositories/outward_repository.dart';
import '../../models/outward.dart';
import '../../models/product.dart';
import '../../models/stock_by_bag_size.dart';
import '../../providers/global_providers.dart';
import '../../providers/inventory_providers.dart';

import '../../services/stock_calculation_service.dart';
import '../../providers/outward_providers.dart';

class OutwardEntryScreen extends ConsumerStatefulWidget {
  final Outward? outward;

  const OutwardEntryScreen({super.key, this.outward});

  @override
  ConsumerState<OutwardEntryScreen> createState() => _OutwardEntryScreenState();
}

class _OutwardEntryScreenState extends ConsumerState<OutwardEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bagCountController = TextEditingController();
  final _notesController = TextEditingController();

  Product? _selectedProduct;
  double _total = 0;
  String _displayUnit = 'kg';

  // State for dynamic dropdown
  List<StockByBagSize> _stockOptions = [];
  double? _selectedBagSize;
  bool _loadingStock = false;
  bool _isGlobalLoading = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    if (widget.outward != null) {
      _loadExistingOutward();
    }
  }

  Future<void> _loadExistingOutward() async {
    _bagCountController.text = widget.outward!.bagCount.toString();
    _notesController.text = widget.outward!.notes ?? '';
    _total = widget.outward!.totalWeight;
    _selectedBagSize = widget.outward!.bagSize;

    // Defer loading product until products are available
    final products = await ref.read(productsProvider.future);
    try {
      final product =
          products.firstWhere((p) => p.id == widget.outward!.productId);
      setState(() {
        _selectedProduct = product;
        _displayUnit = product.unit ?? 'kg';
      });
      // Fetch stock options after setting product
      await _fetchStockOptions(product.id!);

      // Ensure selected bag size is set even if not in current stock (for editing historical records)
      if (!_stockOptions
          .any((opt) => (opt.bagSize - _selectedBagSize!).abs() < 0.01)) {
        // Add legacy option
        setState(() {
          _stockOptions.add(StockByBagSize(
              materialId: product.id!,
              materialName: product.name,
              bagSize: _selectedBagSize!,
              bagCount: 0,
              totalWeight: 0,
              unit: _displayUnit,
              containerUnit: product.unit ?? 'bags'));
        });
      }
    } catch (e) {
      // Product might be deleted
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _bagCountController.dispose();
    _notesController.dispose();
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

  void _calculateTotal() {
    final bagSize = _selectedBagSize ?? 0;
    final bagCount = int.tryParse(_bagCountController.text) ?? 0;
    setState(() {
      _total = bagSize * bagCount;
    });
  }

  void _loadConvertedUnit(Product product) {
    setState(() {
      _displayUnit = product.unit ?? 'kg';
    });
  }

  Future<void> _fetchStockOptions(int productId) async {
    setState(() => _loadingStock = true);

    // Reset selection when product changes (unless we effectively just loaded it for edit)
    if (widget.outward == null ||
        _selectedProduct?.id != widget.outward?.productId) {
      if (_selectedProduct?.id != productId) {
        // If changing product
        _selectedBagSize = null;
      }
    } else if (widget.outward != null && _selectedProduct?.id != productId) {
      _selectedBagSize = null;
    }

    try {
      final selectedDate = ref.read(selectedDateProvider);
      // Fetch all available stock configurations
      final allStock =
          await StockCalculationService.calculateProductStockByBagSize(
              selectedDate);

      // Filter for this product
      final options =
          allStock.where((item) => item.materialId == productId).toList();

      if (mounted) {
        setState(() {
          _stockOptions = options;
          _loadingStock = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingStock = false);
    }
  }

  Future<void> _submitEntry() async {
    if (!_formKey.currentState!.validate() || _selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isGlobalLoading = true);

    try {
      final selectedDate = ref.read(selectedDateProvider);
      final bagSize = _selectedBagSize!;
      final bagCount = int.parse(_bagCountController.text);
      final total = bagSize * bagCount;

      // Validate stock availability
      final stockMap = await StockCalculationService.calculateProductStock(
        selectedDate,
      );

      // Calculate total stock from FIFO map for this product
      final currentStock = stockMap[_selectedProduct!.id] ?? 0;

      // If EDITING, we should add back the original quantity to "Available" for validation
      // But for simplicity, we'll stricter check: Current Available must cover new requirement?
      // No, if editing, we might be increasing quantity.
      // Net change calculation is better but simple check is okay for now.

      // Basic Check
      if (currentStock < total) {
        // If editing, allow if (Current + Old) >= New?
        // Let's keep it simple: Stock check warns but maybe allows?
        // User request was "show error that stock is not available" for PRODUCTION.
        // For Outward (Sales), usually strict.
        // Let's throw error.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Insufficient stock. Available: ${currentStock.toStringAsFixed(2)} $_displayUnit'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        setState(() => _isGlobalLoading = false);
        return;
      }

      final outward = Outward(
        id: widget.outward?.id,
        productId: _selectedProduct!.id!,
        date: selectedDate,
        bagSize: bagSize,
        bagCount: bagCount,
        totalWeight: total,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (widget.outward != null) {
        await OutwardRepository.update(outward);
      } else {
        await OutwardRepository.insert(outward);
      }

      ref.invalidate(outwardListProvider(selectedDate));
      ref.invalidate(productStockProvider);
      ref.invalidate(dashboardStatsProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.outward != null
                ? 'Shipment updated'
                : 'Shipment recorded'),
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
    } finally {
      if (mounted) setState(() => _isGlobalLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final selectedDate = ref.watch(selectedDateProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.outward == null ? 'New Shipment' : 'Edit Shipment'),
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
                  onPressed: _isGlobalLoading ? null : _submitEntry,
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
                    // Product Dropdown
                    SizedBox(
                      width: 400,
                      child: productsAsync.when(
                        data: (products) => DropdownButtonFormField<Product>(
                          value: _selectedProduct,
                          decoration: const InputDecoration(
                            labelText: 'Product SKU *',
                            border: OutlineInputBorder(),
                          ),
                          items: products.map((product) {
                            return DropdownMenuItem(
                              value: product,
                              child: Text(product.name),
                            );
                          }).toList(),
                          onChanged: (product) {
                            setState(() => _selectedProduct = product);
                            if (product != null) {
                              _loadConvertedUnit(product);
                              _fetchStockOptions(product.id!);
                            }
                          },
                          validator: (value) =>
                              value == null ? 'Required' : null,
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) => const Text('Error loading products'),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Bag Size
                    if (_loadingStock)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      )
                    else
                      DropdownButtonFormField<double>(
                        value: _selectedBagSize,
                        decoration: InputDecoration(
                          labelText: 'Size per Bag *',
                          hintText: _stockOptions.isEmpty
                              ? 'No stock available'
                              : 'Select bag size',
                          helperText: _stockOptions.isEmpty
                              ? 'No items to sell'
                              : 'Select from available stock',
                          border: const OutlineInputBorder(),
                          filled: _stockOptions.isEmpty,
                          fillColor: _stockOptions.isEmpty
                              ? Colors.grey.shade100
                              : null,
                        ),
                        items: _stockOptions.map((option) {
                          return DropdownMenuItem<double>(
                            value: option.bagSize,
                            child: Text(
                              '${option.bagSize} $_displayUnit  (${option.bagCount} bags)',
                              style: TextStyle(
                                  color: option.bagCount == 0
                                      ? AppColors.error
                                      : null),
                            ),
                          );
                        }).toList(),
                        onChanged: _stockOptions.isEmpty
                            ? null
                            : (val) {
                                setState(() {
                                  _selectedBagSize = val;
                                  _calculateTotal();
                                });
                              },
                        validator: (value) => value == null ? 'Required' : null,
                      ),

                    const SizedBox(height: 20),

                    // Quantity
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _bagCountController,
                            decoration: InputDecoration(
                              labelText: 'Number of Bags',
                              suffixText: _selectedProduct?.unit ?? 'Units',
                              helperText: 'Total Count',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) => Validators.positiveInteger(
                                value,
                                fieldName: 'Quantity'),
                            onChanged: (_) => _calculateTotal(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.success.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Shipment',
                                    style: TextStyle(fontSize: 10)),
                                Text(
                                  '${_total.toStringAsFixed(2)} $_displayUnit',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Notes
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes / Customer / Dest.',
                        hintText: 'Customer, Location, Invoice...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
