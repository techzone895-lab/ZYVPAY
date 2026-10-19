import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen 6-digit PIN entry, like the UPI PIN screens.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.title, this.subtitle, this.confirm = false});

  final String title;
  final String? subtitle;
  final bool confirm; // when true, asks the PIN twice and checks they match

  /// Pushes the PIN pad and returns the entered PIN, or null if cancelled.
  static Future<String?> ask(BuildContext context, {required String title, String? subtitle, bool confirm = false}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => PinPad(title: title, subtitle: subtitle, confirm: confirm)),
    );
  }

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  String? _first;
  String? _error;
  static const _len = 6;

  void _tap(String d) {
    if (_pin.length >= _len) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == _len) _submit();
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    if (widget.confirm && _first == null) {
      setState(() {
        _first = _pin;
        _pin = '';
      });
      return;
    }
    if (widget.confirm && _first != _pin) {
      setState(() {
        _error = 'PIN match nahi hua, dobara set karein';
        _pin = '';
        _first = null;
      });
      return;
    }
    Navigator.of(context).pop(_pin);
  }

  @override
  Widget build(BuildContext context) {
    final asking = widget.confirm && _first != null ? 'PIN dobara daalein' : widget.title;
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Icon(Icons.lock_outline, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(asking, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(widget.subtitle!, style: TextStyle(color: Theme.of(context).hintColor)),
            ],
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_len, (i) {
                final filled = i < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? Theme.of(context).colorScheme.primary : Colors.transparent,
                    border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.6),
                  ),
                );
              }),
            ),
            SizedBox(
              height: 28,
              child: _error == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
            ),
            const Spacer(),
            _Keypad(onDigit: _tap, onBack: _back),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBack});
  final void Function(String) onDigit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      childAspectRatio: 1.8,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: keys.map((k) {
        if (k.isEmpty) return const SizedBox();
        return InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: () => k == '<' ? onBack() : onDigit(k),
          child: Center(
            child: k == '<'
                ? const Icon(Icons.backspace_outlined, size: 26)
                : Text(k, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
          ),
        );
      }).toList(),
    );
  }
}
