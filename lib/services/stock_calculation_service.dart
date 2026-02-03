import '../database/database_service.dart';
import '../models/stock_item.dart';
import '../models/stock_by_bag_size.dart';
import '../utils/date_utils.dart' as app_date_utils;

class StockCalculationService {
  /// Calculate raw material stock up to a specific date using FIFO
  static Future<Map<int, double>> calculateRawMaterialStock(
      DateTime upToDate) async {
    final dateStr = app_date_utils.DateUtils.formatDateForDatabase(upToDate);

    // Get all inward entries up to date
    final inwardResults = await DatabaseService.rawQuery('''
      SELECT raw_material_id, SUM(total_weight) as total_inward
      FROM inward
      WHERE date <= ?
      GROUP BY raw_material_id
    ''', [dateStr]);

    // Get all production usage up to date
    final usageResults = await DatabaseService.rawQuery('''
      SELECT prm.raw_material_id, SUM(prm.quantity_used) as total_used
      FROM production_raw_materials prm
      INNER JOIN production p ON prm.production_id = p.id
      WHERE p.date <= ?
      GROUP BY prm.raw_material_id
    ''', [dateStr]);

    // Calculate stock
    final Map<int, double> stock = {};

    // Add inward quantities
    for (final row in inwardResults) {
      final materialId = row['raw_material_id'] as int;
      final totalInward = (row['total_inward'] as num?)?.toDouble() ?? 0;
      stock[materialId] = totalInward;
    }

    // Subtract usage
    for (final row in usageResults) {
      final materialId = row['raw_material_id'] as int;
      final totalUsed = (row['total_used'] as num?)?.toDouble() ?? 0;
      stock[materialId] = (stock[materialId] ?? 0) - totalUsed;
    }

    return stock;
  }

  /// Calculate product stock up to a specific date using FIFO
  static Future<Map<int, double>> calculateProductStock(
      DateTime upToDate) async {
    final dateStr = app_date_utils.DateUtils.formatDateForDatabase(upToDate);

    // Get all production up to date
    final productionResults = await DatabaseService.rawQuery('''
      SELECT product_id, SUM(total_quantity) as total_produced
      FROM production
      WHERE date <= ?
      GROUP BY product_id
    ''', [dateStr]);

    // Get all outward (sales) up to date
    final outwardResults = await DatabaseService.rawQuery('''
      SELECT product_id, SUM(total_weight) as total_sold
      FROM outward
      WHERE date <= ?
      GROUP BY product_id
    ''', [dateStr]);

    // Calculate stock
    final Map<int, double> stock = {};

    // Add production quantities
    for (final row in productionResults) {
      final productId = row['product_id'] as int;
      final totalProduced = (row['total_produced'] as num?)?.toDouble() ?? 0;
      stock[productId] = totalProduced;
    }

    // Subtract sales
    for (final row in outwardResults) {
      final productId = row['product_id'] as int;
      final totalSold = (row['total_sold'] as num?)?.toDouble() ?? 0;
      stock[productId] = (stock[productId] ?? 0) - totalSold;
    }

    return stock;
  }

  /// Calculate raw material stock grouped by specific Inward Batch (Strict Allocation)
  static Future<List<StockByBagSize>> calculateRawMaterialStockByBagSize(
      DateTime upToDate) async {
    final dateStr = app_date_utils.DateUtils.formatDateForDatabase(upToDate);

    // 1. Get all Inward Entries (Treating each entry as a distinct batch)
    final inwardResults = await DatabaseService.rawQuery('''
      SELECT 
        i.id as inward_id,
        i.raw_material_id,
        rm.name as material_name,
        rm.unit,
        i.bag_size,
        i.bag_count as initial_bags,
        i.total_weight as initial_weight,
        i.date as inward_date
      FROM inward i
      INNER JOIN raw_materials rm ON i.raw_material_id = rm.id
      WHERE i.date <= ?
      ORDER BY i.date ASC, i.id ASC
    ''', [dateStr]);

    print('DEBUG: StockCalc - Date: $dateStr');
    print('DEBUG: StockCalc - Inward Rows Found: ${inwardResults.length}');

    // 2. Get Production Usage grouped by Inward Source (Strict Mapping)
    final usageResults = await DatabaseService.rawQuery('''
      SELECT 
        prm.inward_entry_id,
        SUM(prm.quantity_used) as total_weight_used,
        SUM(CASE WHEN prm.bag_size IS NOT NULL THEN prm.quantity_used ELSE 0 END) as total_bags_implied_weight
      FROM production_raw_materials prm
      INNER JOIN production p ON prm.production_id = p.id
      WHERE p.date <= ? AND prm.inward_entry_id IS NOT NULL
      GROUP BY prm.inward_entry_id
    ''', [dateStr]);

    // Map usage by Inward ID
    final Map<int, double> usageMap = {};
    for (final row in usageResults) {
      final inwardId = row['inward_entry_id'] as int;
      final usedWeight = (row['total_weight_used'] as num?)?.toDouble() ?? 0;
      usageMap[inwardId] = usedWeight;
    }

    // 3. Calculate Remaining Stock per Batch
    final List<StockByBagSize> stockBatches = [];

    for (final row in inwardResults) {
      final inwardId = row['inward_id'] as int;
      final materialId = row['raw_material_id'] as int;
      final materialName = row['material_name'] as String;
      final unit = row['unit'] as String;
      final bagSize = (row['bag_size'] as num).toDouble();
      final initialBags = (row['initial_bags'] as int); // Explicit integer
      final initialWeight = (row['initial_weight'] as num).toDouble();
      final inwardDateStr = row['inward_date'] as String;
      final inwardDate = DateTime.tryParse(inwardDateStr);

      final usedWeight = usageMap[inwardId] ?? 0;

      // Strict deduction:
      // We track Weight primarily, but derive Bags.
      // Constraint: Bags must be integers.
      // If usedWeight matches specific bags (e.g. 50kg for 2x25kg), bags reduce.
      // For fractional usage (adjustment/spillage), weight reduces, but bag count logic is stricter.

      // Logic:
      // remainingWeight = initialWeight - usedWeight
      // remainingBags = floor(remainingWeight / bagSize) (Simple and robust)

      final remainingWeight = initialWeight - usedWeight;

      if (remainingWeight > 0.05) {
        // Tolerance 0.05
        // Calculate remaining complete bags
        // Using floor to strictly enforce integer bags available for consumption
        // Adding tiny epsilon to handle float precision issues where 50.0 might be 49.99999
        final remainingBags = ((remainingWeight + 0.001) / bagSize).floor();

        if (remainingBags > 0) {
          stockBatches.add(StockByBagSize(
            materialId: materialId,
            materialName: materialName,
            bagSize: bagSize,
            bagCount: remainingBags,
            totalWeight:
                remainingBags * bagSize, // Display weight of available bags
            unit: unit,
            containerUnit: 'packs', // or bags
            inwardEntryId: inwardId,
            inwardDate: inwardDate,
          ));
        }
      }
    }

    print('DEBUG: StockCalc - Final Batches: ${stockBatches.length}');
    for (var b in stockBatches) {
      print(
          'DEBUG: Batch #${b.inwardEntryId} - Mat: ${b.materialId} - Bags: ${b.bagCount}');
    }
    return stockBatches;
  }

  /// Calculate product stock grouped by bag size (unit size)
  static Future<List<StockByBagSize>> calculateProductStockByBagSize(
      DateTime upToDate) async {
    final dateStr = app_date_utils.DateUtils.formatDateForDatabase(upToDate);

    // 1. Get total production grouped by product and unit size
    final productionResults = await DatabaseService.rawQuery('''
      SELECT 
        p.product_id, 
        pr.name as product_name,
        pr.unit as product_unit,
        uc.to_unit as inner_unit,
        p.unit_size, 
        SUM(p.unit_count) as total_units_produced
      FROM production p
      INNER JOIN products pr ON p.product_id = pr.id
      LEFT JOIN unit_conversions uc ON pr.unit = uc.from_unit
      WHERE p.date <= ?
      GROUP BY p.product_id, p.unit_size
    ''', [dateStr]);

    // 2. Get outward entries (sales) grouped by product and bag size
    final outwardResults = await DatabaseService.rawQuery('''
      SELECT 
        product_id,
        bag_size,
        SUM(bag_count) as total_units_sold
      FROM outward
      WHERE date <= ?
      GROUP BY product_id, bag_size
    ''', [dateStr]);

    // Map outward sales for easy lookup: {productId: {bagSize: soldCount}}
    final Map<int, Map<double, double>> salesMap = {};
    for (final row in outwardResults) {
      final productId = row['product_id'] as int;
      final bagSize = (row['bag_size'] as num?)?.toDouble();
      final soldCount = (row['total_units_sold'] as num?)?.toDouble() ?? 0;

      if (bagSize != null) {
        salesMap.putIfAbsent(productId, () => {});
        salesMap[productId]![bagSize] =
            (salesMap[productId]![bagSize] ?? 0) + soldCount;
      }
    }

    final List<StockByBagSize> stockItems = [];

    // 3. Process each production bucket (Unit Size)
    for (final row in productionResults) {
      final productId = row['product_id'] as int;
      final productName = row['product_name'] as String;
      final productUnit = row['product_unit'] as String? ?? 'units';
      final innerUnit = row['inner_unit'] as String?;
      final displayUnit =
          innerUnit ?? productUnit; // Prefer converted unit if available
      final unitSize = (row['unit_size'] as num?)?.toDouble();
      final totalProduced =
          (row['total_units_produced'] as num?)?.toDouble() ?? 0;

      if (totalProduced > 0) {
        // If unitSize is null (legacy data), we might need special handling.
        // For now, let's treat null as a distinct "Unknown Size" bucket or skip if we only care about sized items.
        // Assuming unit_size IS the bag_size for products.

        final effectiveSize = unitSize ?? 0.0;

        double soldCount = 0;
        if (salesMap.containsKey(productId)) {
          soldCount = salesMap[productId]?[effectiveSize] ?? 0;
        }

        final remainingCount = totalProduced - soldCount;

        if (remainingCount > 0) {
          stockItems.add(StockByBagSize(
            materialId: productId,
            materialName: productName,
            bagSize: effectiveSize,
            bagCount: remainingCount.round(),
            totalWeight:
                remainingCount * effectiveSize, // Total weight = count * size
            unit: displayUnit, // Display unit (lines/pieces)
            containerUnit: productUnit, // Container unit (box/bag)
          ));
        }
      }
    }

    // Note: If there are sales for a bag size that was NEVER produced (e.g. legacy mismatch),
    // they won't show up here as "negative stock" because we iterate over Production.
    // If negative stock display is desired, we would need to union keys from both maps.

    return stockItems;
  }

  /// Get raw material stock items with status
  static Future<List<StockItem>> getRawMaterialStockItems(
      DateTime upToDate) async {
    final stockLevels = await calculateRawMaterialStock(upToDate);
    final materials =
        await DatabaseService.query('raw_materials', orderBy: 'name ASC');

    final List<StockItem> items = [];
    for (final material in materials) {
      final id = material['id'] as int;
      final name = material['name'] as String;
      final unit = material['unit'] as String;
      final minAlertLevel =
          (material['min_alert_level'] as num?)?.toDouble() ?? 0;
      final currentStock = stockLevels[id] ?? 0;

      items.add(StockItem.fromRawMaterial(
        id: id,
        name: name,
        currentStock: currentStock,
        unit: unit,
        minAlertLevel: minAlertLevel,
      ));
    }

    return items;
  }

  /// Get product stock items with status
  static Future<List<StockItem>> getProductStockItems(DateTime upToDate) async {
    final stockLevels = await calculateProductStock(upToDate);
    final products = await DatabaseService.rawQuery('''
      SELECT 
        p.id, 
        p.name, 
        p.unit as product_unit,
        uc.to_unit as inner_unit
      FROM products p
      LEFT JOIN unit_conversions uc ON p.unit = uc.from_unit
      ORDER BY p.name ASC
    ''');

    final List<StockItem> items = [];
    final seenProductIds = <int>{};

    for (final product in products) {
      final id = product['id'] as int;

      // Skip if we've already processed this product (handling SQL duplicates)
      if (seenProductIds.contains(id)) continue;
      seenProductIds.add(id);

      final name = product['name'] as String;
      final productUnit = (product['product_unit'] as String?) ?? 'units';
      final innerUnit = product['inner_unit'] as String?;
      final displayUnit = innerUnit ?? productUnit;

      final currentStock = stockLevels[id] ?? 0;

      items.add(StockItem.fromRawMaterial(
        id: id,
        name: name,
        currentStock: currentStock,
        unit: displayUnit,
        minAlertLevel: 0, // Product alert level not yet implemented in DB
      ));
    }

    return items;
  }

  /// Validate if sufficient stock exists for production
  static Future<Map<String, dynamic>> validateProductionStock(
    int productId,
    int batches,
  ) async {
    // Get product recipe
    final recipe = await DatabaseService.rawQuery('''
      SELECT prm.raw_material_id, prm.quantity_ratio, rm.name as material_name
      FROM product_raw_materials prm
      INNER JOIN raw_materials rm ON prm.raw_material_id = rm.id
      WHERE prm.product_id = ?
    ''', [productId]);

    if (recipe.isEmpty) {
      return {'valid': false, 'message': 'Product has no recipe defined'};
    }

    // Get current stock
    final currentStock = await calculateRawMaterialStock(DateTime.now());

    // Check each material
    final List<String> insufficientMaterials = [];
    for (final item in recipe) {
      final materialId = item['raw_material_id'] as int;
      final materialName = item['material_name'] as String;
      final quantityRatio = (item['quantity_ratio'] as num).toDouble();
      final required = quantityRatio * batches;
      final available = currentStock[materialId] ?? 0;

      if (available < required) {
        insufficientMaterials
            .add('$materialName (need $required, have $available)');
      }
    }

    if (insufficientMaterials.isNotEmpty) {
      return {
        'valid': false,
        'message': 'Insufficient stock: ${insufficientMaterials.join(', ')}'
      };
    }

    return {'valid': true};
  }

  /// Validate if sufficient product stock exists for outward
  static Future<Map<String, dynamic>> validateOutwardStock(
    int productId,
    double quantity,
  ) async {
    final currentStock = await calculateProductStock(DateTime.now());
    final available = currentStock[productId] ?? 0;

    if (available < quantity) {
      return {
        'valid': false,
        'message':
            'Insufficient stock. Available: $available, Required: $quantity'
      };
    }

    return {'valid': true};
  }
}
