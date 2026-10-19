import 'package:flutter/material.dart';

import 'protocol.dart';
import 'sms_launcher.dart';
import 'wallet.dart';

/// Orchestrates a single payment: internet first, otherwise the user-confirmed
/// SMS path. Reports progress so the processing screen can show the right step.
enum PayStage { contacting, waitingSms, done }

class PayProgress {
  PayProgress(this.stage, {this.outcome, this.draft});
  final PayStage stage;
  final Outcome? outcome;
  final SmsDraft? draft; // set when the user must send an SMS
}

typedef ProgressSink = void Function(PayProgress);

class PayFlow {
  PayFlow(this.wallet);
  final Wallet wallet;

  /// Runs the payment. When [onSmsNeeded] is provided and the internet is down,
  /// it is invoked so the UI can ask the user to send the SMS; it must return
  /// true once the user has sent it (false to abort).
  Future<Outcome> pay({
    required Payee payee,
    required int amountPaise,
    required String pin,
    required ProgressSink onProgress,
    required Future<bool> Function(SmsDraft draft) onSmsNeeded,
  }) async {
    final plan = await wallet.preparePayment(payee, amountPaise, pin);
    final outcome = await _run(plan.ctr, plan.text, onProgress, onSmsNeeded);
    await wallet.recordTxn(plan.txn, outcome);
    onProgress(PayProgress(PayStage.done, outcome: outcome));
    return outcome;
  }

  Future<Outcome> _run(int ctr, String text, ProgressSink onProgress, Future<bool> Function(SmsDraft) onSmsNeeded) async {
    if (await wallet.hasInternet()) {
      onProgress(PayProgress(PayStage.contacting));
      try {
        return await wallet.sendOverNet(text);
      } catch (_) {
        // Internet flaky — drop to SMS below.
      }
    }
    final draft = wallet.smsDraft(text);
    onProgress(PayProgress(PayStage.waitingSms, draft: draft));
    final sent = await onSmsNeeded(draft);
    if (!sent) return Outcome(TxnStatus.failed, code: 'NO_CHANNEL', channel: Channel.sms);
    return wallet.awaitSms(ctr);
  }
}

Color statusColor(TxnStatus s, ColorScheme c) => switch (s) {
      TxnStatus.success => const Color(0xFF1AA260),
      TxnStatus.pending => const Color(0xFFEC9A1E),
      TxnStatus.failed => c.error,
    };

/// Shared helper for opening the SMS composer and telling the flow it was sent.
Future<bool> confirmAndSendSms(BuildContext context, SmsDraft draft) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _SmsConfirmSheet(draft: draft),
  );
  return ok ?? false;
}

class _SmsConfirmSheet extends StatelessWidget {
  const _SmsConfirmSheet({required this.draft});
  final SmsDraft draft;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sms_outlined, size: 32),
          const SizedBox(height: 12),
          const Text('Internet nahi hai', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Payment SMS se bheji jayegi ${draft.to} par. Agli screen par bas "Send" dabayein.',
              style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(draft.text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await openSmsComposer(draft.to, draft.text);
              if (context.mounted) Navigator.pop(context, true);
            },
            icon: const Icon(Icons.send),
            label: const Text('SMS app kholein'),
          ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ],
      ),
    );
  }
}
