import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';

class DatabaseService {
  static Database? _database;
  static String? _currentDatabasePath;

  /// Get the current database instance
  static Future<Database> get database async {
    if (_database != null) return _database!;
    throw Exception('Database not initialized. Call initDatabase first.');
  }

  /// Initialize database at specified path
  static Future<Database> initDatabase(String databasePath) async {
    try {
      // Close existing database if open
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      // Ensure directory exists
      final directory = Directory(path.dirname(databasePath));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Open database
      _database = await openDatabase(
        databasePath,
        version: 18,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      );

      _currentDatabasePath = databasePath;
      return _database!;
    } catch (e) {
      throw Exception('Failed to initialize database: $e');
    }
  }

  /// Configure database (enable foreign keys)
  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Create database schema
  static Future<void> _onCreate(Database db, int version) async {
    try {
      // Read schema from SQL file
      final schema =
          await rootBundle.loadString('lib/database/database_schema.sql');

      // Remove comments and split by semicolon
      final lines = schema.split('\n');
      final cleanedLines = <String>[];

      for (final line in lines) {
        final trimmed = line.trim();
        // Skip comment lines and empty lines
        if (trimmed.isEmpty || trimmed.startsWith('--')) {
          continue;
        }
        cleanedLines.add(line);
      }

      final cleanedSQL = cleanedLines.join('\n');

      // Split by semicolon and execute each statement
      final statements = cleanedSQL.split(';');

      for (final statement in statements) {
        final trimmed = statement.trim();
        if (trimmed.isNotEmpty) {
          try {
            await db.execute(trimmed);
          } catch (e) {
            print('Error executing SQL statement: $e');
            print(
                'Statement: ${trimmed.substring(0, trimmed.length > 100 ? 100 : trimmed.length)}...');
            // Continue with other statements
          }
        }
      }

      // Create default account (password: admin)
      // Hash: bcrypt hash of "admin" (simplified for demo)
      await db.insert('accounts', {
        'password_hash':
            r'$2a$10$N9qo8uLOickgx2ZMRZoMye7FRNpZeS0BbIdPaBTMZx5NH.0EdB.Oa',
      });

      print('Database schema created successfully');
    } catch (e) {
      print('Failed to create database schema: $e');
      rethrow;
    }
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    print('Upgrading database from $oldVersion to $newVersion');
    if (oldVersion < 2) {
      // Products schema update
      // We use try-catch because SQLite doesn't strictly support IF NOT EXISTS on ADD COLUMN universally reliably across all versions/wrappers without it
      try {
        await db.execute('ALTER TABLE products ADD COLUMN unit TEXT');
      } catch (e) {
        print('Error adding unit to products (might exist): $e');
      }
      try {
        await db.execute(
            'ALTER TABLE products ADD COLUMN initial_stock REAL DEFAULT 0');
      } catch (e) {
        print('Error adding initial_stock to products: $e');
      }

      // Vehicles schema update
      try {
        await db.execute('ALTER TABLE vehicles ADD COLUMN model TEXT');
      } catch (e) {
        print('Error adding model to vehicles: $e');
      }
      try {
        await db.execute(
            'ALTER TABLE vehicles ADD COLUMN odometer_reading REAL DEFAULT 0');
      } catch (e) {
        print('Error adding odometer_reading to vehicles: $e');
      }
    }

    if (oldVersion < 3) {
      // Production schema update
      try {
        await db.execute('ALTER TABLE production ADD COLUMN unit_size REAL');
      } catch (e) {
        print('Error adding unit_size to production: $e');
      }
      try {
        await db.execute('ALTER TABLE production ADD COLUMN unit_count REAL');
      } catch (e) {
        print('Error adding unit_count to production: $e');
      }
    }

    if (oldVersion < 4) {
      // Unit conversions table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS unit_conversions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            from_unit TEXT NOT NULL,
            to_unit TEXT NOT NULL,
            conversion_factor REAL NOT NULL,
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(from_unit, to_unit)
          )
        ''');
      } catch (e) {
        print('Error creating unit_conversions table: $e');
      }
    }

    if (oldVersion < 5) {
      // Bag-based inventory: rename columns for semantic clarity
      try {
        // Inward table: package_size → bag_size, quantity → bag_count, total → total_weight
        await db.execute(
            'ALTER TABLE inward RENAME COLUMN package_size TO bag_size');
        await db
            .execute('ALTER TABLE inward RENAME COLUMN quantity TO bag_count');
        await db
            .execute('ALTER TABLE inward RENAME COLUMN total TO total_weight');

        // Outward table: quantity → bag_count, add total_weight column
        await db
            .execute('ALTER TABLE outward RENAME COLUMN quantity TO bag_count');
        await db.execute('ALTER TABLE outward ADD COLUMN total_weight REAL');

        // Calculate total_weight for existing outward entries
        await db.execute('''
          UPDATE outward 
          SET total_weight = bag_size * bag_count
        ''');
      } catch (e) {
        print('Error in version 5 migration: $e');
      }
    }

    if (oldVersion < 6) {
      // Version 6: Add bag_size for explicit production usage tracking
      try {
        await db.execute(
            'ALTER TABLE production_raw_materials ADD COLUMN bag_size REAL');
      } catch (e) {
        print('Error adding bag_size to production_raw_materials: $e');
      }
    }

    if (oldVersion < 7) {
      // Version 7: Logistics Refactor - Trips table overhaul
      try {
        await db.transaction((txn) async {
          // 1. Create new table without product/quantity, but with new fields
          await txn.execute('''
             CREATE TABLE trips_new (
               id INTEGER PRIMARY KEY AUTOINCREMENT,
               vehicle_id INTEGER NOT NULL,
               date TEXT NOT NULL,
               destination TEXT NOT NULL,
               start_km REAL DEFAULT 0,
               end_km REAL DEFAULT 0,
               start_time TEXT,
               end_time TEXT,
               fuel_cost REAL DEFAULT 0,
               other_cost REAL DEFAULT 0,
               created_at TEXT DEFAULT (datetime('now')),
               FOREIGN KEY(vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE
             )
           ''');

          // 2. Migrate existing data (map common fields)
          // We lose product_id and quantity as they are removed from the requirements
          // We map 'date' to 'date' (which is the main trip date)
          await txn.execute('''
             INSERT INTO trips_new (id, vehicle_id, date, destination, created_at)
             SELECT id, vehicle_id, date, destination, created_at FROM trips
           ''');

          // 3. Drop old table
          await txn.execute('DROP TABLE trips');

          // 4. Rename new table
          await txn.execute('ALTER TABLE trips_new RENAME TO trips');

          // 5. Recreate indexes
          await txn.execute('CREATE INDEX idx_trips_date ON trips(date)');
          await txn
              .execute('CREATE INDEX idx_trips_vehicle ON trips(vehicle_id)');
        });
        print('Migration to v7 (Logistics Refactor) completed successfully');
      } catch (e) {
        print('Error in version 7 migration: $e');
      }
    }
    // Continued...

    if (oldVersion < 8) {
      // Version 8: Add cost tracking
      try {
        await db.execute('ALTER TABLE inward ADD COLUMN total_cost REAL');
      } catch (e) {
        print('Error adding total_cost to inward: $e');
      }
      try {
        await db.execute(
            'ALTER TABLE outward ADD COLUMN price_per_unit REAL DEFAULT 0');
      } catch (e) {
        print('Error adding price_per_unit to outward: $e');
      }
    }

    if (oldVersion < 9) {
      // Version 9: Ensure product_raw_materials (BOM) table exists
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS product_raw_materials (
            product_id INTEGER NOT NULL,
            raw_material_id INTEGER NOT NULL,
            quantity_ratio REAL NOT NULL,
            FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE,
            FOREIGN KEY(raw_material_id) REFERENCES raw_materials(id) ON DELETE CASCADE,
            PRIMARY KEY(product_id, raw_material_id)
          )
        ''');
      } catch (e) {
        print('Error creating product_raw_materials table: $e');
      }
    }

    if (oldVersion < 11) {
      // Version 11: Remove UNIQUE constraint from unit_conversions to allow multiple factors
      // (Using v11 because v10 might have been skipped without migration code)
      try {
        await db.transaction((txn) async {
          // 1. Rename existing table
          await txn.execute(
              'ALTER TABLE unit_conversions RENAME TO unit_conversions_old');

          // 2. Create new table without UNIQUE constraint
          await txn.execute('''
            CREATE TABLE unit_conversions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              from_unit TEXT NOT NULL,
              to_unit TEXT NOT NULL,
              conversion_factor REAL NOT NULL,
              created_at TEXT DEFAULT (datetime('now'))
            )
          ''');

          // 3. Copy data
          await txn.execute('''
            INSERT INTO unit_conversions (id, from_unit, to_unit, conversion_factor, created_at)
            SELECT id, from_unit, to_unit, conversion_factor, created_at FROM unit_conversions_old
          ''');

          // 4. Drop old table
          await txn.execute('DROP TABLE unit_conversions_old');
        });
        print(
            'Migration to v11 (Unit Conversions Update) completed successfully');
      } catch (e) {
        print('Error in version 11 migration: $e');
      }
    }

    if (oldVersion < 13) {
      // Version 13: Remove duplicate products and add UNIQUE constraint to name
      // (Using v13 because v12 was skipped due to error)
      try {
        await db.transaction((txn) async {
          // 1. Remove duplicate products (keep the one with smallest ID)
          // We use a subquery to find IDs that are NOT the minimum ID for their name
          await txn.execute('''
            DELETE FROM products 
            WHERE id NOT IN (
              SELECT MIN(id) 
              FROM products 
              GROUP BY name
            )
          ''');

          // 2. Rename existing table
          await txn.execute('ALTER TABLE products RENAME TO products_old');

          // 3. Create new table with UNIQUE constraint on name
          await txn.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              category_id INTEGER NOT NULL,
              unit TEXT,
              initial_stock REAL DEFAULT 0,
              created_at TEXT DEFAULT (datetime('now')),
              FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE
            )
          ''');

          // 4. Copy data
          await txn.execute('''
            INSERT INTO products (id, name, category_id, unit, initial_stock, created_at)
            SELECT id, name, category_id, unit, initial_stock, created_at FROM products_old
          ''');

          // 5. Drop old table
          await txn.execute('DROP TABLE products_old');
        });
        print('Migration to v13 (Deduplicate Products) completed successfully');
      } catch (e) {
        print('Error in version 13 migration: $e');
      }
    }

    if (oldVersion < 14) {
      // Version 14: Aggressive deduplication (Trim whitespace first)
      try {
        await db.transaction((txn) async {
          // 1. Trim whitespace from all names to ensure "jh " becomes "jh"
          await txn.execute('UPDATE products SET name = TRIM(name)');

          // 2. Remove duplicates (keep the one with smallest ID)
          await txn.execute('''
            DELETE FROM products 
            WHERE id NOT IN (
              SELECT MIN(id) 
              FROM products 
              GROUP BY name
            )
          ''');

          // 3. Rename existing table
          await txn.execute('ALTER TABLE products RENAME TO products_temp_v14');

          // 4. Create new table with UNIQUE constraint
          await txn.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              category_id INTEGER NOT NULL,
              unit TEXT,
              initial_stock REAL DEFAULT 0,
              created_at TEXT DEFAULT (datetime('now')),
              FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE
            )
          ''');

          // 5. Copy data (if any duplicates remain, IGNORE them to prevent crash)
          await txn.execute('''
            INSERT OR IGNORE INTO products (id, name, category_id, unit, initial_stock, created_at)
            SELECT id, name, category_id, unit, initial_stock, created_at FROM products_temp_v14
          ''');

          // 6. Drop old table
          await txn.execute('DROP TABLE products_temp_v14');
        });
        print(
            'Migration to v14 (Aggressive Deduplication) completed successfully');
      } catch (e) {
        print('Error in version 14 migration: $e');
      }
    }

    if (oldVersion < 15) {
      // Version 15: Safe Deduplication (Copy to new table with GROUP BY trimming)
      // This avoids "UNIQUE constraint failed" errors during in-place UPDATES
      try {
        await db.transaction((txn) async {
          // 1. Rename current table
          await txn.execute('ALTER TABLE products RENAME TO products_v15_old');

          // 2. Create NEW table with strict UNIQUE(name)
          await txn.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              category_id INTEGER NOT NULL,
              unit TEXT,
              initial_stock REAL DEFAULT 0,
              created_at TEXT DEFAULT (datetime('now')),
              FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE
            )
          ''');

          // 3. Insert sanitized data
          // We TRIM the name and GROUP BY the trimmed name to strictly enforce uniqueness
          // We take the MIN(id) for each group
          await txn.execute('''
            INSERT INTO products (name, category_id, unit, initial_stock, created_at)
            SELECT 
              TRIM(name) as clean_name, 
              category_id, 
              unit, 
              initial_stock, 
              created_at 
            FROM products_v15_old
            GROUP BY clean_name
          ''');

          // 4. Cleanup
          await txn.execute('DROP TABLE products_v15_old');
        });
        print('Migration to v15 (Safe COPY-DEDUP) completed successfully');
      } catch (e) {
        print('Error in version 15 migration: $e');
      }
    }

    if (oldVersion < 16) {
      // Version 16: Fix Schema Integrity (Recreate tables referencing products)
      // Previous migrations renamed 'products' to 'products_old' and dropped it,
      // but child tables (with FKs) likely stuck to referencing 'products_old'.
      try {
        await db.transaction((txn) async {
          // --- 1. Fix product_raw_materials ---
          await txn.execute(
              'ALTER TABLE product_raw_materials RENAME TO product_raw_materials_old');
          await txn.execute('''
            CREATE TABLE product_raw_materials (
              product_id INTEGER NOT NULL,
              raw_material_id INTEGER NOT NULL,
              quantity_ratio REAL NOT NULL,
              FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE,
              FOREIGN KEY(raw_material_id) REFERENCES raw_materials(id) ON DELETE CASCADE,
              PRIMARY KEY(product_id, raw_material_id)
            )
          ''');
          await txn.execute('''
            INSERT INTO product_raw_materials (product_id, raw_material_id, quantity_ratio)
            SELECT product_id, raw_material_id, quantity_ratio FROM product_raw_materials_old
          ''');
          await txn.execute('DROP TABLE product_raw_materials_old');

          // --- 2. Fix outward ---
          await txn.execute('ALTER TABLE outward RENAME TO outward_old');
          await txn.execute('''
            CREATE TABLE outward (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              date TEXT NOT NULL,
              bag_size REAL NOT NULL,
              bag_count INTEGER NOT NULL,
              total_weight REAL,
              price_per_unit REAL DEFAULT 0,
              notes TEXT,
              created_at TEXT DEFAULT (datetime('now')),
              FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
            )
          ''');
          await txn.execute('''
            INSERT INTO outward (id, product_id, date, bag_size, bag_count, total_weight, price_per_unit, notes, created_at)
            SELECT id, product_id, date, bag_size, bag_count, total_weight, price_per_unit, notes, created_at FROM outward_old
          ''');
          await txn.execute('DROP TABLE outward_old');
          await txn.execute('CREATE INDEX idx_outward_date ON outward(date)');
          await txn.execute(
              'CREATE INDEX idx_outward_product ON outward(product_id)');

          // --- 3. Fix production hierarchy ---
          // production -> production_raw_materials, production_workers

          // Rename all production related tables
          await txn.execute('ALTER TABLE production RENAME TO production_old');
          await txn.execute(
              'ALTER TABLE production_raw_materials RENAME TO production_raw_materials_old');
          await txn.execute(
              'ALTER TABLE production_workers RENAME TO production_workers_old');

          // Create new tables
          await txn.execute('''
            CREATE TABLE production (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              date TEXT NOT NULL,
              batches INTEGER NOT NULL,
              total_quantity REAL NOT NULL,
              unit_size REAL,
              unit_count REAL,
              created_at TEXT DEFAULT (datetime('now')),
              FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
            )
          ''');

          await txn.execute('''
            CREATE TABLE production_raw_materials (
              production_id INTEGER NOT NULL,
              raw_material_id INTEGER NOT NULL,
              quantity_used REAL NOT NULL,
              bag_size REAL,
              FOREIGN KEY(production_id) REFERENCES production(id) ON DELETE CASCADE,
              FOREIGN KEY(raw_material_id) REFERENCES raw_materials(id) ON DELETE CASCADE,
              PRIMARY KEY(production_id, raw_material_id)
            )
          ''');

          await txn.execute('''
            CREATE TABLE production_workers (
              production_id INTEGER NOT NULL,
              worker_id INTEGER NOT NULL,
              FOREIGN KEY(production_id) REFERENCES production(id) ON DELETE CASCADE,
              FOREIGN KEY(worker_id) REFERENCES workers(id) ON DELETE CASCADE,
              PRIMARY KEY(production_id, worker_id)
            )
          ''');

          // Copy Data
          await txn.execute('''
            INSERT INTO production (id, product_id, date, batches, total_quantity, unit_size, unit_count, created_at)
            SELECT id, product_id, date, batches, total_quantity, unit_size, unit_count, created_at FROM production_old
          ''');

          await txn.execute('''
            INSERT INTO production_raw_materials (production_id, raw_material_id, quantity_used, bag_size)
            SELECT production_id, raw_material_id, quantity_used, bag_size FROM production_raw_materials_old
          ''');

          await txn.execute('''
            INSERT INTO production_workers (production_id, worker_id)
            SELECT production_id, worker_id FROM production_workers_old
          ''');

          // Drop Old Tables
          await txn.execute('DROP TABLE production_workers_old');
          await txn.execute('DROP TABLE production_raw_materials_old');
          await txn.execute('DROP TABLE production_old');

          // Recreate Indexes
          await txn
              .execute('CREATE INDEX idx_production_date ON production(date)');
          await txn.execute(
              'CREATE INDEX idx_production_product ON production(product_id)');
        });
        print('Migration to v16 (Fix Schema Integrity) completed successfully');
      } catch (e) {
        print('Error in version 16 migration: $e');
      }
    }

    if (oldVersion < 17) {
      // Version 17: Recreate preferences table for Company Details (Structured instead of KV)
      try {
        await db.transaction((txn) async {
          // Drop old KV preferences table
          await txn.execute('DROP TABLE IF EXISTS preferences');

          // Create new structured table
          await txn.execute('''
            CREATE TABLE preferences (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              company_name TEXT,
              address TEXT,
              phone TEXT,
              email TEXT,
              created_at TEXT DEFAULT (datetime('now'))
            )
          ''');

          // Insert default empty row
          await txn.execute('''
            INSERT INTO preferences (company_name, address, phone, email)
            VALUES ('', '', '', '')
          ''');
        });
        print(
            'Migration to v17 (Preferences Table Restructure) completed successfully');
      } catch (e) {
        print('Error in version 17 migration: $e');
      }
    }

    if (oldVersion < 18) {
      // Version 18: Force specific migration for Preferences table if v17 failed or didn't run properly
      try {
        await db.transaction((txn) async {
          // Check if table exists and has correct columns, or just nuclear option to be safe
          // We will recreate it to be absolutely sure
          await txn.execute('DROP TABLE IF EXISTS preferences');

          await txn.execute('''
            CREATE TABLE preferences (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              company_name TEXT,
              address TEXT,
              phone TEXT,
              email TEXT,
              created_at TEXT DEFAULT (datetime('now'))
            )
          ''');

          await txn.execute('''
            INSERT INTO preferences (company_name, address, phone, email)
            VALUES ('', '', '', '')
          ''');
        });
        print(
            'Migration to v18 (Force Preferences Schema) completed successfully');
      } catch (e) {
        print('Error in version 18 migration: $e');
      }
    }
  }

  /// Check if database file exists at path
  static Future<bool> databaseExists(String databasePath) async {
    return await File(databasePath).exists();
  }

  /// Get current database path
  static String? get currentDatabasePath => _currentDatabasePath;

  /// Close database connection
  static Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _currentDatabasePath = null;
    }
  }

  /// Execute a query and return results
  static Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return await db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// Execute raw query
  static Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    final db = await database;
    return await db.rawQuery(sql, arguments);
  }

  /// Insert a record
  static Future<int> insert(
    String table,
    Map<String, dynamic> values, {
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final db = await database;
    return await db.insert(
      table,
      values,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  /// Update records
  static Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
    );
  }

  /// Delete records
  static Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.delete(
      table,
      where: where,
      whereArgs: whereArgs,
    );
  }

  /// Execute transaction
  static Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action,
  ) async {
    final db = await database;
    return await db.transaction(action);
  }

  /// Backup database to specified path
  static Future<void> backupDatabase(String backupPath) async {
    if (_currentDatabasePath == null) {
      throw Exception('No database is currently open');
    }

    try {
      // Close database before copying
      await closeDatabase();

      // Copy file
      final sourceFile = File(_currentDatabasePath!);
      await sourceFile.copy(backupPath);

      // Reopen database
      await initDatabase(_currentDatabasePath!);

      print('Database backed up to: $backupPath');
    } catch (e) {
      // Reopen database even if backup failed
      if (_currentDatabasePath != null) {
        await initDatabase(_currentDatabasePath!);
      }
      throw Exception('Failed to backup database: $e');
    }
  }

  /// Restore database from backup
  static Future<void> restoreDatabase(
      String backupPath, String targetPath) async {
    try {
      // Close current database
      await closeDatabase();

      // Copy backup to target
      final backupFile = File(backupPath);
      await backupFile.copy(targetPath);

      // Open restored database
      await initDatabase(targetPath);

      print('Database restored from: $backupPath');
    } catch (e) {
      throw Exception('Failed to restore database: $e');
    }
  }
}
