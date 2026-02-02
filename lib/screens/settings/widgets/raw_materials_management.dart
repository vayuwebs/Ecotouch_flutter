import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../models/raw_material.dart';
import '../../../database/repositories/raw_material_repository.dart';
import '../../../database/database_service.dart';
import '../../../utils/validators.dart';
import '../../../providers/global_providers.dart';
import '../../dashboard/dashboard_screen.dart';

class RawMaterialsManagement extends ConsumerWidget {
  const RawMaterialsManagement({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialsAsync = ref.watch(rawMaterialsProvider);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Raw Materials',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Define raw materials and their properties',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showRawMaterialDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add Material'),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Materials Table
          Expanded(
            child: materialsAsync.when(
              data: (materials) {
                if (materials.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 64,
                            color: Theme.of(context)
                                .iconTheme
                                .color
                                ?.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No raw materials found',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => _showRawMaterialDialog(context, ref),
                          icon: const Icon(Icons.add),
                          label: const Text('Add your first material'),
                        ),
                      ],
                    ),
                  );
                }

                return Card(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                    child: SingleChildScrollView(
                      child: DataTable(
                        dataRowHeight: 60,
                        columns: const [
                          DataColumn(label: Text('Material Name')),
                          DataColumn(label: Text('Unit')),
                          DataColumn(label: Text('Min Alert Level')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: materials.map((material) {
                          return DataRow(cells: [
                            DataCell(Text(material.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500))),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? AppColors.darkSurfaceVariant
                                    : AppColors.lightSurfaceVariant,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(material.unit,
                                  style: const TextStyle(fontSize: 12)),
                            )),
                            DataCell(Text(
                                '${material.minAlertLevel} ${material.unit}')),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    onPressed: () => _showRawMaterialDialog(
                                        context, ref,
                                        material: material),
                                    tooltip: 'Edit',
                                    color: AppColors.primaryBlue,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18),
                                    onPressed: () =>
                                        _deleteMaterial(context, ref, material),
                                    tooltip: 'Delete',
                                    color: AppColors.error,
                                  ),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Text('Error: $error',
                    style: const TextStyle(color: AppColors.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRawMaterialDialog(BuildContext context, WidgetRef ref,
      {RawMaterial? material}) async {
    await showDialog(
      context: context,
      builder: (context) => _RawMaterialDialog(material: material),
    );
    // Refresh strictly after dialog close if needed, but dialog handles self-invalidation logic usually.
    // However, to be safe:
    // ref.invalidate(rawMaterialsProvider); // This is done inside dialog
  }

  Future<void> _deleteMaterial(
      BuildContext context, WidgetRef ref, RawMaterial material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Material'),
        content: Text('Are you sure you want to delete ${material.name}?'),
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

    if (confirmed == true && material.id != null) {
      await RawMaterialRepository.delete(material.id!);
      ref.invalidate(rawMaterialsProvider);
      ref.invalidate(dashboardStatsProvider);
    }
  }
}

class _RawMaterialDialog extends ConsumerStatefulWidget {
  final RawMaterial? material;

  const _RawMaterialDialog({this.material});

  @override
  ConsumerState<_RawMaterialDialog> createState() => _RawMaterialDialogState();
}

class _RawMaterialDialogState extends ConsumerState<_RawMaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _unitController;
  late final TextEditingController _minAlertController;
  final _initialStockController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.material?.name);
    _unitController = TextEditingController(text: widget.material?.unit);
    _minAlertController =
        TextEditingController(text: widget.material?.minAlertLevel.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _minAlertController.dispose();
    _initialStockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final material = RawMaterial(
        id: widget.material?.id,
        name: _nameController.text.trim(),
        unit: _unitController.text.trim(),
        minAlertLevel: double.tryParse(_minAlertController.text) ?? 0,
      );

      if (widget.material == null) {
        // Create
        final id = await RawMaterialRepository.insert(material);

        // Handle Initial Stock
        final initialStock = double.tryParse(_initialStockController.text) ?? 0;
        if (initialStock > 0) {
          // Create Inward Transaction (Opening Stock)
          await DatabaseService.insert('inward', {
            'raw_material_id': id,
            'date': DateTime.now().toIso8601String(),
            'bag_size': 1.0, // Fixed: package_size -> bag_size
            'bag_count': initialStock, // Fixed: quantity -> bag_count
            'total_weight': initialStock, // Fixed: total -> total_weight
            'notes': 'Opening Stock',
          });
        }
      } else {
        // Update
        await RawMaterialRepository.update(material);
      }

      ref.invalidate(rawMaterialsProvider);
      ref.invalidate(dashboardStatsProvider);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        String message = 'Error saving material';
        if (e.toString().contains('UNIQUE constraint failed') ||
            e.toString().contains('2067')) {
          message = 'Material "${_nameController.text}" already exists';
        } else {
          message = 'Error: $e';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title:
              Text(widget.material == null ? 'Add Material' : 'Edit Material'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration:
                        const InputDecoration(labelText: 'Material Name *'),
                    validator: (value) =>
                        Validators.required(value, fieldName: 'Name'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _unitController,
                          decoration: const InputDecoration(
                            labelText: 'Unit *',
                            hintText: 'e.g. kg, ltr, pcs',
                          ),
                          validator: (value) =>
                              Validators.required(value, fieldName: 'Unit'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Preset units suggestion
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (val) => _unitController.text = val,
                        itemBuilder: (context) => [
                          'kg',
                          'ltr',
                          'pcs',
                          'boxes',
                          'tons'
                        ]
                            .map((u) => PopupMenuItem(value: u, child: Text(u)))
                            .toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _minAlertController,
                    decoration: const InputDecoration(
                      labelText: 'Min Alert Level',
                      helperText: 'Alert when stock falls below',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) => Validators.nonNegativeNumber(value,
                        fieldName: 'Alert Level'),
                  ),
                  if (widget.material == null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _initialStockController,
                      decoration: const InputDecoration(
                        labelText: 'Initial Stock',
                        helperText: 'Current quantity on hand (Opening Stock)',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => Validators.nonNegativeNumber(value,
                          fieldName: 'Initial Stock'),
                    ),
                  ],
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
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
