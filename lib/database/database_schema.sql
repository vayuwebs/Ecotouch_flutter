-- Production Management Dashboard Database Schema
-- Version: 8.0
-- Compatible with SQLite

-- ============================================
-- MASTER DATA TABLES
-- ============================================

-- Users/Accounts
CREATE TABLE IF NOT EXISTS accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  password_hash TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Workers (both labourers and drivers)
CREATE TABLE IF NOT EXISTS workers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  city TEXT,
  phone TEXT,
  type TEXT NOT NULL CHECK(type IN ('labour', 'driver')),
  created_at TEXT DEFAULT (datetime('now'))
);

-- Raw Materials
CREATE TABLE IF NOT EXISTS raw_materials (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  unit TEXT NOT NULL,
  min_alert_level REAL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Categories
CREATE TABLE IF NOT EXISTS categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Category-RawMaterial Junction
CREATE TABLE IF NOT EXISTS category_raw_materials (
  category_id INTEGER NOT NULL,
  raw_material_id INTEGER NOT NULL,
  FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE,
  FOREIGN KEY(raw_material_id) REFERENCES raw_materials(id) ON DELETE CASCADE,
  PRIMARY KEY(category_id, raw_material_id)
);

-- Products
CREATE TABLE IF NOT EXISTS products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  category_id INTEGER NOT NULL,
  unit TEXT,
  initial_stock REAL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE
);

-- Product-RawMaterial Junction (with quantities/ratios)
CREATE TABLE IF NOT EXISTS product_raw_materials (
  product_id INTEGER NOT NULL,
  raw_material_id INTEGER NOT NULL,
  quantity_ratio REAL NOT NULL,
  FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE,
  FOREIGN KEY(raw_material_id) REFERENCES raw_materials(id) ON DELETE CASCADE,
  PRIMARY KEY(product_id, raw_material_id)
);

-- Vehicles
CREATE TABLE IF NOT EXISTS vehicles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  registration_number TEXT NOT NULL UNIQUE,
  model TEXT,
  odometer_reading REAL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);

-- ============================================
-- TRANSACTION TABLES
-- ============================================

-- Attendance
CREATE TABLE IF NOT EXISTS attendance (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  worker_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('full_day', 'half_day')),
  time_in TEXT,
  time_out TEXT,
  FOREIGN KEY(worker_id) REFERENCES workers(id) ON DELETE CASCADE,
  UNIQUE(worker_id, date)
);

-- Inward (Raw Material Receipts)
CREATE TABLE IF NOT EXISTS inward (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  raw_material_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  bag_size REAL NOT NULL,
  bag_count INTEGER NOT NULL,
  total_weight REAL NOT NULL,
  total_cost REAL,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY(raw_material_id) REFERENCES raw_materials(id) ON DELETE CASCADE
);

-- Production
CREATE TABLE IF NOT EXISTS production (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  batches INTEGER NOT NULL,
  total_quantity REAL NOT NULL,
  unit_size REAL,
  unit_count REAL,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
);

-- Production-RawMaterial Usage
CREATE TABLE IF NOT EXISTS production_raw_materials (
  production_id INTEGER NOT NULL,
  raw_material_id INTEGER NOT NULL,
  quantity_used REAL NOT NULL,
  bag_size REAL,
  FOREIGN KEY(production_id) REFERENCES production(id) ON DELETE CASCADE,
  FOREIGN KEY(raw_material_id) REFERENCES raw_materials(id) ON DELETE CASCADE,
  PRIMARY KEY(production_id, raw_material_id)
);

-- Production-Worker Junction
CREATE TABLE IF NOT EXISTS production_workers (
  production_id INTEGER NOT NULL,
  worker_id INTEGER NOT NULL,
  FOREIGN KEY(production_id) REFERENCES production(id) ON DELETE CASCADE,
  FOREIGN KEY(worker_id) REFERENCES workers(id) ON DELETE CASCADE,
  PRIMARY KEY(production_id, worker_id)
);

-- Outward (Product Sales)
CREATE TABLE IF NOT EXISTS outward (
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
);

-- Logistics/Trips
CREATE TABLE IF NOT EXISTS trips (
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
);

-- ============================================
-- SETTINGS TABLE
-- ============================================

-- Preferences/Settings
CREATE TABLE IF NOT EXISTS preferences (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Unit Conversions
CREATE TABLE IF NOT EXISTS unit_conversions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  from_unit TEXT NOT NULL,
  to_unit TEXT NOT NULL,
  conversion_factor REAL NOT NULL,
  created_at TEXT DEFAULT (datetime('now'))
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(date);
CREATE INDEX IF NOT EXISTS idx_attendance_worker ON attendance(worker_id);

CREATE INDEX IF NOT EXISTS idx_inward_date ON inward(date);
CREATE INDEX IF NOT EXISTS idx_inward_material ON inward(raw_material_id);

CREATE INDEX IF NOT EXISTS idx_production_date ON production(date);
CREATE INDEX IF NOT EXISTS idx_production_product ON production(product_id);

CREATE INDEX IF NOT EXISTS idx_outward_date ON outward(date);
CREATE INDEX IF NOT EXISTS idx_outward_product ON outward(product_id);

CREATE INDEX IF NOT EXISTS idx_trips_date ON trips(date);
CREATE INDEX IF NOT EXISTS idx_trips_vehicle ON trips(vehicle_id);

CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);
