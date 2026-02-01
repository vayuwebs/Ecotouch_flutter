import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../models/worker.dart';
import '../../../providers/global_providers.dart';
import '../../../database/repositories/worker_repository.dart';
import '../../../utils/validators.dart';
import '../../../widgets/status_badge.dart';
import '../../attendance/attendance_screen.dart';
import '../../production/production_screen.dart';
import '../../dashboard/dashboard_screen.dart';

final workersProvider = FutureProvider<List<Worker>>((ref) async {
  return await WorkerRepository.getAll();
});

final workerTypeFilterProvider = StateProvider<WorkerType?>((ref) => null);

class WorkersManagement extends ConsumerStatefulWidget {
  const WorkersManagement({super.key});

  @override
  ConsumerState<WorkersManagement> createState() => _WorkersManagementState();
}

class _WorkersManagementState extends ConsumerState<WorkersManagement> {
  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(workersProvider);
    final typeFilter = ref.watch(workerTypeFilterProvider);

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
                    'Workers Management',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add and manage employees, drivers, and labourers',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showAddWorkerDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Worker'),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Type Filter Toggle
          Row(
            children: [
              _buildFilterChip('All Workers', typeFilter == null, () {
                ref.read(workerTypeFilterProvider.notifier).state = null;
              }),
              const SizedBox(width: 12),
              _buildFilterChip('Labourers', typeFilter == WorkerType.labour,
                  () {
                ref.read(workerTypeFilterProvider.notifier).state =
                    WorkerType.labour;
              }),
              const SizedBox(width: 12),
              _buildFilterChip('Drivers', typeFilter == WorkerType.driver, () {
                ref.read(workerTypeFilterProvider.notifier).state =
                    WorkerType.driver;
              }),
            ],
          ),
          const SizedBox(height: 24),

          // Workers Table
          Expanded(
            child: workersAsync.when(
              data: (workers) {
                final filteredWorkers = typeFilter == null
                    ? workers
                    : workers.where((w) => w.type == typeFilter).toList();

                if (filteredWorkers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 64,
                            color: Theme.of(context)
                                .iconTheme
                                .color
                                ?.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No workers found',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        if (typeFilter == null)
                          OutlinedButton.icon(
                            onPressed: () => _showAddWorkerDialog(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Add your first worker'),
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
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Role')),
                          DataColumn(label: Text('City')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: filteredWorkers.map((worker) {
                          return DataRow(cells: [
                            DataCell(Text(worker.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500))),
                            DataCell(StatusBadge(
                              label: worker.type.displayName,
                              type: StatusType.info,
                            )),
                            DataCell(Text(worker.city ?? '-')),
                            DataCell(Text(worker.phone ?? '-')),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    onPressed: () =>
                                        _showEditWorkerDialog(context, worker),
                                    tooltip: 'Edit',
                                    color: AppColors.primaryBlue,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18),
                                    onPressed: () => _deleteWorker(worker),
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

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryBlue
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : Theme.of(context).textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Future<void> _showAddWorkerDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => _WorkerDialog(
        onSave: (worker) async {
          await WorkerRepository.insert(worker);
          ref.invalidate(workersProvider);
          // Providers invalidation cleanup
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(labourersProvider);
        },
      ),
    );
  }

  Future<void> _showEditWorkerDialog(
      BuildContext context, Worker worker) async {
    await showDialog(
      context: context,
      builder: (context) => _WorkerDialog(
        worker: worker,
        onSave: (updatedWorker) async {
          await WorkerRepository.update(updatedWorker);
          ref.invalidate(workersProvider);
          // Providers invalidation cleanup
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(labourersProvider);
        },
      ),
    );
  }

  Future<void> _deleteWorker(Worker worker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Worker'),
        content: Text(
            'Are you sure you want to delete ${worker.name}? This cannot be undone.'),
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

    if (confirmed == true && worker.id != null) {
      await WorkerRepository.delete(worker.id!);
      ref.invalidate(workersProvider);
      // Providers invalidation cleanup
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(labourersProvider);
    }
  }
}

class _WorkerDialog extends StatefulWidget {
  final Worker? worker;
  final Future<void> Function(Worker) onSave;

  const _WorkerDialog({this.worker, required this.onSave});

  @override
  State<_WorkerDialog> createState() => _WorkerDialogState();
}

class _WorkerDialogState extends State<_WorkerDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _cityController;
  late TextEditingController _phoneController;
  late WorkerType _selectedType;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.worker?.name);
    _cityController = TextEditingController(text: widget.worker?.city);
    _phoneController = TextEditingController(text: widget.worker?.phone);
    _selectedType = widget.worker?.type ?? WorkerType.labour;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.worker == null ? 'Add Worker' : 'Edit Worker'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) =>
                    Validators.required(value, fieldName: 'Name'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<WorkerType>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Role / Type *',
                  prefixIcon: Icon(Icons.work_outline),
                ),
                items: WorkerType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedType = value);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'City / Location',
                  prefixIcon: Icon(Icons.location_city),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final worker = Worker(
        id: widget.worker?.id,
        name: _nameController.text.trim(),
        type: _selectedType,
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
      );

      await widget.onSave(worker);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
