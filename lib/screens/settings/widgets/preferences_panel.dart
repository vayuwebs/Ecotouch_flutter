import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_colors.dart';
import '../../../database/database_service.dart';
import '../../../providers/global_providers.dart';

final preferencesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final results = await DatabaseService.query('preferences', limit: 1);
  if (results.isEmpty) {
    return {
      'company_name': '',
      'address': '',
      'phone': '',
      'email': '',
    };
  }
  return results.first;
});

class PreferencesPanel extends ConsumerStatefulWidget {
  const PreferencesPanel({super.key});

  @override
  ConsumerState<PreferencesPanel> createState() => _PreferencesPanelState();
}

class _PreferencesPanelState extends ConsumerState<PreferencesPanel> {
  final _formKey = GlobalKey<FormState>();
  final _companyNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _companyNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferencesAsync = ref.watch(preferencesProvider);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preferences',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Configure general application settings',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: preferencesAsync.when(
              data: (prefs) {
                // Initialize controllers with current values
                if (_companyNameController.text.isEmpty && !_isSaving) {
                  _companyNameController.text =
                      prefs['company_name'] as String? ?? '';
                  _addressController.text = prefs['address'] as String? ?? '';
                  _phoneController.text = prefs['phone'] as String? ?? '';
                  _emailController.text = prefs['email'] as String? ?? '';
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Company Details',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 24),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _companyNameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Company Name',
                                      prefixIcon: Icon(Icons.business),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  child: TextFormField(
                                    controller: _emailController,
                                    decoration: const InputDecoration(
                                      labelText: 'Email Address',
                                      prefixIcon: Icon(Icons.email_outlined),
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _phoneController,
                                    decoration: const InputDecoration(
                                      labelText: 'Phone Number',
                                      prefixIcon: Icon(Icons.phone_outlined),
                                    ),
                                    keyboardType: TextInputType.phone,
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  child:
                                      Container(), // Spacer for layout balance
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(
                                labelText: 'Address',
                                prefixIcon: Icon(Icons.location_on_outlined),
                              ),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 48),
                            Divider(color: Theme.of(context).dividerColor),
                            const SizedBox(height: 32),
                            const Divider(),
                            const SizedBox(height: 32),
                            Text(
                              'Appearance',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 24),
                            Consumer(
                              builder: (context, ref, _) {
                                final isDarkMode = ref.watch(themeModeProvider);
                                return SwitchListTile(
                                  title: const Text('Dark Mode'),
                                  subtitle:
                                      const Text('Enable dark color theme'),
                                  value: isDarkMode,
                                  onChanged: (bool value) {
                                    ref
                                        .read(themeModeProvider.notifier)
                                        .setTheme(value);
                                  },
                                  secondary: Icon(
                                    isDarkMode
                                        ? Icons.dark_mode
                                        : Icons.light_mode,
                                    color: isDarkMode
                                        ? AppColors.primaryBlue
                                        : Theme.of(context)
                                            .iconTheme
                                            .color
                                            ?.withOpacity(0.5),
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                );
                              },
                            ),
                            const SizedBox(height: 32),
                            const Divider(),
                            const SizedBox(height: 32),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: _isSaving
                                    ? null
                                    : () => _savePreferences(prefs),
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.save),
                                label: Text(_isSaving
                                    ? 'Saving...'
                                    : 'Save Preferences'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(150, 50),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Text('Error: $error',
                    style: const TextStyle(color: AppColors.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _savePreferences(Map<String, dynamic> currentPrefs) async {
    setState(() => _isSaving = true);

    try {
      final data = {
        'company_name': _companyNameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
      };

      if (data['company_name'].toString().isEmpty ||
          data['address'].toString().isEmpty ||
          data['phone'].toString().isEmpty ||
          data['email'].toString().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter details to save'),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (currentPrefs['id'] == null) {
        await DatabaseService.insert('preferences', data);
      } else {
        await DatabaseService.update(
          'preferences',
          data,
          where: 'id = ?',
          whereArgs: [currentPrefs['id']],
        );
      }

      ref.invalidate(preferencesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preferences saved successfully'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
