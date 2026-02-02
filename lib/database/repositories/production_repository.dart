import '../../database/database_service.dart';
import '../../models/production.dart';

class ProductionRepository {
  /// Get all production records
  static Future<List<Production>> getAll() async {
    final results = await DatabaseService.query('production',
        orderBy: 'date DESC, id DESC');
    return results.map((e) => Production.fromJson(e)).toList();
  }

  /// Get production records by date
  static Future<List<Production>> getByDate(DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    final results = await DatabaseService.rawQuery('''
      SELECT 
        p.*, 
        pr.name as product_name, 
        pr.unit as product_unit
      FROM production p
      LEFT JOIN products pr ON p.product_id = pr.id
      WHERE p.date = ?
      ORDER BY p.id DESC
    ''', [dateStr]);

    final List<Production> items = [];
    for (final row in results) {
      var production = Production.fromJson(row);
      final workerIds = await getWorkerIds(production.id!);
      print(
          'DEBUG: Fetched ${workerIds.length} workers for production ${production.id}');
      production = production.copyWith(workerIds: workerIds);
      items.add(production);
    }

    return items;
  }

  /// Get production records by date range
  static Future<List<Production>> getByDateRange(
      DateTime startDate, DateTime endDate) async {
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];

    final results = await DatabaseService.rawQuery('''
      SELECT 
        p.*, 
        pr.name as product_name, 
        pr.unit as product_unit
      FROM production p
      LEFT JOIN products pr ON p.product_id = pr.id
      WHERE p.date BETWEEN ? AND ?
      ORDER BY p.date DESC, p.id DESC
    ''', [startStr, endStr]);

    final List<Production> items = [];
    for (final row in results) {
      var production = Production.fromJson(row);
      final workerIds = await getWorkerIds(production.id!);
      production = production.copyWith(workerIds: workerIds);
      items.add(production);
    }

    return items;
  }

  /// Get daily production stats for the last N days
  /// Returns a list of maps {date: String, total_output: double}
  static Future<List<Map<String, dynamic>>> getDailyProductionStats(
      int days) async {
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr = startDate.toIso8601String().split('T')[0];

    print('🔍 ProductionRepository.getDailyProductionStats:');
    print(
        '  Querying from: $startDateStr to ${now.toIso8601String().split('T')[0]}');

    // We want all dates even if 0 production, but standard SQL in sqflite
    // makes generating a date series harder without a date table.
    // For now, we will query existing data and fill gaps in Dart code.

    final results = await DatabaseService.rawQuery('''
      SELECT date, SUM(total_quantity) as total_output
      FROM production
      WHERE date >= ?
      GROUP BY date
      ORDER BY date ASC
    ''', [startDateStr]);

    print('  Query returned ${results.length} rows');
    for (var row in results) {
      print('    ${row['date']}: ${row['total_output']} units');
    }

    return results;
  }

  /// Insert production entry
  static Future<int> insert(Production production) async {
    return await DatabaseService.transaction((txn) async {
      final id = await txn.insert('production', production.toJson());

      if (production.workerIds != null && production.workerIds!.isNotEmpty) {
        print(
            'DEBUG: Inserting ${production.workerIds!.length} workers for production ID $id');
        for (final workerId in production.workerIds!) {
          print('DEBUG: Inserting worker $workerId');
          await txn.insert('production_workers', {
            'production_id': id,
            'worker_id': workerId,
          });
        }
      } else {
        print('DEBUG: No workers to insert for production ID $id');
      }
      return id;
    });
  }

  /// Update production entry
  static Future<int> update(Production production) async {
    if (production.id == null)
      throw Exception('Production ID is required for update');

    return await DatabaseService.transaction((txn) async {
      final rows = await txn.update(
        'production',
        production.toJson(),
        where: 'id = ?',
        whereArgs: [production.id],
      );

      // Update workers
      await txn.delete(
        'production_workers',
        where: 'production_id = ?',
        whereArgs: [production.id],
      );

      if (production.workerIds != null && production.workerIds!.isNotEmpty) {
        for (final workerId in production.workerIds!) {
          await txn.insert('production_workers', {
            'production_id': production.id,
            'worker_id': workerId,
          });
        }
      }

      return rows;
    });
  }

  /// Delete production entry
  static Future<int> delete(int id) async {
    // Delete related records first
    await DatabaseService.delete(
      'production_workers',
      where: 'production_id = ?',
      whereArgs: [id],
    );
    await DatabaseService.delete(
      'production_raw_materials',
      where: 'production_id = ?',
      whereArgs: [id],
    );

    // Delete main production record
    return await DatabaseService.delete(
      'production',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get worker IDs for a production entry
  static Future<List<int>> getWorkerIds(int productionId) async {
    final results = await DatabaseService.rawQuery('''
      SELECT worker_id FROM production_workers WHERE production_id = ?
    ''', [productionId]);
    return results.map((row) => row['worker_id'] as int).toList();
  }

  /// Get raw material usage for a production entry
  /// Returns List of Maps with keys: raw_material_id, quantity_used
  static Future<List<Map<String, dynamic>>> getRawMaterialUsage(
      int productionId) async {
    return await DatabaseService.rawQuery('''
      SELECT raw_material_id, quantity_used, bag_size
      FROM production_raw_materials 
      WHERE production_id = ?
    ''', [productionId]);
  }
}
