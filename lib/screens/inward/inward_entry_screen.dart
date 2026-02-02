import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';

import '../../utils/validators.dart';
import '../../database/repositories/inward_repository.dart';
import '../../models/inward.dart';
import '../../models/raw_material.dart';
import '../../providers/global_providers.dart';
import '../../providers/inventory_providers.dart';
import '../../providers/inward_providers.dart';

class InwardEntryScreen extends ConsumerStatefulWidget {
  final Inward? inward; // If null, new entry

  const InwardEntryScreen({super.key, this.inward});

  @override
  ConsumerState<InwardEntryScreen> createState() => _InwardEntryScreenState();
}

class _InwardEntryScreenState extends ConsumerState<InwardEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bagSizeController = TextEditingController();
  final _bagCountController = TextEditingController();
  final _notesController = TextEditingController();

  RawMaterial? _selectedMaterial;
  double _total = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    if (widget.inward != null) {
      _loadExistingInward();
    }
  }

  void _loadExistingInward() async {
    setState(() {
      _bagSizeController.text = widget.inward!.bagSize.toString();
      _bagCountController.text = widget.inward!.bagCount.toString();
      _notesController.text = widget.inward!.notes ?? '';
      _total = widget.inward!.totalWeight;
    });

    // Load material details (async)
    // We defer setting _selectedMaterial until data is available,
    // or we assume lists are loaded.
    // Ideally we wait for provider.
    final materials = await ref.read(rawMaterialsProvider.future);
    try {
      final material =
          materials.firstWhere((m) => m.id == widget.inward!.rawMaterialId);
      setState(() {
        _selectedMaterial = material;
      });
    } catch (e) {
      // Material might be deleted?
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _bagSizeController.dispose();
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
    final bagSize = double.tryParse(_bagSizeController.text) ?? 0;
    final bagCount = int.tryParse(_bagCountController.text) ?? 0;
    setState(() {
      _total = bagSize * bagCount;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedMaterial == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: AppColors.error));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final selectedDate = ref.read(selectedDateProvider);

      final inward = Inward(
        id: widget.inward?.id,
        rawMaterialId: _selectedMaterial!.id!,
        date: selectedDate,
        bagSize: double.parse(_bagSizeController.text),
        bagCount: int.parse(_bagCountController.text),
        totalWeight: _total,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (widget.inward != null) {
        await InwardRepository.update(inward);
      } else {
        await InwardRepository.insert(inward);
      }

      ref.invalidate(inwardListProvider(selectedDate));
      ref.invalidate(rawMaterialStockProvider);
      // Also invalidate bag size stock cache if needed
      ref.invalidate(rawMaterialStockByBagSizeProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.inward != null
                ? 'Inward entry updated'
                : 'Inward entry added'),
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _containerLabel {
    final unit = _selectedMaterial?.unit?.toLowerCase() ?? '';
    if (unit == 'ltr' || unit == 'l') return 'bottles';
    if (unit == 'kg' || unit == 'gm') return 'bags';
    if (unit == 'pcs' || unit == 'nos') return 'boxes';
    return 'packs';
  }

  @override
  Widget build(BuildContext context) {
    final materialsAsync = ref.watch(rawMaterialsProvider);
    final selectedDate = ref.watch(selectedDateProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.inward == null ? 'New Inward' : 'Edit Inward'),
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
                    // Material Dropdown
                    SizedBox(
                      width: 400,
                      child: materialsAsync.when(
                        data: (materials) =>
                            DropdownButtonFormField<RawMaterial>(
                          value: _selectedMaterial,
                          decoration: const InputDecoration(
                            labelText: 'Raw Material *',
                            border: OutlineInputBorder(),
                          ),
                          items: materials.map((material) {
                            return DropdownMenuItem(
                              value: material,
                              child:
                                  Text('${material.name} (${material.unit})'),
                            );
                          }).toList(),
                          onChanged: (material) {
                            setState(() => _selectedMaterial = material);
                          },
                          validator: (value) =>
                              value == null ? 'Required' : null,
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) => const Text('Error loading materials'),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Bag Size & Count
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _bagSizeController,
                            decoration: InputDecoration(
                              labelText: 'Pack Size',
                              suffixText: _selectedMaterial?.unit ?? 'unit',
                              helperText: 'Size of one pack',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) => Validators.positiveNumber(
                                value,
                                fieldName: 'Pack Size'),
                            onChanged: (_) => _calculateTotal(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _bagCountController,
                            decoration: InputDecoration(
                              labelText: 'Number of Packs',
                              suffixText: _containerLabel,
                              helperText: 'Count',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) => Validators.positiveInteger(
                                value,
                                fieldName: 'Bag Count'),
                            onChanged: (_) => _calculateTotal(),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Total Display
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.primaryBlue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Text('Total Inward Weight:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(
                            '${_total.toStringAsFixed(2)} ${_selectedMaterial?.unit ?? ''}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Notes
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes / Supplier Info',
                        hintText: 'Invoice no., supplier details...',
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
