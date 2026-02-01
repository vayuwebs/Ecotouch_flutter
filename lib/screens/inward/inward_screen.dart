import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart' as app_date_utils;
import '../../utils/validators.dart';
import '../../database/repositories/inward_repository.dart';
import '../../models/inward.dart';
import '../../models/raw_material.dart';
import '../../providers/global_providers.dart';
import '../../providers/inventory_providers.dart';
import '../../providers/summary_providers.dart';
import '../../services/export_service.dart';
import '../../widgets/status_badge.dart';
import '../../services/export_service.dart';
import '../../widgets/export_dialog.dart';

final inwardListProvider =
    FutureProvider.family<List<Inward>, DateTime>((ref, date) async {
  return await InwardRepository.getByDate(date);
});

class InwardScreen extends ConsumerStatefulWidget {
  const InwardScreen({super.key});

  @override
  ConsumerState<InwardScreen> createState() => _InwardScreenState();
}

class _InwardScreenState extends ConsumerState<InwardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bagSizeController = TextEditingController();
  final _bagCountController = TextEditingController();
  final _notesController = TextEditingController();

  int? _editingId;
  RawMaterial? _selectedMaterial;
  double _total = 0;

  void _calculateTotal() {
    final bagSize = double.tryParse(_bagSizeController.text) ?? 0;
    final bagCount = int.tryParse(_bagCountController.text) ?? 0;
    setState(() {
      _total = bagSize * bagCount;
    });
  }

  Future<void> _handleExport() async {
    final config = await showDialog<ExportConfig>(
      context: context,
      builder: (c) => const ExportDialog(title: 'Export Inward History'),
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
      start = config.customRange!.start;
      end = config.customRange!.end;
    }

    try {
      final data = await InwardRepository.getByDateRange(start, end);

      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No inward records found for selected period')),
          );
        }
        return;
      }

      final headers = [
        'Date',
        'Material Name',
        'Pack Size (kg)',
        'Packs',
        'Total Weight (kg)',
        'Notes'
      ];
      final rows = data
          .map((e) => [
                app_date_utils.DateUtils.formatDate(e.date),
                e.materialName ?? 'Unknown',
                e.bagSize.toString(),
                e.bagCount.toString(),
                e.totalWeight.toStringAsFixed(2),
                e.notes ?? '-'
              ])
          .toList();

      final title =
          'Inward Report (${app_date_utils.DateUtils.formatDate(start)} - ${app_date_utils.DateUtils.formatDate(end)})';

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
    final inwardAsync = ref.watch(inwardListProvider(selectedDate));
    final materialsAsync = ref.watch(rawMaterialsProvider);

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
                      'Raw Material Inward',
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Record incoming raw material stock',
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
                                    ? 'New Supply Entry'
                                    : 'Edit Supply Entry',
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

                          // Material Dropdown
                          materialsAsync.when(
                            data: (materials) =>
                                DropdownButtonFormField<RawMaterial>(
                              value: _selectedMaterial,
                              decoration: const InputDecoration(
                                labelText: 'Raw Material *',
                                hintText: 'Select material...',
                                border: OutlineInputBorder(),
                              ),
                              items: materials.map((material) {
                                return DropdownMenuItem(
                                  value: material,
                                  child: Text(
                                      '${material.name} (${material.unit})'),
                                );
                              }).toList(),
                              onChanged: (material) {
                                setState(() => _selectedMaterial = material);
                              },
                              validator: (value) => value == null
                                  ? 'Please select a material'
                                  : null,
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (_, __) =>
                                const Text('Error loading materials'),
                          ),

                          const SizedBox(height: 20),

                          // Bag Size
                          TextFormField(
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

                          const SizedBox(height: 20),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _bagCountController,
                                  decoration: const InputDecoration(
                                    labelText: 'Number of Packs',
                                    suffixText: 'bags',
                                    helperText: 'Count',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) =>
                                      Validators.positiveInteger(value,
                                          fieldName: 'Bag Count'),
                                  onChanged: (_) => _calculateTotal(),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  height: 56, // Match input height roughly
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.primaryBlue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(
                                        4), // Match border radius default
                                    border: Border.all(
                                        color: AppColors.primaryBlue
                                            .withOpacity(0.3)),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Total Inward',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color,
                                        ),
                                      ),
                                      Text(
                                        '${_total.toStringAsFixed(2)} ${_selectedMaterial?.unit ?? ''}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primaryBlue,
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
                              labelText: 'Notes / Supplier Info',
                              hintText: 'Invoice no., supplier details...',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
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
                                  ? 'Add to Stock'
                                  : 'Update Entry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
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
                                  'Inward History (Today)',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontSize: 18),
                                ),
                                const Spacer(),
                                StatusBadge(
                                  label:
                                      '${inwardAsync.value?.length ?? 0} Entries',
                                  type: StatusType.neutral,
                                ),
                              ],
                            ),
                          ),
                          Divider(
                              height: 1, color: Theme.of(context).dividerColor),

                          // Table
                          Expanded(
                            child: inwardAsync.when(
                              data: (inwardList) {
                                if (inwardList.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.arrow_downward,
                                            size: 48,
                                            color: Theme.of(context)
                                                .hintColor
                                                .withOpacity(0.3)),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No inward entries today',
                                          style: TextStyle(
                                              color:
                                                  Theme.of(context).hintColor),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: inwardList.length,
                                  separatorBuilder: (c, i) => Divider(
                                      height: 1,
                                      indent: 0,
                                      endIndent: 0,
                                      color: Theme.of(context).dividerColor),
                                  itemBuilder: (context, index) {
                                    final inward = inwardList[index];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  inward.materialName ??
                                                      'Unknown',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${inward.bagSize} ${inward.materialUnit ?? ''} × ${inward.bagCount} packs',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Theme.of(context)
                                                          .hintColor),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${inward.totalWeight.toStringAsFixed(2)} ${inward.materialUnit ?? ''}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: AppColors.success),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(inward.notes ?? '-',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Theme.of(context)
                                                            .hintColor)),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 18),
                                            onPressed: () =>
                                                _editInward(inward),
                                            tooltip: 'Edit',
                                            color: AppColors.primaryBlue,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18),
                                            onPressed: () =>
                                                _deleteInward(inward),
                                            tooltip: 'Delete',
                                            color: AppColors.error,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
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
    if (!_formKey.currentState!.validate() || _selectedMaterial == null) return;

    try {
      final selectedDate = ref.read(selectedDateProvider);

      final inward = Inward(
        id: _editingId,
        rawMaterialId: _selectedMaterial!.id!,
        date: selectedDate,
        bagSize: double.parse(_bagSizeController.text),
        bagCount: int.parse(_bagCountController.text),
        totalWeight: _total,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (_editingId != null) {
        await InwardRepository.update(inward);
      } else {
        await InwardRepository.insert(inward);
      }

      ref.invalidate(inwardListProvider(selectedDate));

      // Invalidate stock provider to refresh raw material stock levels
      ref.invalidate(rawMaterialStockProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_editingId != null
                ? 'Inward entry updated successfully'
                : 'Inward entry recorded successfully'),
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

  void _editInward(Inward inward) async {
    // Find material object
    final materials = await ref.read(rawMaterialsProvider.future);
    final material = materials.firstWhere(
      (m) => m.id == inward.rawMaterialId,
      orElse: () => RawMaterial(name: 'Unknown', unit: 'unit'),
    );

    setState(() {
      _editingId = inward.id;
      _selectedMaterial = material.id != null ? material : null;
      _bagSizeController.text = inward.bagSize.toString();
      _bagCountController.text = inward.bagCount.toString();
      _notesController.text = inward.notes ?? '';
      _total = inward.totalWeight;
    });
  }

  Future<void> _deleteInward(Inward inward) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: Text('Delete inward entry for ${inward.materialName}?'),
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

    if (confirm == true && inward.id != null) {
      await InwardRepository.delete(inward.id!);

      if (_editingId == inward.id) {
        _clearForm();
      }

      final selectedDate = ref.read(selectedDateProvider);
      ref.invalidate(inwardListProvider(selectedDate));
      ref.invalidate(rawMaterialStockProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Entry deleted'),
              backgroundColor: AppColors.success),
        );
      }
    }
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _selectedMaterial = null;
      _bagSizeController.clear();
      _bagCountController.clear();
      _notesController.clear();
      _total = 0;
    });
  }
}
