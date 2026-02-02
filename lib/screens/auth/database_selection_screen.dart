import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'package:path/path.dart' as path;
import '../../providers/global_providers.dart';
import '../../database/database_service.dart';
import '../../utils/constants.dart';
import '../../utils/recent_files_service.dart';

import '../../theme/app_colors.dart';
import '../main/gateway_screen.dart';

class DatabaseSelectionScreen extends ConsumerStatefulWidget {
  const DatabaseSelectionScreen({super.key});

  @override
  ConsumerState<DatabaseSelectionScreen> createState() =>
      _DatabaseSelectionScreenState();
}

class _DatabaseSelectionScreenState
    extends ConsumerState<DatabaseSelectionScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  List<String> _recentFiles = [];

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();
  }

  Future<void> _loadRecentFiles() async {
    final files = await RecentFilesService.getRecentFiles();
    if (mounted) {
      setState(() => _recentFiles = files);
    }
  }

  Future<void> _selectDatabaseFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Database Folder',
      );

      if (result != null) {
        final dbPath = path.join(result, AppConstants.databaseName);
        await _openDatabase(dbPath);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        debugPrint('Failed to open database: $e');
      });
    }
  }

  Future<void> _openDatabase(String dbPath) async {
    setState(() {
      _isLoading = true;
      _isLoading = true;
    });

    try {
      await DatabaseService.initDatabase(dbPath);
      await RecentFilesService.addRecentFile(dbPath);

      if (mounted) {
        ref.read(databasePathProvider.notifier).state = dbPath;
        ref.read(isAuthenticatedProvider.notifier).state = true;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GatewayScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final errorStr = e.toString();
          debugPrint('Failed to initialize database: $errorStr');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _showExitConfirmation,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Center(
            child: SingleChildScrollView(
                child: Container(
              width: 700,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brand Header
                  const Icon(Icons.eco, size: 64, color: AppColors.primaryBlue),
                  const SizedBox(height: 16),
                  Text(
                    'EcoTouch',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color:
                              Theme.of(context).textTheme.displaySmall?.color,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Production Management System',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                  ),
                  const SizedBox(height: 48),

                  // Main Card
                  Card(
                    elevation: 4,
                    shadowColor: Colors.black.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    color: Theme.of(context).cardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Select Company',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.color,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          // Primary Action
                          ElevatedButton.icon(
                            onPressed:
                                _isLoading ? null : _selectDatabaseFolder,
                            icon: const Icon(Icons.folder_open),
                            label: Text(_isLoading
                                ? 'Loading...'
                                : 'Open Company Folder'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),

                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.error),
                              ),
                              child: Text(
                                "Error: check console for details",
                                style: const TextStyle(color: AppColors.error),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Recent Companies
                  if (_recentFiles.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recent Companies',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.color,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListView.separated(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      itemCount: _recentFiles.length,
                      separatorBuilder: (c, i) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final filePath = _recentFiles[index];
                        final companyName =
                            path.basename(path.dirname(filePath));
                        final companyPath = path.dirname(filePath);

                        return Material(
                          color: Theme.of(context).cardColor,
                          elevation: 1,
                          shadowColor: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: _isLoading
                                ? null
                                : () => _openDatabase(filePath),
                            borderRadius: BorderRadius.circular(12),
                            hoverColor: AppColors.primaryBlue.withOpacity(0.05),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryBlue
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.business,
                                        color: AppColors.primaryBlue, size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          companyName,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.color,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          companyPath,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.color,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      color: Theme.of(context).disabledColor),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            )),
          ),
        ),
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => const ExitConfirmationDialog(),
    );
  }
}

class ExitConfirmationDialog extends StatefulWidget {
  const ExitConfirmationDialog({super.key});

  @override
  State<ExitConfirmationDialog> createState() => _ExitConfirmationDialogState();
}

class _ExitConfirmationDialogState extends State<ExitConfirmationDialog> {
  final FocusNode _yesFocus = FocusNode();
  final FocusNode _noFocus = FocusNode();

  @override
  void dispose() {
    _yesFocus.dispose();
    _noFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyY): () =>
            _yesFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyN): () =>
            _noFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.enter): _handleEnter,
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: const Text('Quit Application'),
          content: const Text('Do you want to close the application?'),
          actions: [
            TextButton(
              focusNode: _noFocus,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('No'),
            ),
            TextButton(
              focusNode: _yesFocus,
              onPressed: () => exit(0),
              child: const Text('Yes'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleEnter() {
    if (_yesFocus.hasFocus) {
      exit(0);
    } else if (_noFocus.hasFocus) {
      Navigator.of(context).pop();
    }
  }
}
