import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/protocol.dart';
import '../core/theme.dart';
import '../core/wallet.dart';
import 'pin_pad.dart';
import 'processing_screen.dart';

/// Shows the payee and takes the amount, then asks for the PIN and starts the flow.
class AmountScreen extends StatefulWidget {
  const AmountScreen({super.key, required this.payee});
  final Payee payee;

  @override
  State<AmountScreen> createState() => _AmountScreenState();
}

class _AmountScreenState extends State<AmountScreen> {
  late final TextEditingController _amt;
  final _note = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _amt = TextEditingController(text: widget.payee.amountPaise == null ? '' : formatRupees(widget.payee.amountPaise!, symbol: false));
  }

  @override
  void dispose() {
    _amt.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final paise = parseRupees(_amt.text);
    if (paise == null) {
      setState(() => _error = 'Sahi amount daalein');
      return;
    }
    final pin = await PinPad.ask(context, title: 'UPI PIN daalein', subtitle: '${formatRupees(paise)} to ${widget.payee.name}');
    if (pin == null || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ProcessingScreen(payee: widget.payee, amountPaise: paise, pin: pin)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: ZColors.brand,
                child: Text(widget.payee.name[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
              ),
              title: Text(widget.payee.name),
              subtitle: Text(widget.payee.vpa),
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _amt,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(prefixText: '₹ ', border: InputBorder.none, errorText: _error, hintText: '0'),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(hintText: 'Note (optional)', prefixIcon: Icon(Icons.edit_note)),
          ),
          const Spacer(),
          if (!Wallet.instance.online)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                const Icon(Icons.sms_outlined, size: 16, color: ZColors.pending),
                const SizedBox(width: 6),
                Expanded(child: Text('Internet nahi hai — payment SMS se jayegi.', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13))),
              ]),
            ),
          FilledButton(onPressed: _pay, child: const Text('Pay karein')),
        ]),
      ),
    );
  }
}
