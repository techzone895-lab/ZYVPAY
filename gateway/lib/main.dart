import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyv_sms/zyv_sms.dart';

/// ZYVPAY SMS Gateway.
///
/// Runs on the operator's own phone with the ZYVPAY service SIM. It relays the
/// ZP1 SMS that users send to the backend, and sends the backend's reply SMS back.
/// This is service infrastructure the operator controls — it only ever replies to
/// numbers that first messaged this SIM.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GatewayApp());
}

class GatewayApp extends StatelessWidget {
  const GatewayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZYVPAY Gateway',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF4A2FBD)),
      home: const GatewayHome(),
    );
  }
}

class GatewayHome extends StatefulWidget {
  const GatewayHome({super.key});

  @override
  State<GatewayHome> createState() => _GatewayHomeState();
}

class _GatewayHomeState extends State<GatewayHome> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _log = <String>[];
  SharedPreferences? _prefs;
  StreamSubscription<IncomingSms>? _sub;
  Timer? _poll;
  bool _running = false;
  int _inCount = 0;
  int _outCount = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _url.text = _prefs!.getString('url') ?? '';
    _token.text = _prefs!.getString('token') ?? '';
    setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _poll?.cancel();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  void _add(String line) {
    final ts = TimeOfDay.now().format(context);
    setState(() {
      _log.insert(0, '$ts  $line');
      if (_log.length > 200) _log.removeLast();
    });
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json', 'X-Gateway-Token': _token.text.trim()};
  Uri _uri(String path) => Uri.parse('${_url.text.trim()}$path');

  Future<void> _start() async {
    final grants = await [Permission.sms].request();
    if (grants[Permission.sms] != PermissionStatus.granted) {
      _add('SMS permission chahiye.');
      return;
    }
    await _prefs!.setString('url', _url.text.trim());
    await _prefs!.setString('token', _token.text.trim());

    _sub = ZyvSms.incoming.listen((m) => _forward(m.from, m.body));
    for (final m in await ZyvSms.drain()) {
      _forward(m.from, m.body);
    }
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _drainOutbox());
    setState(() => _running = true);
    _add('Gateway shuru. Incoming SMS sun raha hai.');
    _drainOutbox();
  }

  void _stop() {
    _sub?.cancel();
    _poll?.cancel();
    setState(() => _running = false);
    _add('Gateway band.');
  }

  Future<void> _forward(String from, String body) async {
    try {
      final res = await http.post(_uri('/gateway/inbound'), headers: _headers, body: jsonEncode({'from': from, 'body': body}));
      if (res.statusCode == 200) {
        final outcome = (jsonDecode(res.body) as Map)['outcome'];
        setState(() => _inCount++);
        _add('IN  $from  →  $outcome');
        _drainOutbox();
      } else {
        _add('IN  $from  HTTP ${res.statusCode}');
      }
    } catch (e) {
      _add('IN  forward fail: $e');
    }
  }

  Future<void> _drainOutbox() async {
    try {
      final res = await http.get(_uri('/gateway/outbox?limit=10'), headers: _headers);
      if (res.statusCode != 200) return;
      final msgs = (jsonDecode(res.body) as Map)['messages'] as List;
      for (final m in msgs) {
        final id = m['id'];
        final err = await ZyvSms.send(m['to'] as String, m['body'] as String);
        await http.post(_uri('/gateway/outbox/$id/ack'), headers: _headers, body: jsonEncode({'ok': err == null, 'error': err}));
        if (err == null) {
          setState(() => _outCount++);
          _add('OUT ${m['to']}  sent');
        } else {
          _add('OUT ${m['to']}  $err');
        }
      }
    } catch (e) {
      _add('OUT drain fail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZYVPAY Gateway'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              label: Text(_running ? 'Running' : 'Stopped'),
              backgroundColor: (_running ? Colors.green : Colors.grey).withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _url, enabled: !_running, decoration: const InputDecoration(labelText: 'Backend URL', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _token, enabled: !_running, obscureText: true, decoration: const InputDecoration(labelText: 'Gateway token', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Stat(label: 'Inbound', value: _inCount)),
            Expanded(child: _Stat(label: 'Replies sent', value: _outCount)),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? _stop : _start,
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop gateway' : 'Start gateway'),
          ),
          const SizedBox(height: 12),
          const Align(alignment: Alignment.centerLeft, child: Text('Log', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
              child: ListView(children: _log.map((l) => Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))).toList()),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Text('$value', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}
