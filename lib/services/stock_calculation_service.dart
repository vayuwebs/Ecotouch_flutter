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

  /// Calculate raw material stock grouped by bag size
  static Future<List<StockByBagSize>> calculateRawMaterialStockByBagSize(
      DateTime upToDate) async {
    final dateStr = app_date_utils.DateUtils.formatDateForDatabase(upToDate);

    // 1. Get inward entries grouped by material and bag size
    final inwardResults = await DatabaseService.rawQuery('''
      SELECT 
        i.raw_material_id,
        rm.name as material_name,
        rm.unit,
        i.bag_size,
        SUM(i.bag_count) as total_bags,
        SUM(i.total_weight) as total_weight
      FROM inward i
      INNER JOIN raw_materials rm ON i.raw_material_id = rm.id
      WHERE i.date <= ?
      GROUP BY i.raw_material_id, i.bag_size
      ORDER BY rm.name, i.bag_size
    ''', [dateStr]);

    // 2. Get production usage grouped by material AND bag size
    final usageResults = await DatabaseService.rawQuery('''
      SELECT 
        prm.raw_material_id, 
        prm.bag_size, 
        SUM(prm.quantity_used) as total_used
      FROM production_raw_materials prm
      INNER JOIN production p ON prm.production_id = p.id
      WHERE p.date <= ?
      GROUP BY prm.raw_material_id, prm.bag_size
    ''', [dateStr]);

    // Organize usage:
    // explicitUsageMap: {materialId: {bagSize: usedAmount}}
    // legacyUsageMap: {materialId: usedAmount} (where bag_size is null)
    final Map<int, Map<double, double>> explicitUsageMap = {};
    final Map<int, double> legacyUsageMap = {};

    for (final row in usageResults) {
      final materialId = row['raw_material_id'] as int;
      final usedAmount = (row['total_used'] as num?)?.toDouble() ?? 0;
      final bagSize = (row['bag_size'] as num?)?.toDouble();

      if (bagSize != null) {
        explicitUsageMap.putIfAbsent(materialId, () => {});
        explicitUsageMap[materialId]![bagSize] =
            (explicitUsageMap[materialId]![bagSize] ?? 0) + usedAmount;
      } else {
        legacyUsageMap[materialId] =
            (legacyUsageMap[materialId] ?? 0) + usedAmount;
      }
    }

    // 3. Process each inward group
    // We first convert database results to mutable objects to track remaining weight
    final List<Map<String, dynamic>> buckets = [];

    for (final row in inwardResults) {
      buckets.add(Map<String, dynamic>.from(row));
    }

    // Pass 1: Deduct Explicit Usage
    for (final bucket in buckets) {
      final materialId = bucket['raw_material_id'] as int;
      final bagSize = (bucket['bag_size'] as num).toDouble();
      double totalWeight = (bucket['total_weight'] as num).toDouble();

      final explicitUsed = explicitUsageMap[materialId]?[bagSize] ?? 0;

      // Subtract explicit usage
      double remainingWeight = totalWeight - explicitUsed;
      if (remainingWeight < 0)
        remainingWeight = 0; // Prevent negative stock from bad data

      bucket['current_weight'] = remainingWeight;
    }

    // Pass 2: Deduct Legacy Usage (Largest Stock First)
    // We prioritize deducting from the bucket with the most weight to minimize
    // the impact on smaller/newer batches (avoiding the "49 bags instead of 50" issue
    // due to fractional distribution).
    if (legacyUsageMap.isNotEmpty) {
      for (final kv in legacyUsageMap.entries) {
        final materialId = kv.key;
        double usageToDeduct = kv.value;

        // Get buckets for this material
        final materialBuckets = buckets
            .where((b) => (b['raw_material_id'] as int) == materialId)
            .toList();

        // Sort by current weight descending (Absorb usage into largest pile)
        materialBuckets.sort((a, b) => (b['current_weight'] as double)
            .compareTo(a['current_weight'] as double));

        for (final bucket in materialBuckets) {
          if (usageToDeduct <= 0) break;

          final currentWeight = bucket['current_weight'] as double;
          if (currentWeight > 0) {
            final deduct =
                usageToDeduct > currentWeight ? currentWeight : usageToDeduct;
            bucket['current_weight'] = currentWeight - deduct;
            usageToDeduct -= deduct;
          }
        }
      }
    }

    // 4. Convert to StockByBagSize objects
    final List<StockByBagSize> stockItems = [];

    for (final bucket in buckets) {
      final currentWeight = (bucket['current_weight'] as double);

      // Only show items with positive stock
      if (currentWeight > 0.01) {
        // 0.01 tolerance
        final bagSize = (bucket['bag_size'] as num).toDouble();

        // Calculate full bags only (floor division)
        // Add a small epsilon to handle floating point errors (e.g., 49.9999 -> 50.0)
        // This ensures 10 bags don't become 9 due to microscopic precision loss
        final fullBags = ((currentWeight + 0.01) / bagSize).floor();
        final fullBagsWeight = fullBags * bagSize;

        // Only show if there's at least one full bag
        if (fullBags > 0) {
          stockItems.add(StockByBagSize(
            materialId: bucket['raw_material_id'] as int,
            materialName: bucket['material_name'] as String,
            bagSize: bagSize,
            bagCount: fullBags,
            totalWeight: fullBagsWeight, // Weight of full bags only
            unit: bucket['unit'] as String,
            containerUnit: 'packs',
          ));
        }
      }
    }

    return stockItems;
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
