import 'package:flutter/material.dart';

import '../core/protocol.dart';
import 'amount_screen.dart';

/// Enter a UPI ID by hand, then move to the amount screen.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key, this.payee});
  final Payee? payee;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _vpa = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.payee != null) _vpa.text = widget.payee!.vpa;
  }

  @override
  void dispose() {
    _vpa.dispose();
    super.dispose();
  }

  void _next() {
    final vpa = _vpa.text.trim().toLowerCase();
    if (!isValidVpa(vpa)) {
      setState(() => _error = 'Sahi UPI ID daalein, jaise naam@bank');
      return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AmountScreen(payee: Payee(vpa))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UPI ID par bhejein')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(
            controller: _vpa,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'UPI ID / VPA',
              hintText: 'naam@okaxis',
              prefixIcon: const Icon(Icons.alternate_email),
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _next(),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _next, child: const Text('Aage badhein')),
        ]),
      ),
    );
  }
}
