import 'package:flutter/material.dart';

import '../core/wallet.dart';
import 'home_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: AnimatedBuilder(
        animation: Wallet.instance,
        builder: (context, _) {
          final h = Wallet.instance.history;
          if (h.isEmpty) {
            return Center(child: Text('Abhi koi payment nahi.', style: TextStyle(color: Theme.of(context).hintColor)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: h.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => TxnTile(txn: h[i]),
          );
        },
      ),
    );
  }
}
