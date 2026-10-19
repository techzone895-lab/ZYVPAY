import 'package:flutter/material.dart';

import '../core/wallet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _api = TextEditingController(text: Wallet.instance.apiBase);

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = Wallet.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(title: const Text('Naam'), subtitle: Text(w.name)),
          ListTile(title: const Text('Mobile'), subtitle: Text(w.phone ?? '-')),
          ListTile(title: const Text('Device ID'), subtitle: Text(w.sid ?? '-')),
          ListTile(title: const Text('SMS gateway number'), subtitle: Text(w.gatewayNumber ?? '-')),
          const Divider(),
          TextField(
            controller: _api,
            decoration: const InputDecoration(labelText: 'Backend URL'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () async {
              await w.setApiBase(_api.text);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
            },
            child: const Text('Save'),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('App reset karein?'),
                  content: const Text('Device unregister ho jayega aur history mit jayegi.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nahi')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                  ],
                ),
              );
              if (ok == true) {
                await w.reset();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
            child: const Text('Reset / Logout'),
          ),
        ],
      ),
    );
  }
}
