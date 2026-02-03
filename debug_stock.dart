import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';

Future<void> main() async {
  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = join(Directory.current.path, 'assets', 'management.db');
  print('Opening DB at $dbPath');

  final db = await databaseFactory.openDatabase(dbPath);

  try {
    // 1. Check Inward Entries
    print('\n--- INWARD ENTRIES ---');
    final inward = await db.rawQuery('''
      SELECT id, raw_material_id, bag_size, date, bag_count 
      FROM inward 
      ORDER BY raw_material_id, bag_size
    ''');

    for (var row in inward) {
      print(row);
    }

    // 2. Check for "Exact Duplicates" (Same Material, Same Size, Same Date, Different ID)
    print('\n--- POTENTIAL DUPLICATES ---');
    final dups = await db.rawQuery('''
      SELECT raw_material_id, bag_size, date, COUNT(*) as count
      FROM inward
      GROUP BY raw_material_id, bag_size, date
      HAVING count > 1
    ''');

    if (dups.isEmpty) {
      print('No potential duplicates found based on Material+Size+Date.');
    } else {
      for (var row in dups) {
        print('Found Duplicate Candidates: $row');
        // Get details
        final details = await db.query('inward',
            where: 'raw_material_id = ? AND bag_size = ? AND date = ?',
            whereArgs: [row['raw_material_id'], row['bag_size'], row['date']]);
        for (var d in details) {
          print('  -> ID: ${d['id']}, Count: ${d['bag_count']}');
        }
      }
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    await db.close();
  }
}
