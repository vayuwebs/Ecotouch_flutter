import '../database_service.dart';
import '../../models/attendance.dart';
import '../../utils/date_utils.dart' as app_date_utils;

class AttendanceRepository {
  /// Get attendance for a specific date
  static Future<List<Attendance>> getByDate(DateTime date) async {
    final dateStr = app_date_utils.DateUtils.formatDateForDatabase(date);
    final results = await DatabaseService.rawQuery('''
      SELECT a.*, w.name as worker_name
      FROM attendance a
      INNER JOIN workers w ON a.worker_id = w.id
      WHERE a.date = ?
      ORDER BY w.name ASC
    ''', [dateStr]);
    return results.map((json) => Attendance.fromJson(json)).toList();
  }

  /// Get attendance for date range
  static Future<List<Attendance>> getByDateRange(
      DateTime startDate, DateTime endDate) async {
    final startStr = app_date_utils.DateUtils.formatDateForDatabase(startDate);
    final endStr = app_date_utils.DateUtils.formatDateForDatabase(endDate);
    final results = await DatabaseService.rawQuery('''
      SELECT a.*, w.name as worker_name
      FROM attendance a
      INNER JOIN workers w ON a.worker_id = w.id
      WHERE a.date BETWEEN ? AND ?
      ORDER BY a.date DESC, w.name ASC
    ''', [startStr, endStr]);
    return results.map((json) => Attendance.fromJson(json)).toList();
  }

  /// Insert attendance
  static Future<int> insert(Attendance attendance) async {
    try {
      return await DatabaseService.insert('attendance', attendance.toJson());
    } catch (e) {
      final error = e.toString();
      if (error.contains('UNIQUE constraint failed') ||
          error.contains('2067')) {
        throw Exception('Attendance is already marked for this worker today.');
      }
      rethrow;
    }
  }

  /// Update attendance (mainly for time_out)
  static Future<int> update(Attendance attendance) async {
    if (attendance.id == null)
      throw Exception('Attendance ID is required for update');
    return await DatabaseService.update(
      'attendance',
      attendance.toJson(),
      where: 'id = ?',
      whereArgs: [attendance.id],
    );
  }

  /// Delete attendance
  static Future<int> delete(int id) async {
    return await DatabaseService.delete(
      'attendance',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get attendance summary for date range
  static Future<Map<String, dynamic>> getSummary(
      DateTime startDate, DateTime endDate) async {
    final startStr = app_date_utils.DateUtils.formatDateForDatabase(startDate);
    final endStr = app_date_utils.DateUtils.formatDateForDatabase(endDate);
    final results = await DatabaseService.rawQuery('''
      SELECT 
        w.name as worker_name,
        COUNT(*) as total_days,
        SUM(CASE WHEN a.status = 'full_day' THEN 1 ELSE 0 END) as full_days,
        SUM(CASE WHEN a.status = 'half_day' THEN 1 ELSE 0 END) as half_days
      FROM workers w
      LEFT JOIN attendance a ON w.id = a.worker_id 
        AND a.date BETWEEN ? AND ?
      GROUP BY w.id, w.name
      ORDER BY w.name ASC
    ''', [startStr, endStr]);
    return {'summary': results};
  }
}
