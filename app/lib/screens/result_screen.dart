import 'package:flutter/material.dart';

import '../core/protocol.dart';
import '../core/theme.dart';
import '../core/wallet.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.outcome, required this.payee, required this.amountPaise});
  final Outcome outcome;
  final Payee payee;
  final int amountPaise;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title) = switch (outcome.status) {
      TxnStatus.success => (Icons.check_circle, ZColors.success, 'Payment ho gayi'),
      TxnStatus.pending => (Icons.schedule, ZColors.pending, 'Payment ho rahi hai'),
      TxnStatus.failed => (Icons.cancel, ZColors.danger, 'Payment fail'),
    };
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            Icon(icon, color: color, size: 88),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(formatRupees(amountPaise), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('to ${payee.name} (${payee.vpa})',
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 16),
            if (outcome.status == TxnStatus.failed)
              Text(errorMessage(outcome.code), textAlign: TextAlign.center, style: const TextStyle(color: ZColors.danger)),
            if (outcome.status == TxnStatus.pending)
              Text(
                outcome.channel == Channel.sms
                    ? 'SMS chala gaya hai. Confirmation aate hi status update ho jayega.'
                    : 'Bank se confirmation ka intezaar hai.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            if (outcome.ref != null) ...[
              const SizedBox(height: 10),
              Text('Ref: ${outcome.ref}', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
            ],
            if (outcome.balance != null) ...[
              const SizedBox(height: 10),
              Text('Balance: ${formatRupees(outcome.balance!)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Ho gaya'),
            ),
          ]),
        ),
      ),
    );
  }
}
