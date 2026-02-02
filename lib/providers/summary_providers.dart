import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/repositories/production_repository.dart';
import '../database/repositories/inward_repository.dart';
import '../database/repositories/outward_repository.dart';

enum ReportViewMode {
  daily,
  weekly,
  monthly,
  yearly
}

extension ReportViewModeExtension on ReportViewMode {
  String get label {
    switch (this) {
      case ReportViewMode.daily: return 'Daily View';
      case ReportViewMode.weekly: return 'Weekly View';
      case ReportViewMode.monthly: return 'Monthly View';
      case ReportViewMode.yearly: return 'Yearly View';
    }
  }
}

// Controls the current view mode for all summary report tabs
final reportViewModeProvider = StateProvider<ReportViewMode>((ref) => ReportViewMode.weekly);

// Controls the anchor date for reports (e.g. "today", or the selected week's start/center)
// Initialized to current date
final reportReferenceDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

// Computed provider that returns the Start and End date based on Mode and ReferenceDate
final reportDateRangeProvider = Provider<DateTimeRange>((ref) {
  final mode = ref.watch(reportViewModeProvider);
  final date = ref.watch(reportReferenceDateProvider);

  switch (mode) {
    case ReportViewMode.daily:
      return DateTimeRange(start: date, end: date);
    
    case ReportViewMode.weekly:
      // Start from Monday (or however defined, assuming Monday start for business logic)
      final startOfWeek = date.subtract(Duration(days: date.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      return DateTimeRange(start: startOfWeek, end: endOfWeek);
    
    case ReportViewMode.monthly:
      final startOfMonth = DateTime(date.year, date.month, 1);
      final nextMonth = DateTime(date.year, date.month + 1, 1);
      final endOfMonth = nextMonth.subtract(const Duration(days: 1));
      return DateTimeRange(start: startOfMonth, end: endOfMonth);
    
    case ReportViewMode.yearly:
      final startOfYear = DateTime(date.year, 1, 1);
      final endOfYear = DateTime(date.year, 12, 31);
      return DateTimeRange(start: startOfYear, end: endOfYear);
  }
});

// Helper to get previous/next range
final reportNavigationProvider = Provider.autoDispose((ref) {
  return (bool isNext) {
    final mode = ref.read(reportViewModeProvider);
    final currentDate = ref.read(reportReferenceDateProvider);
    final notifier = ref.read(reportReferenceDateProvider.notifier);

    DateTime newDate;
    int sign = isNext ? 1 : -1;

    switch (mode) {
      case ReportViewMode.daily:
        newDate = currentDate.add(Duration(days: sign * 1));
        break;
      case ReportViewMode.weekly:
        newDate = currentDate.add(Duration(days: sign * 7));
        break;
      case ReportViewMode.monthly:
        newDate = DateTime(currentDate.year, currentDate.month + sign, 1);
        break;
      case ReportViewMode.yearly:
        newDate = DateTime(currentDate.year + sign, 1, 1);
        break;
    }
    notifier.state = newDate;
  };
});

// Report Data Providers
final productionReportProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final range = ref.watch(reportDateRangeProvider);
  final list = await ProductionRepository.getByDateRange(range.start, range.end);

  double totalQty = 0;
  int totalBatches = 0;
  for (var item in list) {
    totalQty += item.totalQuantity;
    totalBatches += item.batches;
  }

  return {
    'totals': {
      'total_quantity': totalQty,
      'total_batches': totalBatches,
    },
    'data': list,
  };
});

final inwardReportProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final range = ref.watch(reportDateRangeProvider);
  final list = await InwardRepository.getByDateRange(range.start, range.end);

  double totalQty = 0;
  double totalValue = 0;
  for (var item in list) {
    totalQty += item.totalWeight;
    totalValue += (item.totalCost ?? 0);
  }

  return {
    'totals': {
      'total_quantity': totalQty,
      'total_value': totalValue,
      'total_entries': list.length,
    },
    'data': list,
  };
});

final outwardReportProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final range = ref.watch(reportDateRangeProvider);
  final list = await OutwardRepository.getByDateRange(range.start, range.end);

  double totalQty = 0;
  double totalValue = 0;
  for (var item in list) {
    totalQty += item.totalWeight;
    totalValue += (item.pricePerUnit * item.totalWeight); // Approximation if no total field
  }

  return {
    'totals': {
      'total_quantity': totalQty,
      'total_value': totalValue,
      'total_entries': list.length,
    },
    'data': list,
  };
});
