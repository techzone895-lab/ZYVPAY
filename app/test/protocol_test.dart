import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyvpay/core/protocol.dart';

void main() {
  // Same vector as backend/test/protocol.test.js.
  final secret = List.filled(32, 7);

  test('pin key and pay message match the backend', () {
    final k = derivePinKey(secret, '123456');
    expect(base64.encode(k), 'QLsapKV6o6ftZ5m3FBNXmw9URJvIxAl0n7+DcPYkJi0=');
    expect(buildPay(k, 'ABCD2345', 3, 25050, 'Shop@OkAxis'), 'ZP1 P ABCD2345 3 25050 shop@okaxis pyW90s6BpJvGm5aS');
  });

  test('parses server reply tags', () {
    final ok = ZpReply.parse('ZYVPAY: Rs 250.50 paid to shop@okaxis. Ref 1. [ZP1 S 3 OK 123456789012 274950]')!;
    expect([ok.kind, ok.ctr, ok.ref, ok.balance], [ReplyKind.ok, 3, '123456789012', 274950]);
    final bal = ZpReply.parse('ZYVPAY: Balance Rs 5.00. [ZP1 S 4 OK - 500]')!;
    expect([bal.ref, bal.balance], [null, 500]);
    final fail = ZpReply.parse('ZYVPAY: Payment failed (BAD_PIN). [ZP1 S 5 FAIL BAD_PIN]')!;
    expect([fail.kind, fail.code], [ReplyKind.fail, 'BAD_PIN']);
    expect(ZpReply.parse('[ZP1 S 6 PEND 999999999999]')!.kind, ReplyKind.pending);
    expect(ZpReply.parse('[ZP1 V ABCD2345 OK]')!.sid, 'ABCD2345');
    expect(ZpReply.parse('hello'), isNull);
  });

  test('reads UPI QR codes', () {
    final p = Payee.fromQr('upi://pay?pa=Shop@okaxis&pn=Ram%20Store&am=99.5&cu=INR')!;
    expect([p.vpa, p.name, p.amountPaise], ['shop@okaxis', 'Ram Store', 9950]);
    expect(Payee.fromQr('ram@ybl')!.name, 'ram@ybl');
    expect(Payee.fromQr('https://example.com'), isNull);
  });

  test('amount parsing and formatting', () {
    expect(parseRupees('10'), 1000);
    expect(parseRupees('0.05'), 5);
    expect(parseRupees('0'), isNull);
    expect(parseRupees('1.234'), isNull);
    expect(formatRupees(123456789), '₹12,34,567.89');
    expect(formatRupees(50000), '₹500');
  });
}
