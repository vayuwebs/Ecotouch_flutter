import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../models/category.dart';
import '../../../models/product.dart';
import '../../../models/raw_material.dart';
import '../../../database/repositories/category_repository.dart';
import '../../../database/repositories/product_repository.dart';
import '../../../providers/global_providers.dart';
import '../../../utils/validators.dart';
import 'package:flutter/services.dart';

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  return await CategoryRepository.getAll();
});

final productsByCategoryProvider =
    FutureProvider.family<List<Product>, int?>((ref, categoryId) async {
  if (categoryId == null) {
    return await ProductRepository.getAll();
  }
  return await ProductRepository.getByCategory(categoryId);
});

class CategoriesManagement extends ConsumerStatefulWidget {
  const CategoriesManagement({super.key});

  @override
  ConsumerState<CategoriesManagement> createState() =>
      _CategoriesManagementState();
}

class _CategoriesManagementState extends ConsumerState<CategoriesManagement> {
  Category? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync =
        ref.watch(productsByCategoryProvider(_selectedCategory?.id));

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Categories Panel
          Expanded(
            flex: 2, // Increased flex from 1
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Categories',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _showCategoryDialog(context),
                      icon: const Icon(Icons.add_circle_outline,
                          color: AppColors.primaryBlue),
                      tooltip: 'Add Category',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: categoriesAsync.when(
                    data: (categories) {
                      if (categories.isEmpty) {
                        return Card(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.category_outlined,
                                    size: 48,
                                    color: Theme.of(context)
                                        .iconTheme
                                        .color
                                        ?.withOpacity(0.5)),
                                const SizedBox(height: 16),
                                const Text('No categories yet'),
                                TextButton(
                                  onPressed: () => _showCategoryDialog(context),
                                  child: const Text('Add Category'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Card(
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppTheme.borderRadius),
                          child: ListView.separated(
                            itemCount: categories.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 0),
                            itemBuilder: (context, index) {
                              final category = categories[index];
                              final isSelected =
                                  _selectedCategory?.id == category.id;

                              return ListTile(
                                selected: isSelected,
                                selectedTileColor:
                                    AppColors.primaryBlue.withOpacity(0.1),
                                leading: Icon(
                                  Icons.label_outline,
                                  color: isSelected
                                      ? AppColors.primaryBlue
                                      : Theme.of(context)
                                          .iconTheme
                                          .color
                                          ?.withOpacity(0.7),
                                ),
                                title: Text(
                                  category.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? AppColors.primaryBlue
                                        : Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.color,
                                  ),
                                ),
                                trailing: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  tooltip: 'Actions',
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _showCategoryDialog(context,
                                          category: category);
                                    } else if (value == 'delete') {
                                      _deleteCategory(context, category);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [
                                        Icon(Icons.edit, size: 18),
                                        SizedBox(width: 8),
                                        Text('Edit')
                                      ]),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(children: [
                                        Icon(Icons.delete_outline,
                                            size: 18, color: AppColors.error),
                                        SizedBox(width: 8),
                                        Text('Delete',
                                            style: TextStyle(
                                                color: AppColors.error))
                                      ]),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(() => _selectedCategory = category);
                                },
                              );
                            },
                          ),
                        ),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Center(
                      child: Text('Error: $error',
                          style: const TextStyle(color: AppColors.error)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 32),

          // Products Panel
          Expanded(
            flex: 4, // Increased width
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedCategory != null
                              ? _selectedCategory!.name
                              : 'All Products',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_selectedCategory != null)
                          Text(
                            'Manage products in this category',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: productsAsync.when(
                    data: (products) {
                      if (_selectedCategory == null) {
                        return Card(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.touch_app_outlined,
                                    size: 64,
                                    color: Theme.of(context)
                                        .iconTheme
                                        .color
                                        ?.withOpacity(0.3)),
                                const SizedBox(height: 16),
                                Text(
                                  'Select a category from the left to view products',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.color),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.borderRadius),
                          side:
                              BorderSide(color: Theme.of(context).dividerColor),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton.icon(
                                  onPressed: () => _showProductDialog(context),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Product'),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                    AppTheme.borderRadius),
                                child: SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                        minWidth:
                                            MediaQuery.of(context).size.width *
                                                0.6),
                                    child: DataTable(
                                      columnSpacing: 40,
                                      columns: const [
                                        DataColumn(label: Text('Product Name')),
                                        DataColumn(label: Text('Unit')),
                                        DataColumn(label: Text('Stock')),
                                        DataColumn(label: Text('Actions')),
                                      ],
                                      rows: products.map((product) {
                                        return DataRow(cells: [
                                          DataCell(Text(product.name,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w500))),
                                          DataCell(Text(product.unit ?? '-')),
                                          DataCell(
                                              Text('${product.initialStock}')),
                                          DataCell(Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit,
                                                    size: 18),
                                                onPressed: () =>
                                                    _showProductDialog(context,
                                                        product: product),
                                                tooltip: 'Edit',
                                                color: AppColors.primaryBlue,
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 18),
                                                onPressed: () => _deleteProduct(
                                                    context, product),
                                                tooltip: 'Delete',
                                                color: AppColors.error,
                                              ),
                                            ],
                                          )),
                                        ]);
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Center(
                      child: Text('Error: $error',
                          style: const TextStyle(color: AppColors.error)),
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

  void _showCategoryDialog(BuildContext context, {Category? category}) {
    showDialog(
      context: context,
      builder: (context) => _CategoryDialog(category: category),
    ).then((_) => ref.invalidate(categoriesProvider));
  }

  void _showProductDialog(BuildContext context, {Product? product}) {
    if (_selectedCategory == null) return;

    showDialog(
      context: context,
      builder: (context) => _ProductDialog(
        categoryId: _selectedCategory!.id!,
        product: product,
      ),
    ).then((_) {
      ref.invalidate(productsByCategoryProvider(_selectedCategory?.id));
      ref.invalidate(productsProvider);
    });
  }

  Future<void> _deleteCategory(BuildContext context, Category category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete "${category.name}"?'),
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

    if (confirm == true && category.id != null) {
      try {
        await CategoryRepository.delete(category.id!);
        ref.invalidate(categoriesProvider);
        if (_selectedCategory?.id == category.id) {
          setState(() => _selectedCategory = null);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(e.toString().replaceAll('Exception: ', '')),
                backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _deleteProduct(BuildContext context, Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
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

    if (confirm == true && product.id != null) {
      try {
        await ProductRepository.delete(product.id!);
        ref.invalidate(productsByCategoryProvider(_selectedCategory?.id));
        ref.invalidate(productsProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(e.toString().replaceAll('Exception: ', '')),
                backgroundColor: AppColors.error),
          );
        }
      }
    }
  }
}

class _CategoryDialog extends StatefulWidget {
  final Category? category;

  const _CategoryDialog({this.category});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final category = Category(
        id: widget.category?.id,
        name: _nameController.text.trim(),
      );

      if (widget.category == null) {
        await CategoryRepository.create(category);
      } else {
        await CategoryRepository.update(category);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
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
              Text(widget.category == null ? 'Add Category' : 'Edit Category'),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Category Name *'),
              validator: (value) =>
                  Validators.required(value, fieldName: 'Name'),
              autofocus: true,
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
        ),
      ),
    );
  }
}

class _ProductDialog extends ConsumerStatefulWidget {
  final int categoryId;
  final Product? product;

  const _ProductDialog({required this.categoryId, this.product});

  @override
  ConsumerState<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<_ProductDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _unitController;
  final _initialStockController = TextEditingController();
  late final TabController _tabController;

  // Recipe State
  List<Map<String, dynamic>> _recipeItems = [];
  bool _isLoadingRecipe = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name);
    _unitController =
        TextEditingController(text: widget.product?.unit ?? 'pieces');
    _initialStockController.text =
        (widget.product?.initialStock ?? 0).toString();

    _tabController = TabController(length: 2, vsync: this);

    if (widget.product != null) {
      _loadRecipe();
    }
  }

  Future<void> _loadRecipe() async {
    setState(() => _isLoadingRecipe = true);
    try {
      final items = await ProductRepository.getRecipe(widget.product!.id!);
      setState(() {
        _recipeItems = items.map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (e) {
      // ignore
    } finally {
      setState(() => _isLoadingRecipe = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _initialStockController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _addRecipeItem(int rawMaterialId, String name, String unit) {
    // Check if exists
    final exists =
        _recipeItems.any((item) => item['raw_material_id'] == rawMaterialId);
    if (!exists) {
      setState(() {
        _recipeItems.add({
          'raw_material_id': rawMaterialId,
          'raw_material_name': name,
          'raw_material_unit': unit,
          'quantity_ratio': 1.0,
        });
      });
    }
  }

  void _removeRecipeItem(int index) {
    setState(() {
      _recipeItems.removeAt(index);
    });
  }

  void _updateRecipeQuantity(int index, String value) {
    final qty = double.tryParse(value) ?? 0;
    _recipeItems[index]['quantity_ratio'] = qty;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      _tabController.animateTo(0); // Go to info tab if error
      return;
    }

    try {
      // Validate recipe items content
      // (optional)

      final product = Product(
        id: widget.product?.id,
        name: _nameController.text.trim(),
        categoryId: widget.categoryId,
        unit: _unitController.text.trim(),
        initialStock: double.tryParse(_initialStockController.text) ?? 0,
      );

      int productId;
      if (widget.product == null) {
        productId = await ProductRepository.create(product);
      } else {
        productId = widget.product!.id!;
        await ProductRepository.update(product);
      }

      // Save Recipe
      await ProductRepository.saveRecipe(productId, _recipeItems);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Add Ctrl+S shortcut
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: Text(widget.product == null ? 'Add Product' : 'Edit Product'),
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 600,
            height: 500,
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primaryBlue,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primaryBlue,
                  tabs: const [
                    Tab(text: 'Basic Info', icon: Icon(Icons.info_outline)),
                    Tab(
                        text: 'Recipe (BOM)',
                        icon: Icon(Icons.format_list_bulleted)),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Basic Info
                      _KeepAliveWrapper(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFormField(
                                  controller: _nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Product Name *',
                                    prefixIcon:
                                        Icon(Icons.shopping_bag_outlined),
                                  ),
                                  validator: (value) => Validators.required(
                                      value,
                                      fieldName: 'Name'),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _unitController,
                                        decoration: const InputDecoration(
                                          labelText: 'Unit *',
                                          prefixIcon:
                                              Icon(Icons.scale_outlined),
                                          hintText: 'e.g. pieces',
                                        ),
                                        validator: (value) =>
                                            Validators.required(value,
                                                fieldName: 'Unit'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons
                                          .arrow_drop_down_circle_outlined),
                                      onSelected: (val) =>
                                          _unitController.text = val,
                                      itemBuilder: (context) => [
                                        'pieces',
                                        'boxes',
                                        'kg',
                                        'tons',
                                        'sets',
                                        'Bag'
                                      ]
                                          .map((u) => PopupMenuItem(
                                              value: u, child: Text(u)))
                                          .toList(),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // Initial Stock (Only for new items usually, but editable here)
                                TextFormField(
                                  controller: _initialStockController,
                                  decoration: const InputDecoration(
                                    labelText: 'Initial/Current Stock',
                                    helperText: 'Opening stock level',
                                    prefixIcon:
                                        Icon(Icons.inventory_2_outlined),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) =>
                                      Validators.nonNegativeNumber(value,
                                          fieldName: 'Stock'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Tab 2: Recipe
                      _buildRecipeTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _save,
              child: const Text('Save Product'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeTab() {
    final rawMaterialsAsync = ref.watch(rawMaterialsProvider);

    // Local state for the dropdown selection
    RawMaterial? selectedMaterial;

    return StatefulBuilder(builder: (context, setState) {
      return Column(
        children: [
          // Add Material Row
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: rawMaterialsAsync.when(
              data: (materials) {
                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<RawMaterial>(
                        decoration: const InputDecoration(
                          labelText: 'Select Raw Material',
                          prefixIcon: Icon(Icons.science_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        value: selectedMaterial,
                        items: materials
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text('${m.name} (${m.unit})'),
                                ))
                            .toList(),
                        onChanged: (material) {
                          setState(() => selectedMaterial = material);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: selectedMaterial == null
                          ? null
                          : () {
                              _addRecipeItem(
                                  selectedMaterial!.id!,
                                  selectedMaterial!.name,
                                  selectedMaterial!.unit);
                              setState(() => selectedMaterial = null);
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Failed to load raw materials'),
            ),
          ),

          const Divider(height: 1),

          // List of items
          Expanded(
            child: _isLoadingRecipe
                ? const Center(child: CircularProgressIndicator())
                : _recipeItems.isEmpty
                    ? const Center(child: Text('No ingredients added yet.'))
                    : ListView.separated(
                        itemCount: _recipeItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _recipeItems[index];
                          return ListTile(
                            title: Text(item['raw_material_name']),
                            subtitle:
                                Text('Unit: ${item['raw_material_unit']}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: TextFormField(
                                    initialValue:
                                        item['quantity_ratio'].toString(),
                                    decoration: const InputDecoration(
                                      labelText: 'Qty',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (val) =>
                                        _updateRecipeQuantity(index, val),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: AppColors.error),
                                  onPressed: () => _removeRecipeItem(index),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      );
    });
  }
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
