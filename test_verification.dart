import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Mock StockCalculationService logic (SIMPLIFIED for test)
class StockCalculator {
  final Database db;
  StockCalculator(this.db);

  Future<List<Map<String, dynamic>>> calculateRawMaterialStockByBagSize(DateTime upToDate) async {
    final dateStr = upToDate.toIso8601String().split('T')[0];
    print('Calculating stock up to $dateStr');
    
    // Inward
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
    ''', [dateStr]);
    
    // Usage
    final usageResults = await db.rawQuery('''
      SELECT 
        prm.raw_material_id, 
        prm.bag_size, 
        SUM(prm.quantity_used) as total_used
      FROM production_raw_materials prm
      INNER JOIN production p ON prm.production_id = p.id
      WHERE p.date <= ?
      GROUP BY prm.raw_material_id, prm.bag_size
    ''', [dateStr]);
    
    final Map<int, Map<double, double>> explicitUsageMap = {};
    for (final row in usageResults) {
      final materialId = row['raw_material_id'] as int;
      final usedAmount = (row['total_used'] as num?)?.toDouble() ?? 0;
      final bagSize = (row['bag_size'] as num?)?.toDouble();
      if (bagSize != null) {
        explicitUsageMap.putIfAbsent(materialId, () => {});
        explicitUsageMap[materialId]![bagSize] = (explicitUsageMap[materialId]![bagSize] ?? 0) + usedAmount;
      }
    }

    final List<Map<String, dynamic>> stockItems = [];
    
    for (final row in inwardResults) {
      final materialId = row['raw_material_id'] as int;
      final bagSize = (row['bag_size'] as num).toDouble();
      double totalWeight = (row['total_weight'] as num).toDouble();
      
      final explicitUsed = explicitUsageMap[materialId]?[bagSize] ?? 0;
      final remainingWeight = totalWeight - explicitUsed;

      if (remainingWeight > 0) {
        stockItems.add({
          'bagSize': bagSize,
          'remainingWeight': remainingWeight,
        });
      }
    }
    
    return stockItems;
  }
}

void main() async {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

  // Schema
  await db.execute('CREATE TABLE raw_materials (id INTEGER PRIMARY KEY, name TEXT, unit TEXT)');
  await db.execute('CREATE TABLE inward (id INTEGER PRIMARY KEY, raw_material_id INTEGER, date TEXT, bag_size REAL, bag_count INTEGER, total_weight REAL)');
  await db.execute('CREATE TABLE production (id INTEGER PRIMARY KEY, date TEXT)');
  await db.execute('CREATE TABLE production_raw_materials (id INTEGER PRIMARY KEY, production_id INTEGER, raw_material_id INTEGER, quantity_used REAL, bag_size REAL)');

  // Data
  await db.insert('raw_materials', {'id': 1, 'name': 'Up Grey', 'unit': 'kg'});
  
  // 1. Inward: 10kg bags (100)
  await db.insert('inward', {
    'raw_material_id': 1, 'date': '2026-02-01', 'bag_size': 10.0, 'bag_count': 100, 'total_weight': 1000.0,
  });
  // 2. Inward: 50kg bags (10)
  await db.insert('inward', {
    'raw_material_id': 1, 'date': '2026-02-01', 'bag_size': 50.0, 'bag_count': 10, 'total_weight': 500.0,
  });

  // 3. Consume from 50kg bag (Explicitly)
  await db.insert('production', {'id': 1, 'date': '2026-02-01'});
  await db.insert('production_raw_materials', {
    'production_id': 1, 'raw_material_id': 1, 'quantity_used': 50.0, 'bag_size': 50.0
  });

  final calc = StockCalculator(db);
  final items = await calc.calculateRawMaterialStockByBagSize(DateTime(2026, 2, 1));

  print('FINAL STOCK:');
  for (final item in items) {
    print(item);
  }
  
  // Expectation:
  // 10kg bags: 1000kg (unchanged)
  // 50kg bags: 500 - 50 = 450kg
  
  await db.close();
}
