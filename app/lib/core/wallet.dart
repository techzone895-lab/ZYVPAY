import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyv_sms/zyv_sms.dart';

import 'protocol.dart';

/// Default backend; can be changed from Settings for testing.
const defaultApiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://zyvpay-api.onrender.com');

enum TxnStatus { success, pending, failed }

enum Channel { net, sms }

class Txn {
  Txn({
    required this.ctr,
    required this.vpa,
    required this.name,
    required this.amount,
    required this.status,
    required this.time,
    required this.channel,
    this.ref,
    this.code,
  });

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        ctr: j['ctr'] as int,
        vpa: j['vpa'] as String,
        name: j['name'] as String,
        amount: j['amount'] as int,
        status: TxnStatus.values.byName(j['status'] as String),
        time: DateTime.fromMillisecondsSinceEpoch(j['time'] as int),
        channel: Channel.values.byName(j['channel'] as String),
        ref: j['ref'] as String?,
        code: j['code'] as String?,
      );

  final int ctr;
  final String vpa;
  final String name;
  final int amount;
  TxnStatus status;
  final DateTime time;
  Channel channel;
  String? ref;
  String? code;

  Map<String, dynamic> toJson() => {
        'ctr': ctr,
        'vpa': vpa,
        'name': name,
        'amount': amount,
        'status': status.name,
        'time': time.millisecondsSinceEpoch,
        'channel': channel.name,
        'ref': ref,
        'code': code,
      };
}

String errorMessage(String? code) => switch (code) {
      'BAD_PIN' => 'Galat PIN. Dobara try karein.',
      'LOCKED' => 'Bahut baar galat PIN. Account lock ho gaya hai, support se sampark karein.',
      'LOW_BALANCE' => 'Balance kam hai.',
      'LIMIT' => 'Ek payment ki limit se zyada amount hai.',
      'DAY_LIMIT' => 'Aaj ki payment limit poori ho gayi.',
      'NOT_REGISTERED' || 'UNKNOWN' => 'Device registered nahi hai. App dobara setup karein.',
      'SIM_MISMATCH' => 'SMS usi SIM se bheja jaana chahiye jisse number register hua tha.',
      'REPLAY' => 'Ye request pehle hi process ho chuki hai.',
      'NO_CHANNEL' => 'Na internet hai na SMS bhej paaye. Signal aane par try karein.',
      'SMS_TIMEOUT' => 'SMS chala gaya par abhi tak confirm nahi hua. History mein status dekhein.',
      'REG_TIMEOUT' => 'Number verify nahi hua. Check karein ki SIM mein SMS balance hai aur signal hai.',
      _ => 'Payment fail ho gaya${code == null ? '' : ' ($code)'}.',
    };

/// Result of a payment or balance request.
class Outcome {
  Outcome(this.status, {this.ref, this.balance, this.code, required this.channel});
  final TxnStatus status;
  final String? ref;
  final int? balance;
  final String? code;
  final Channel channel;

  bool get ok => status != TxnStatus.failed;
}

/// Holds the device identity, balance and history, and runs requests over the
/// internet when available or over SMS otherwise. The UI builds the SMS text and
/// asks the user to send it; this class only tracks the reply.
class Wallet extends ChangeNotifier {
  Wallet._();
  static final Wallet instance = Wallet._();

  static const _secure = FlutterSecureStorage();
  static const _smsWait = Duration(seconds: 90);

  late SharedPreferences _prefs;
  String? sid;
  String? phone;
  String? gatewayNumber;
  String apiBase = defaultApiBase;
  String name = '';
  List<int>? _secret;
  int _ctr = 0;
  int? balance;
  DateTime? balanceAt;
  List<Txn> history = [];
  bool online = false;

  // ctr -> completer resolved when the matching reply SMS arrives.
  final _waiters = <int, Completer<ZpReply>>{};
  StreamSubscription<IncomingSms>? _smsSub;
  final _rng = Random.secure();

  bool get isSetUp => sid != null && _secret != null;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    apiBase = _prefs.getString('apiBase') ?? defaultApiBase;
    sid = _prefs.getString('sid');
    phone = _prefs.getString('phone');
    gatewayNumber = _prefs.getString('gatewayNumber');
    name = _prefs.getString('name') ?? '';
    _ctr = _prefs.getInt('ctr') ?? 0;
    balance = _prefs.containsKey('balance') ? _prefs.getInt('balance') : null;
    final ba = _prefs.getInt('balanceAt');
    balanceAt = ba == null ? null : DateTime.fromMillisecondsSinceEpoch(ba);
    final sec = await _secure.read(key: 'secret');
    _secret = sec == null ? null : base64.decode(sec);
    history = (jsonDecode(_prefs.getString('history') ?? '[]') as List)
        .map((e) => Txn.fromJson(e as Map<String, dynamic>))
        .toList();
    _listenForSms();
    _watchConnectivity();
    notifyListeners();
  }

  void _watchConnectivity() {
    Connectivity().onConnectivityChanged.listen((r) {
      online = !r.contains(ConnectivityResult.none);
      notifyListeners();
    });
    Connectivity().checkConnectivity().then((r) {
      online = !r.contains(ConnectivityResult.none);
      notifyListeners();
    });
  }

  void _listenForSms() {
    _smsSub?.cancel();
    _smsSub = ZyvSms.incoming.listen((m) => _handleReply(m.body));
    ZyvSms.drain().then((list) {
      for (final m in list) {
        _handleReply(m.body);
      }
    });
  }

  void _handleReply(String body) {
    final r = ZpReply.parse(body);
    if (r == null) return;
    if (r.kind == ReplyKind.registered) {
      _waiters.remove(-1)?.complete(r);
      return;
    }
    if (r.ctr != null) _waiters.remove(r.ctr)?.complete(r);
  }

  Future<void> _save() async {
    await _prefs.setString('sid', sid ?? '');
    await _prefs.setString('phone', phone ?? '');
    await _prefs.setString('gatewayNumber', gatewayNumber ?? '');
    await _prefs.setString('name', name);
    await _prefs.setInt('ctr', _ctr);
    if (balance != null) await _prefs.setInt('balance', balance!);
    if (balanceAt != null) await _prefs.setInt('balanceAt', balanceAt!.millisecondsSinceEpoch);
    await _prefs.setString('history', jsonEncode(history.map((t) => t.toJson()).toList()));
  }

  Future<void> setApiBase(String v) async {
    apiBase = v.trim();
    await _prefs.setString('apiBase', apiBase);
    notifyListeners();
  }

  // ---- Setup / registration ----

  /// Creates the device on the backend. Needs internet once, at setup.
  /// Returns the verification SMS the UI must get the user to send.
  Future<SmsDraft> register({required String phone, required String name, required String pin}) async {
    final secret = _randomBytes(_rng, 32);
    final pinKey = derivePinKey(secret, pin);
    final res = await http
        .post(Uri.parse('$apiBase/api/devices'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'pinKey': base64.encode(pinKey)}))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 201) throw 'Registration failed (${res.statusCode})';
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    sid = j['sid'] as String;
    gatewayNumber = j['gatewayNumber'] as String?;
    this.phone = phone;
    this.name = name;
    _secret = secret;
    _ctr = 0;
    await _secure.write(key: 'secret', value: base64.encode(secret));
    await _save();
    notifyListeners();
    return SmsDraft(gatewayNumber!, buildRegister(sid!, j['regCode'] as String));
  }

  /// Waits for the registration-confirmation SMS after the user has sent the verify SMS.
  Future<bool> awaitRegistration() async {
    final c = _waiters.putIfAbsent(-1, () => Completer<ZpReply>());
    try {
      await c.future.timeout(const Duration(seconds: 120));
      return true;
    } on TimeoutException {
      _waiters.remove(-1);
      return false;
    }
  }

  // ---- Payments ----

  int _nextCtr() {
    _ctr += 1;
    _prefs.setInt('ctr', _ctr);
    return _ctr;
  }

  /// Runs a payment. Tries the internet first; if that is not reachable it returns
  /// an [SmsDraft] the UI must hand to the SMS app, then [awaitSms] tracks the reply.
  Future<PaymentPlan> preparePayment(Payee payee, int amountPaise, String pin) async {
    final ctr = _nextCtr();
    final text = buildPay(derivePinKey(_secret!, pin), sid!, ctr, amountPaise, payee.vpa);
    final txn = Txn(
      ctr: ctr,
      vpa: payee.vpa,
      name: payee.name,
      amount: amountPaise,
      status: TxnStatus.pending,
      time: DateTime.now(),
      channel: Channel.net,
    );
    return PaymentPlan(ctr: ctr, text: text, txn: txn);
  }

  Future<bool> hasInternet() async {
    final r = await Connectivity().checkConnectivity();
    return !r.contains(ConnectivityResult.none);
  }

  /// Sends the request over the internet. Throws on network trouble so the caller
  /// can fall back to SMS.
  Future<Outcome> sendOverNet(String text) async {
    final res = await http
        .post(Uri.parse('$apiBase/api/request'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode({'text': text}))
        .timeout(const Duration(seconds: 20));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final status = switch (j['status']) {
      'success' => TxnStatus.success,
      'pending' => TxnStatus.pending,
      _ => TxnStatus.failed,
    };
    return Outcome(status, ref: j['ref'] as String?, balance: j['balance'] as int?, code: j['code'] as String?, channel: Channel.net);
  }

  /// The SMS the UI must get the user to send (via the system SMS composer).
  SmsDraft smsDraft(String text) => SmsDraft(gatewayNumber!, text);

  /// After the user has sent the SMS, waits for the reply that matches [ctr].
  Future<Outcome> awaitSms(int ctr) async {
    final c = _waiters.putIfAbsent(ctr, () => Completer<ZpReply>());
    try {
      final r = await c.future.timeout(_smsWait);
      final status = switch (r.kind) {
        ReplyKind.ok => TxnStatus.success,
        ReplyKind.pending => TxnStatus.pending,
        _ => TxnStatus.failed,
      };
      if (r.balance != null) _setBalance(r.balance!);
      return Outcome(status, ref: r.ref, balance: r.balance, code: r.code, channel: Channel.sms);
    } on TimeoutException {
      _waiters.remove(ctr);
      return Outcome(TxnStatus.pending, code: 'SMS_TIMEOUT', channel: Channel.sms);
    }
  }

  Future<void> recordTxn(Txn txn, Outcome outcome) async {
    txn.status = outcome.status;
    txn.channel = outcome.channel;
    txn.ref = outcome.ref;
    txn.code = outcome.code;
    history.insert(0, txn);
    if (history.length > 100) history.removeRange(100, history.length);
    if (outcome.balance != null) _setBalance(outcome.balance!);
    await _save();
    notifyListeners();
  }

  void _setBalance(int v) {
    balance = v;
    balanceAt = DateTime.now();
    notifyListeners();
  }

  /// Balance enquiry text; UI decides net vs SMS the same way as a payment.
  BalancePlan balancePlan(String pin) {
    final ctr = _nextCtr();
    return BalancePlan(ctr: ctr, text: buildBalance(derivePinKey(_secret!, pin), sid!, ctr));
  }

  Future<void> reset() async {
    await _secure.deleteAll();
    await _prefs.clear();
    sid = null;
    _secret = null;
    history = [];
    balance = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _smsSub?.cancel();
    super.dispose();
  }
}

class SmsDraft {
  SmsDraft(this.to, this.text);
  final String to;
  final String text;
}

class PaymentPlan {
  PaymentPlan({required this.ctr, required this.text, required this.txn});
  final int ctr;
  final String text;
  final Txn txn;
}

class BalancePlan {
  BalancePlan({required this.ctr, required this.text});
  final int ctr;
  final String text;
}

/// 32 cryptographically-random bytes without pulling in extra packages.
List<int> _randomBytes(Random rng, int n) => List<int>.generate(n, (_) => rng.nextInt(256));
