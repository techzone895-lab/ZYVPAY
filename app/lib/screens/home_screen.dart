import 'package:flutter/material.dart';

import '../core/protocol.dart';
import '../core/theme.dart';
import '../core/wallet.dart';
import 'history_screen.dart';
import 'scan_screen.dart';
import 'send_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final w = Wallet.instance;
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: w,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _TopBar(w: w),
              const SizedBox(height: 18),
              _BalanceCard(w: w),
              const SizedBox(height: 20),
              const Text('Paisa bhejein', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(children: [
                _Action(
                  icon: Icons.qr_code_scanner,
                  label: 'Scan & Pay',
                  color: ZColors.brand,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen())),
                ),
                const SizedBox(width: 12),
                _Action(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'UPI ID par',
                  color: ZColors.accent,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendScreen())),
                ),
              ]),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
                    child: const Text('Sab dekhein'),
                  ),
                ],
              ),
              if (w.history.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: Text('Abhi koi payment nahi.', style: TextStyle(color: Theme.of(context).hintColor))),
                )
              else
                ...w.history.take(6).map((t) => TxnTile(txn: t)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.w});
  final Wallet w;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      CircleAvatar(
        backgroundColor: ZColors.brand,
        child: Text(w.name.isEmpty ? '?' : w.name[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Namaste,', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
          Text(w.name.isEmpty ? 'ZYVPAY user' : w.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
        ]),
      ),
      _NetChip(online: w.online),
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
      ),
    ]);
  }
}

class _NetChip extends StatelessWidget {
  const _NetChip({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    final c = online ? ZColors.success : ZColors.pending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(online ? Icons.wifi : Icons.sms_outlined, size: 14, color: c),
        const SizedBox(width: 5),
        Text(online ? 'Online' : 'SMS mode', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.w});
  final Wallet w;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [ZColors.brand, ZColors.brandDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ZYVPAY Wallet', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 10),
        Text(
          w.balance == null ? '₹ —' : formatRupees(w.balance!),
          style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          w.balanceAt == null ? 'Balance ke liye payment ya refresh karein' : 'Updated ${_ago(w.balanceAt!)}',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ]),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'abhi';
    if (d.inHours < 1) return '${d.inMinutes} min pehle';
    if (d.inDays < 1) return '${d.inHours} ghante pehle';
    return '${d.inDays} din pehle';
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn});
  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (txn.status) {
      TxnStatus.success => (Icons.check_circle, ZColors.success, 'Paid'),
      TxnStatus.pending => (Icons.schedule, ZColors.pending, 'Processing'),
      TxnStatus.failed => (Icons.cancel, ZColors.danger, 'Failed'),
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.14),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(txn.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$label · ${txn.channel == Channel.sms ? 'SMS' : 'Online'}',
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
      trailing: Text('- ${formatRupees(txn.amount)}', style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
