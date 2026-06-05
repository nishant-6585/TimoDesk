import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _spineUrlController;
  late TextEditingController _robotIpController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _spineUrlController = TextEditingController(text: settings.spineUrl);
    _robotIpController = TextEditingController(text: settings.robotIp);
  }

  @override
  void dispose() {
    _spineUrlController.dispose();
    _robotIpController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    ref.read(settingsProvider.notifier).setSpineUrl(_spineUrlController.text);
    ref.read(settingsProvider.notifier).setRobotIp(_robotIpController.text);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  void _testConnection() async {
    final success = await ref.read(settingsProvider.notifier).testConnection(_spineUrlController.text);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Connection OK' : 'Connection failed'),
        backgroundColor: success ? TimoColors.success : TimoColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: TimoColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Network Configuration',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: TimoColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),

            // Spine URL
            Text(
              'Spine URL',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: TimoColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _spineUrlController,
              decoration: const InputDecoration(
                hintText: 'ws://192.168.1.x:4000',
                prefixIcon: Icon(Icons.cloud, color: TimoColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),

            // Robot IP
            Text(
              'Robot IP (for MJPEG)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: TimoColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _robotIpController,
              decoration: const InputDecoration(
                hintText: '192.168.1.x',
                prefixIcon: Icon(Icons.router, color: TimoColors.textSecondary),
              ),
            ),
            const SizedBox(height: 32),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: settings.isLoading ? null : _testConnection,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: TimoColors.primary),
                    ),
                    child: settings.isLoading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 1),
                          )
                        : const Text('Test Connection'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),

            // About section
            Text(
              'About',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: TimoColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TimoColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TimoColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'App Version',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TimoColors.textSecondary,
                        ),
                      ),
                      Text(
                        '0.1.0',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TimoColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Built by xboom · Land + Air + Water',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: TimoColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
