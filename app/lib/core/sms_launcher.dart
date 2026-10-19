import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's own SMS app with the recipient and message pre-filled, so the
/// user taps Send themselves. ZYVPAY never sends an SMS silently — the user always
/// sees and confirms the message.
Future<bool> openSmsComposer(String to, String body) async {
  final uri = Uri(scheme: 'sms', path: to, queryParameters: {'body': body});
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  // Some OEMs reject query parameters; fall back to copying the text.
  await Clipboard.setData(ClipboardData(text: body));
  return false;
}
