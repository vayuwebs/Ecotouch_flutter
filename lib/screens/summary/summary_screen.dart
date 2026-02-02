import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/summary_tab_bar.dart';
import 'widgets/attendance_report_tab.dart';
import 'widgets/production_report_tab.dart';
import 'widgets/inward_report_tab.dart';
import 'widgets/outward_report_tab.dart';
import '../../providers/global_providers.dart';
import '../attendance/attendance_screen.dart';
import '../../providers/production_providers.dart';
import '../../providers/inward_providers.dart';
import '../../providers/outward_providers.dart';

class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<String> _tabs = [
    'Attendance',
    'Production',
    'Inward (Stock)',
    'Outward (Sales)',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding:
                const EdgeInsets.only(left: 32, right: 32, top: 32, bottom: 20),
            child: Row(
              children: [
                Text(
                  'Summary: Production Reports', // Dynamic based on tab?
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                // Global Date/Action controls could go here
                // Global Date/Action controls
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh Reports',
                      onPressed: () {
                        // Invalidate global stats
                        ref.invalidate(dashboardStatsProvider);

                        // Invalidate list providers for the current date
                        final selectedDate = ref.read(selectedDateProvider);
                        ref.invalidate(attendanceListProvider(selectedDate));
                        ref.invalidate(productionListProvider(selectedDate));
                        ref.invalidate(inwardListProvider(selectedDate));
                        ref.invalidate(outwardListProvider(selectedDate));

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Reports refreshed'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(milliseconds: 1000),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SummaryTabBar(controller: _tabController, tabs: _tabs),
          ),

          // Tab View
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: TabBarView(
                controller: _tabController,
                physics:
                    const NeverScrollableScrollPhysics(), // Disable swipe to avoid conflict with matrices/tables
                children: const [
                  AttendanceReportTab(),
                  ProductionReportTab(),
                  InwardReportTab(),
                  OutwardReportTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
