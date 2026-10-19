import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'core/wallet.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Wallet.instance.load();
  runApp(const ZyvpayApp());
}

class ZyvpayApp extends StatelessWidget {
  const ZyvpayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZYVPAY',
      debugShowCheckedModeBanner: false,
      theme: zyvTheme(Brightness.light),
      darkTheme: zyvTheme(Brightness.dark),
      home: AnimatedBuilder(
        animation: Wallet.instance,
        builder: (context, _) => Wallet.instance.isSetUp ? const HomeScreen() : const SetupScreen(),
      ),
    );
  }
}
