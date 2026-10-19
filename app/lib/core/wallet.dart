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

class WalletException implements Exception {
  WalletException(this.code);
  final String code;

  @override
  String toString() => errorMessage(code);
}

String errorMessage(String? code) => switch (code) {
      'BAD_PIN' => 'Galat PIN. Dobara try karein.',
      'LOCKED' => 'Bahut baar galat PIN. Account lock ho gaya hai, support se sampark karein.',
      'LOW_BALANCE' => 'Balance kam hai.',
      'LIMIT' => 'Ek payment ki limit se zyada amount hai.',
      'DAY_LIMIT' => 'Aaj ki payment limit poori ho gayi.',
      'NOT_REGISTERED' || 'UNKNOWN' => 'Device registered nahi hai. App dobara setup karein.',
      'REPLAY' => 'Ye request pehle hi process ho chuki hai.',
      'NO_NETWORK' => 'Na internet hai na mobile network. Signal aane par try karein.',
      'REG_TIMEOUT' => 'Number verify nahi hua. Check karein ki SIM mein SMS balance hai.',
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
}

/// Device identity, history and the two delivery channels (internet first, SMS fallback).
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

  final _waiters = <int, Completer