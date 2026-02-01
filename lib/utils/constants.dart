class AppConstants {
  // Layout Dimensions
  static const double sidebarWidth = 240.0;
  static const double sidebarCollapsedWidth = 60.0;
  static const double topBarHeight = 64.0;
  static const double contentPadding = 32.0;

  // Component Heights
  static const double buttonHeight = 40.0;
  static const double inputHeight = 40.0;
  static const double tableRowHeight = 48.0;
  static const double kpiCardMinHeight = 120.0;

  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacing2Xl = 48.0;

  // Border Radius
  static const double borderRadius = 4.0;

  // Database
  static const String databaseName = 'production_dashboard_v2.db';
  static const int databaseVersion = 1;
  static const int maxRecentDatabases = 5;

  // Stock Thresholds
  static const double stockSufficientMultiplier = 2.0; // > 2x minimum
  static const double stockLowMultiplier = 1.0; // 1x-2x minimum
  // < 1x minimum = critical

  // Default Values
  static const String defaultTimeOut = '18:00'; // 6:00 PM

  // Date Formats
  static const String displayDateFormat = 'dd/MM/yyyy';
  static const String databaseDateFormat = 'yyyy-MM-dd';
  static const String displayTimeFormat = 'HH:mm';
  static const String displayDateTimeFormat = 'dd/MM/yyyy HH:mm';
}
