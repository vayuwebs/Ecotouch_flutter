import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/global_providers.dart';
import '../settings/configuration_screen.dart';

class TallyPageWrapper extends ConsumerStatefulWidget {
  final String title;
  final Widget child;
  final List<Widget>? rightActions;

  const TallyPageWrapper({
    super.key,
    required this.title,
    required this.child,
    this.rightActions,
  });

  @override
  ConsumerState<TallyPageWrapper> createState() => _TallyPageWrapperState();
}

class _TallyPageWrapperState extends ConsumerState<TallyPageWrapper> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      // Only pop if this route is the current top-most route (i.e., no dialogs on top)
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).maybePop();
        return true; // We handled it
      }
    }
    return false; // Let it propagate if we didn't handle it (or if a dialog is open)
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    // Mock company name for now
    final companyName = "EcoTouch Inc.";

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () =>
            _showDateDialog(context, ref, selectedDate),
        const SingleActivator(LogicalKeyboardKey.f12): () =>
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConfigurationScreen()),
            ),
        // Esc handled by HardwareKeyboard manually to bypass TextField focus
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Column(
            children: [
// 1. Top Bar (Modern Header)
              Container(
                height: 60,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                      bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    // Breadcrumbs / Title
                    const Icon(Icons.dashboard_outlined,
                        color: Colors.blue, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      companyName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),

                    const Spacer(),

                    // Header Actions
                    Row(
                      children: [
                        _buildHeaderButton(
                          context,
                          label: 'Date',
                          shortcut: 'F2',
                          icon: Icons.calendar_today,
                          onTap: () =>
                              _showDateDialog(context, ref, selectedDate),
                        ),
                        const SizedBox(width: 8),
                        _buildHeaderButton(
                          context,
                          label: 'Company',
                          shortcut: 'F3',
                          icon: Icons.business,
                          onTap: () {},
                        ),
                        const SizedBox(width: 8),
                        _buildHeaderButton(
                          context,
                          label: 'Config',
                          shortcut: 'F12',
                          icon: Icons.settings,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ConfigurationScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(width: 24),
                    Container(
                        height: 24,
                        width: 1,
                        color: Theme.of(context).dividerColor), // Separator
                    const SizedBox(width: 24),

                    // Top Actions (Date Display & Back)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            "${selectedDate.day}-${selectedDate.month}-${selectedDate.year}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Focus(
                      skipTraversal: true,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Main Content Area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    String? shortcut,
    required VoidCallback onTap,
  }) {
    return TextButton.icon(
      focusNode: FocusNode(skipTraversal: true),
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: Theme.of(context).iconTheme.color),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color)),
          if (shortcut != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                shortcut,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodySmall?.color),
              ),
            ),
          ],
        ],
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Future<void> _showDateDialog(
      BuildContext context, WidgetRef ref, DateTime currentDate) async {
    final picked = await showDatePicker(
        context: context,
        initialDate: currentDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF2196F3),
              ),
            ),
            child: child!,
          );
        });

    if (picked != null) {
      ref.read(selectedDateProvider.notifier).state = picked;
    }
  }
}
