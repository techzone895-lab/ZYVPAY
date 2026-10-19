import 'package:flutter/services.dart';

class IncomingSms {
  IncomingSms(this.from, this.body, this.time);

  factory IncomingSms.fromMap(Map<dynamic, dynamic> m) => IncomingSms(
        m['from'] as String,
        m['body'] as String,
        DateTime.fromMillisecondsSinceEpoch((m['ts'] as num).toInt()),
      );

  final String from;
  final String body;
  final DateTime time;
}

/// Direct SMS send/receive. Needs SEND_SMS and RECEIVE_SMS granted at runtime.
class ZyvSms {
  static const _methods = MethodChannel('zyv_sms');
  static const _events = EventChannel('zyv_sms/incoming');

  /// Sends [body] to [to] without opening any SMS screen.
  /// Returns null once the network accepted it, otherwise an error code.
  static Future<String?> send(String to, String body, {int? subscriptionId}) =>
      _methods.invokeMethod<String>('send', {'to': to, 'body': body, 'subscriptionId': subscriptionId});

  /// ZP1 messages received while nothing was listening.
  static Future<List<IncomingSms>> drain() async {
    final list = await _methods.invokeListMethod<Map<dynamic, dynamic>>('drain') ?? const [];
    return list.map(IncomingSms.fromMap).toList();
  }

  /// ZP1 messages as they arrive.
  static Stream<IncomingSms> get incoming =>
      _events.receiveBroadcastStream().map((e) => IncomingSms.fromMap(e as Map<dynamic, dynamic>));
}
