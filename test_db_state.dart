import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = 'production_dashboard.db';
  final db = await databaseFactory.openDatabase(dbPath);

  try {
    // 1. Check Version
    final versionInfo = await db.rawQuery('PRAGMA user_version');
    print('Current Database Version: ${versionInfo.first.values.first}');

    // 2. Check Schema for UNIQUE constraint
    final schemaRes = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='products'");
    print('\nProducts Table Schema:');
    if (schemaRes.isNotEmpty) {
      print(schemaRes.first['sql']);
    } else {
      print('TABLE products DOES NOT EXIST!');
    }

    // 3. Check Row Counts
    final count = await db.rawQuery('SELECT COUNT(*) as c FROM products');
    print('\nTotal Products: ${count.first['c']}');

    // 4. Check for temp table debris
    final tempCheck = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='products_temp_v14'");
    if (tempCheck.isNotEmpty) {
      print('\nWARNING: products_temp_v14 still exists!');
    } else {
      print('\nproducts_temp_v14 was successfully dropped.');
    }

    // 5. List all products to see what remains
    print('\nListing all products:');
    final allProducts = await db
        .rawQuery("SELECT id, name, hex(name) as hex_name FROM products");
    for (var row in allProducts) {
      print(
          'ID: ${row['id']}, Name: "${row['name']}", Hex: ${row['hex_name']}');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    await db.close();
  }
}
