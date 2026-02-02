import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../models/unit_conversion.dart';
import '../../../database/repositories/unit_conversion_repository.dart';
import '../../../utils/validators.dart';
import '../../../providers/settings_providers.dart';

class UnitConversionsManagement extends ConsumerWidget {
  const UnitConversionsManagement({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversionsAsync = ref.watch(unitConversionsProvider);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Unit Conversions',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showConversionDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add Conversion'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Define conversion rates between different units',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: conversionsAsync.when(
              data: (conversions) {
                if (conversions.isEmpty) {
                  return Card(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.swap_horiz,
                            size: 64,
                            color: Theme.of(context)
                                .iconTheme
                                .color
                                ?.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          const Text('No unit conversions defined yet'),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () =>
                                _showConversionDialog(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Your First Conversion'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 40,
                      columns: const [
                        DataColumn(label: Text('From Unit')),
                        DataColumn(label: Text('To Unit')),
                        DataColumn(label: Text('Conversion Factor')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: conversions.map((conversion) {
                        return DataRow(cells: [
                          DataCell(Text(
                            conversion.fromUnit,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          )),
                          DataCell(Text(
                            conversion.toUnit,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          )),
                          DataCell(Text(
                            '1 ${conversion.fromUnit} = ${conversion.conversionFactor} ${conversion.toUnit}',
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                          )),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _showConversionDialog(
                                  context,
                                  ref,
                                  conversion: conversion,
                                ),
                                tooltip: 'Edit',
                                color: AppColors.primaryBlue,
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete_outline, size: 18),
                                onPressed: () => _deleteConversion(
                                  context,
                                  ref,
                                  conversion,
                                ),
                                tooltip: 'Delete',
                                color: AppColors.error,
                              ),
                            ],
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Text(
                  'Error: $error',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showConversionDialog(
    BuildContext context,
    WidgetRef ref, {
    UnitConversion? conversion,
  }) {
    showDialog(
      context: context,
      builder: (context) => _ConversionDialog(conversion: conversion),
    ).then((_) => ref.invalidate(unitConversionsProvider));
  }

  Future<void> _deleteConversion(
    BuildContext context,
    WidgetRef ref,
    UnitConversion conversion,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversion'),
        content: Text(
          'Delete conversion "${conversion.fromUnit} → ${conversion.toUnit}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && conversion.id != null) {
      try {
        await UnitConversionRepository.delete(conversion.id!);
        ref.invalidate(unitConversionsProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conversion deleted'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}

class _ConversionDialog extends StatefulWidget {
  final UnitConversion? conversion;

  const _ConversionDialog({this.conversion});

  @override
  State<_ConversionDialog> createState() => _ConversionDialogState();
}

class _ConversionDialogState extends State<_ConversionDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fromUnitController;
  late TextEditingController _toUnitController;
  late TextEditingController _factorController;

  // Common units for quick selection
  final List<String> _commonUnits = [
    'kg',
    'tons',
    'pieces',
    'boxes',
    'Bag',
    'sets',
    'liters',
    'meters',
  ];

  @override
  void initState() {
    super.initState();
    _fromUnitController =
        TextEditingController(text: widget.conversion?.fromUnit);
    _toUnitController = TextEditingController(text: widget.conversion?.toUnit);
    _factorController = TextEditingController(
      text: widget.conversion?.conversionFactor.toString(),
    );
  }

  @override
  void dispose() {
    _fromUnitController.dispose();
    _toUnitController.dispose();
    _factorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final newConversion = UnitConversion(
        id: widget.conversion?.id,
        fromUnit: _fromUnitController.text.trim(),
        toUnit: _toUnitController.text.trim(),
        conversionFactor: double.parse(_factorController.text),
      );

      // Check for duplicates
      final allConversions = await UnitConversionRepository.getAll();
      final duplicate = allConversions.any((c) =>
          c.fromUnit.toLowerCase() == newConversion.fromUnit.toLowerCase() &&
          c.toUnit.toLowerCase() == newConversion.toUnit.toLowerCase() &&
          (c.conversionFactor - newConversion.conversionFactor).abs() < 0.001 &&
          c.id != newConversion.id);

      if (duplicate) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Duplicate conversion already exists. Please delete the old one or change values.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      if (widget.conversion == null) {
        await UnitConversionRepository.create(newConversion);
      } else {
        await UnitConversionRepository.update(newConversion);
      }

      if (mounted) Navigator.pop(context);
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
    return AlertDialog(
      title: Text(
        widget.conversion == null
            ? 'Add Unit Conversion'
            : 'Edit Unit Conversion',
      ),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fromUnitController,
                      decoration: const InputDecoration(
                        labelText: 'From Unit *',
                        hintText: 'e.g., Box',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          Validators.required(value, fieldName: 'From Unit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                    tooltip: 'Select unit',
                    onSelected: (val) => _fromUnitController.text = val,
                    itemBuilder: (context) => _commonUnits
                        .map((u) => PopupMenuItem(value: u, child: Text(u)))
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _toUnitController,
                      decoration: const InputDecoration(
                        labelText: 'To Unit *',
                        hintText: 'e.g., kg',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          Validators.required(value, fieldName: 'To Unit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                    tooltip: 'Select unit',
                    onSelected: (val) => _toUnitController.text = val,
                    itemBuilder: (context) => _commonUnits
                        .map((u) => PopupMenuItem(value: u, child: Text(u)))
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _factorController,
                decoration: const InputDecoration(
                  labelText: 'Conversion Factor *',
                  hintText: 'e.g., 2.0',
                  helperText: '1 [From Unit] = ? [To Unit]',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    Validators.positiveNumber(value, fieldName: 'Factor'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
