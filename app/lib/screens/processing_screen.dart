import 'package:flutter/material.dart';

import '../core/pay_flow.dart';
import '../core/protocol.dart';
import '../core/theme.dart';
import '../core/wallet.dart';
import 'result_screen.dart';

/// Drives the payment: tries internet, otherwise the user-confirmed SMS path.
class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key, required this.payee, required this.amountPaise, required this.pin});
  final Payee payee;
  final int amountPaise;
  final String pin;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String _step = 'Payment shuru ho rahi hai...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  Future<void> _go() async {
    final flow = PayFlow(Wallet.instance);
    final outcome = await flow.pay(
      payee: widget.payee,
      amountPaise: widget.amountPaise,
      pin: widget.pin,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _step = switch (p.stage) {
              PayStage.contacting => 'Server se baat ho rahi hai...',
              PayStage.waitingSms => 'SMS se bheja ja raha hai...',
              PayStage.done => 'Ho gaya',
            });
      },
      onSmsNeeded: (draft) => confirmAndSendSms(context, draft),
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(outcome: outcome, payee: widget.payee, amountPaise: widget.amountPaise),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: ZColors.brand),
          const SizedBox(height: 24),
          Text(formatRupees(widget.amountPaise), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('to ${widget.payee.name}', style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 18),
          Text(_step),
        ]),
      ),
    );
  }
}
