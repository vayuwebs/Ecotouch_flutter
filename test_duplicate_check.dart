import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'lib/database/database_service.dart';

void main() async {
  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  try {
    // Open DB
    final db = await DatabaseService.initDatabase('production_dashboard.db');

    print('--- Check Products ---');
    final products =
        await db.rawQuery("SELECT * FROM products WHERE name LIKE '%jh%'");
    for (var p in products) {
      print(p);
    }

    print('--- Check Raw Materials ---');
    final materials =
        await db.rawQuery("SELECT * FROM raw_materials WHERE name LIKE '%jh%'");
    for (var m in materials) {
      print(m);
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    await DatabaseService.closeDatabase();
  }
}
