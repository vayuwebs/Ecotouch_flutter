import 'package:flutter/material.dart';

import '../main/tally_page_wrapper.dart';
import 'widgets/preferences_panel.dart';

class ConfigurationScreen extends StatelessWidget {
  const ConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TallyPageWrapper(
      title: 'Configuration',
      child: PreferencesPanel(),
    );
  }
}
