import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';
import '../services/api_service.dart';
import '../services/server_config.dart';
import '../utils/constants.dart';
import '../utils/validators.dart';

class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController(text: ServerConfig.baseUrl);

  bool _isTesting = false;
  bool? _testPassed;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testPassed = null;
    });

    final url = ServerConfig.clean(_urlController.text);
    final ok = await ApiService(baseUrlOverride: url).checkHealth();

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testPassed = ok;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final sync = context.read<SyncProvider>();
    if (sync.isBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait until the sync finishes')),
      );
      return;
    }

    await ServerConfig.save(_urlController.text);

    sync.checkConnection();

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _useDefault() {
    setState(() {
      _urlController.text = defaultBaseUrl;
      _testPassed = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: 'http://192.168.1.5:3000',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: Validators.serverUrl,
              onChanged: (_) => setState(() => _testPassed = null),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use your computer\'s IP address on the same Wi-Fi or hotspot, '
              'with port 3000. Find it on a Mac with "ipconfig getifaddr en0", '
              'or on Windows with "ipconfig". '
              'The Android emulator uses http://10.0.2.2:3000.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_testPassed != null) _buildTestResult(_testPassed!),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find),
              label: const Text('Test connection'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _useDefault,
              child: Text('Use default ($defaultBaseUrl)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestResult(bool passed) {
    return Row(
      children: [
        Icon(
          passed ? Icons.check_circle : Icons.error,
          color: passed ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            passed
                ? 'Connected to the server'
                : 'Could not reach the server. Check the address, that the '
                      'server is running, and that both devices are on the '
                      'same network.',
          ),
        ),
      ],
    );
  }
}
