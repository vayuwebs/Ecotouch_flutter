import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Mock StockCalculationService logic
class StockCalculator {
  final Database db;
  StockCalculator(this.db);

  Future<List<Map<String, dynamic>>> calculateRawMaterialStockByBagSize(DateTime upToDate) async {
    final dateStr = upToDate.toIso8601String().split('T')[0];
    print('Calculating stock up to $dateStr');
    
    // Get inward entries grouped by material and bag size
    final inwardResults = await db.rawQuery('''
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
    
    print('DEBUG: Inward Results: $inwardResults');

    // Get production usage
    final usageResults = await db.rawQuery('''
      SELECT prm.raw_material_id, SUM(prm.quantity_used) as total_used
      FROM production_raw_materials prm
      INNER JOIN production p ON prm.production_id = p.id
      WHERE p.date <= ?
      GROUP BY prm.raw_material_id
    ''', [dateStr]);
    
    print('DEBUG: Usage Results: $usageResults');

    final Map<int, double> usageMap = {};
    for (final row in usageResults) {
      final materialId = row['raw_material_id'] as int;
      final totalUsed = (row['total_used'] as num?)?.toDouble() ?? 0;
      usageMap[materialId] = totalUsed;
    }
    
    final List<Map<String, dynamic>> stockItems = [];
    final Map<int, double> materialTotalInward = {};
    
    // First pass: calculate total inward for each material
    for (final row in inwardResults) {
      final materialId = row['raw_material_id'] as int;
      final totalWeight = (row['total_weight'] as num?)?.toDouble() ?? 0;
      materialTotalInward[materialId] = (materialTotalInward[materialId] ?? 0) + totalWeight;
    }
    
    print('DEBUG: Material Total Inward: $materialTotalInward');

    // Second pass: distribute usage
    for (final row in inwardResults) {
      final materialId = row['raw_material_id'] as int;
      final materialName = row['material_name'] as String;
      final bagSize = (row['bag_size'] as num).toDouble();
      final totalWeight = (row['total_weight'] as num).toDouble();
      
      final totalUsed = usageMap[materialId] ?? 0;
      final totalInward = materialTotalInward[materialId] ?? 1; // Avoid div by zero
      
      final proportionalUsage = (totalWeight / totalInward) * totalUsed;
      final remainingWeight = totalWeight - proportionalUsage;
      final remainingBags = (remainingWeight / bagSize).round();
      
      print('DEBUG: Process: $materialName ($bagSize kg) - Inward: $totalWeight, PropUsage: $proportionalUsage, RemWeight: $remainingWeight, RemBags: $remainingBags');

      if (remainingBags > 0) {
        stockItems.add({
          'materialName': materialName,
          'bagSize': bagSize,
          'bagCount': remainingBags,
          'remainingWeight': remainingWeight,
        });
      }
    }
    
    return stockItems;
  }
}

void main() async {
  // Init FFI
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

  // Create tables
  await db.execute('CREATE TABLE raw_materials (id INTEGER PRIMARY KEY, name TEXT, unit TEXT)');
  await db.execute('CREATE TABLE inward (id INTEGER PRIMARY KEY, raw_material_id INTEGER, date TEXT, bag_size REAL, bag_count INTEGER, total_weight REAL)');
  await db.execute('CREATE TABLE production (id INTEGER PRIMARY KEY, date TEXT)');
  await db.execute('CREATE TABLE production_raw_materials (id INTEGER PRIMARY KEY, production_id INTEGER, raw_material_id INTEGER, quantity_used REAL)');

  // Insert Data
  await db.insert('raw_materials', {'id': 1, 'name': 'Up Grey', 'unit': 'kg'});
  
  // 3. User Scenario: 2 different bag sizes.
  // Entry 1: 10kg bags. 201 bags (similar to user).
  await db.insert('inward', {
    'raw_material_id': 1,
    'date': '2026-02-01',
    'bag_size': 10.0,
    'bag_count': 201,
    'total_weight': 2010.0,
  });

  // Entry 2: 50kg bags. 1 bag.
  await db.insert('inward', {
    'raw_material_id': 1,
    'date': '2026-02-01',
    'bag_size': 50.0,
    'bag_count': 1,
    'total_weight': 50.0,
  });

  // Add small usage (5kg)
  await db.insert('production', {'id': 100, 'date': '2026-02-01'});
  await db.insert('production_raw_materials', {
    'production_id': 100,
    'raw_material_id': 1,
    'quantity_used': 5.0,
  });

  // Add large usage (just to test limit)
  // await db.insert('production_raw_materials', {
  //   'production_id': 100,
  //   'raw_material_id': 1,
  //   'quantity_used': 2000.0,
  // });


  final calc = StockCalculator(db);
  final items = await calc.calculateRawMaterialStockByBagSize(DateTime(2026, 2, 1));

  print('FINAL STOCK ITEMS:');
  for (final item in items) {
    print(item);
  }

  await db.close();
}
