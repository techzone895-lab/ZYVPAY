import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/sms_launcher.dart';
import '../core/theme.dart';
import '../core/wallet.dart';
import 'pin_pad.dart';

/// First-run setup: phone + name, set PIN, then verify the SIM with one SMS.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final phone = _phone.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10 || _name.text.trim().isEmpty) {
      _toast('Naam aur sahi mobile number daalein');
      return;
    }
    final pin = await PinPad.ask(context, title: 'Naya UPI PIN set karein', subtitle: '6 digit', confirm: true);
    if (pin == null) return;

    setState(() => _busy = true);
    try {
      // RECEIVE_SMS lets the app read the confirmation SMS back automatically.
      await [Permission.sms].request();
      final draft = await Wallet.instance.register(phone: phone, name: _name.text.trim(), pin: pin);
      if (!mounted) return;
      await _verify(draft);
    } catch (e) {
      _toast('Setup fail: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(SmsDraft draft) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VerifyDialog(draft: draft),
    );
    if (ok != true) return;
    _toast('Number verify ho gaya 🎉');
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: ZColors.brand, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.bolt, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Text('ZYVPAY', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ]),
              const SizedBox(height: 10),
              Text('Net ho ya na ho, payment ho jaye.', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 15)),
              const SizedBox(height: 36),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Aapka naam', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_outlined)),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Verify karne ke liye ek SMS jayega. Normal SMS charge lag sakte hain.',
                        style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor)),
                  ),
                ]),
              ),
              const Spacer(),
              FilledButton(onPressed: _busy ? null : _start, child: _busy ? const _Spin() : const Text('Shuru karein')),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifyDialog extends StatefulWidget {
  const _VerifyDialog({required this.draft});
  final SmsDraft draft;

  @override
  State<_VerifyDialog> createState() => _VerifyDialogState();
}

class _VerifyDialogState extends State<_VerifyDialog> {
  bool _waiting = false;

  Future<void> _send() async {
    setState(() => _waiting = true);
    await openSmsComposer(widget.draft.to, widget.draft.text);
    final ok = await Wallet.instance.awaitRegistration();
    if (!mounted) return;
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Number verify karein'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.draft.to} par ek SMS bhejna hai. "Send" dabate hi aap wapas yahin aa jayenge.',
              style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 10),
          if (_waiting)
            const Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Text('Confirmation ka intezaar...')]),
        ],
      ),
      actions: [
        TextButton(onPressed: _waiting ? null : () => Navigator.pop(context, false), child: const Text('Baad mein')),
        FilledButton(onPressed: _waiting ? null : _send, child: const Text('SMS bhejein')),
      ],
    );
  }
}

class _Spin extends StatelessWidget {
  const _Spin();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
}
