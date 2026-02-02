import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tally_page_wrapper.dart';
import '../attendance/attendance_screen.dart';
import '../production/production_screen.dart';
import '../inward/inward_screen.dart';
import '../outward/outward_screen.dart';
import '../logistics/logistics_screen.dart';
import '../stock_level/inventory_screen.dart';
import '../summary/summary_screen.dart';
import '../settings/settings_screen.dart';

class GatewayScreen extends ConsumerWidget {
  const GatewayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TallyPageWrapper(
      title: 'Gateway',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 2. Action Grid
          Expanded(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: const EdgeInsets.all(32),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    // --- MASTERS ---
                    _buildActionCard(
                      context,
                      title: 'Masters',
                      subtitle: 'Manage Workers & Settings',
                      icon: Icons.settings,
                      color: Colors.blueGrey,
                      autofocus: true,
                      onTap: () =>
                          _navigateTo(context, const SettingsScreenWrapper()),
                    ),

                    // --- TRANSACTIONS ---
                    _buildActionCard(
                      context,
                      title: 'Attendance',
                      subtitle: 'Log Worker In/Out',
                      icon: Icons.people,
                      color: Colors.blue,
                      onTap: () =>
                          _navigateTo(context, const AttendanceScreen()),
                    ),
                    _buildActionCard(
                      context,
                      title: 'Production',
                      subtitle: 'Daily Manufacturing Logs',
                      icon: Icons.factory,
                      color: Colors.orange,
                      onTap: () =>
                          _navigateTo(context, const ProductionScreen()),
                    ),
                    _buildActionCard(
                      context,
                      title: 'Inventory',
                      subtitle: 'Stock Levels & Management',
                      icon: Icons.inventory_2,
                      color: Colors.teal,
                      onTap: () =>
                          _navigateTo(context, const InventoryScreenWrapper()),
                    ),
                    _buildActionCard(
                      context,
                      title: 'Inward',
                      subtitle: 'Material In',
                      icon: Icons.arrow_circle_down,
                      color: Colors.green,
                      onTap: () =>
                          _navigateTo(context, const InwardScreenWrapper()),
                    ),
                    _buildActionCard(
                      context,
                      title: 'Outward',
                      subtitle: 'Dispatch & Sales',
                      icon: Icons.arrow_circle_up,
                      color: Colors.redAccent,
                      onTap: () =>
                          _navigateTo(context, const OutwardScreenWrapper()),
                    ),
                    _buildActionCard(
                      context,
                      title: 'Logistics',
                      subtitle: 'Transport & Vehicles',
                      icon: Icons.local_shipping,
                      color: Colors.indigo,
                      onTap: () =>
                          _navigateTo(context, const LogisticsScreenWrapper()),
                    ),

                    // --- REPORTS ---
                    _buildActionCard(
                      context,
                      title: 'Reports',
                      subtitle: 'Summary & Balance Sheet',
                      icon: Icons.assessment,
                      color: Colors.purple,
                      onTap: () =>
                          _navigateTo(context, const SummaryScreenWrapper()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool autofocus = false,
  }) {
    // Fixed size for Wrap items to simulate grid cells
    // Adjust width/height as needed to fit 6 items roughly or responsive
    const cardSize = 160.0;

    return SizedBox(
      width: cardSize,
      height: cardSize,
      child: Material(
        color: Theme.of(context).cardColor,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          autofocus: autofocus,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: color.withOpacity(0.04),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

// WRAPPERS for existing screens to use TallyPageWrapper
// We can move these to their respective files later or keep here for quick refactor.
// For now, I'll define simple wrappers here to verify the concept.

class InwardScreenWrapper extends StatelessWidget {
  const InwardScreenWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return const TallyPageWrapper(
      title: 'Gateway of Tally > Inward',
      child: InwardScreen(),
    );
  }
}

class OutwardScreenWrapper extends StatelessWidget {
  const OutwardScreenWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return const TallyPageWrapper(
      title: 'Gateway of Tally > Outward',
      child: OutwardScreen(),
    );
  }
}

class LogisticsScreenWrapper extends StatelessWidget {
  const LogisticsScreenWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return const TallyPageWrapper(
      title: 'Gateway of Tally > Logistics',
      child: LogisticsScreen(),
    );
  }
}

class InventoryScreenWrapper extends StatelessWidget {
  const InventoryScreenWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return const TallyPageWrapper(
      title: 'Gateway of Tally > Inventory',
      child: InventoryScreen(),
    );
  }
}

class SummaryScreenWrapper extends StatelessWidget {
  const SummaryScreenWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return const TallyPageWrapper(
      title: 'Gateway of Tally > Summary',
      child: SummaryScreen(),
    );
  }
}

class SettingsScreenWrapper extends StatelessWidget {
  const SettingsScreenWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return const TallyPageWrapper(
      title: 'Gateway of Tally > Masters',
      child: SettingsScreen(),
    );
  }
}
