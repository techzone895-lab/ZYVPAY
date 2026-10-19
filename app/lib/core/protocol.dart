// Client side of the ZP1 SMS protocol. Must stay byte-for-byte compatible with
// backend/src/protocol.js; test/protocol_test.dart checks the shared vector.
import 'dart:convert';

import 'package:crypto/crypto.dart';

const zpVersion = 'ZP1';
const _macLen = 16;
final _vpaRe = RegExp(r'^[a-z0-9._-]{1,64}@[a-z0-9.-]{2,32}$');

List<int> derivePinKey(List<int> deviceSecret, String pin) =>
    Hmac(sha256, deviceSecret).convert(utf8.encode('pin|$pin')).bytes;

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String zpMac(List<int> pinKey, List<String> fields) =>
    _b64url(Hmac(sha256, pinKey).convert(utf8.encode(fields.join('|'))).bytes).substring(0, _macLen);

bool isValidVpa(String vpa) => _vpaRe.hasMatch(vpa.trim().toLowerCase());

String _signed(List<int> pinKey, List<String> fields) => '${fields.join(' ')} ${zpMac(pinKey, fields)}';

String buildPay(List<int> pinKey, String sid, int ctr, int amountPaise, String vpa) =>
    _signed(pinKey, [zpVersion, 'P', sid, '$ctr', '$amountPaise', vpa.trim().toLowerCase()]);

String buildBalance(List<int> pinKey, String sid, int ctr) => _signed(pinKey, [zpVersion, 'B', sid, '$ctr']);

String buildRegister(String sid, String regCode) => '$zpVersion R $sid $regCode';

enum ReplyKind { ok, pending, fail, registered }

/// Machine tag at the end of a server SMS / API message, e.g. `[ZP1 S 4 OK 123456789012 74950]`.
class ZpReply {
  ZpReply(this.kind, {this.ctr, this.ref, this.balance, this.code, this.sid});

  final ReplyKind kind;
  final int? ctr;
  final String? ref;
  final int? balance;
  final String? code;
  final String? sid;

  static final _tag = RegExp(r'\[ZP1 (S|V) (\S+) (OK|PEND|FAIL)(?: (\S+))?(?: (\d+))?\]');

  static ZpReply? parse(String text) {
    final m = _tag.firstMatch(text);
    if (m == null) return null;
    if (m[1] == 'V') return ZpReply(ReplyKind.registered, sid: m[2]);
    final ctr = int.tryParse(m[2]!);
    switch (m[3]) {
      case 'OK':
        final ref = m[4] == '-' ? null : m[4];
        return ZpReply(ReplyKind.ok, ctr: ctr, ref: ref, balance: m[5] == null ? null : int.parse(m[5]!));
      case 'PEND':
        return ZpReply(ReplyKind.pending, ctr: ctr, ref: m[4]);
      default:
        return ZpReply(ReplyKind.fail, ctr: ctr, code: m[4]);
    }
  }
}

/// Payee read from a UPI QR (`upi://pay?pa=...&pn=...&am=...`) or typed by hand.
class Payee {
  Payee(this.vpa, {String? name, this.amountPaise, this.note}) : name = (name == null || name.isEmpty) ? vpa : name;

  final String vpa;
  final String name;
  final int? amountPaise;
  final String? note;

  static Payee? fromQr(String raw) {
    final text = raw.trim();
    if (isValidVpa(text)) return Payee(text.toLowerCase());
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme.toLowerCase() != 'upi') return null;
    final q = uri.queryParameters;
    final pa = (q['pa'] ?? '').trim().toLowerCase();
    if (!isValidVpa(pa)) return null;
    return Payee(pa, name: q['pn'], amountPaise: parseRupees(q['am'] ?? ''), note: q['tn']);
  }
}

/// "250.5" -> 25050. Returns null for anything that is not a positive amount with at most 2 decimals.
int? parseRupees(String s) {
  final m = RegExp(r'^(\d{1,7})(?:\.(\d{1,2}))?$').firstMatch(s.trim());
  if (m == null) return null;
  final paise = int.parse(m[1]!) * 100 + int.parse((m[2] ?? '0').padRight(2, '0'));
  return paise > 0 ? paise : null;
}

String formatRupees(int paise, {bool symbol = true}) {
  final r = paise ~/ 100;
  final p = paise % 100;
  final s = r.toString();
  // Indian grouping: 12,34,567
  String grouped;
  if (s.length <= 3) {
    grouped = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  final out = p == 0 ? grouped : '$grouped.${p.toString().padLeft(2, '0')}';
  return symbol ? '₹$out' : out;
}
