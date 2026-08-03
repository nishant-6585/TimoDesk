import 'package:flutter/material.dart';
import 'config.dart';

/// Full-screen PIN gate for the admin area (Dashboard/Settings/Enroll).
/// A visitor tapping the ambient face screen lands here first; only the correct
/// [RobotConfig.dashboardPin] pops `true` and lets them through. Cancel pops
/// `false`. Auto-checks once the entry reaches the stored PIN's length.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  static const _accent = Color(0xFFFF6B35);
  static const _bg = Color(0xFF0F0F0F);
  static const _key = Color(0xFF1A1A1A);

  String _entry = '';
  bool _error = false;

  void _press(String d) {
    if (_entry.length >= 12) return;
    setState(() {
      _entry += d;
      _error = false;
    });
    final pin = RobotConfig.dashboardPin;
    if (_entry.length >= pin.length) {
      if (_entry == pin) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = true;
          _entry = '';
        });
      }
    }
  }

  void _backspace() {
    if (_entry.isNotEmpty) {
      setState(() => _entry = _entry.substring(0, _entry.length - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_rounded, color: _accent, size: 56),
              const SizedBox(height: 18),
              Text(
                _error ? 'Wrong PIN — try again' : 'Enter PIN to access admin',
                style: TextStyle(
                  color: _error ? const Color(0xFFE5484D) : Colors.white70,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                height: 22,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    _entry.length,
                    (_) => Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration:
                          const BoxDecoration(color: _accent, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 34),
              SizedBox(
                width: 500,
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 18,
                  childAspectRatio: 1.25,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final n in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                      _digit(n),
                    _icon(Icons.close_rounded, () => Navigator.of(context).pop(false)),
                    _digit('0'),
                    _icon(Icons.backspace_outlined, _backspace),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _digit(String n) => Material(
        color: _key,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _press(n),
          child: Center(
            child: Text(n,
                style: const TextStyle(
                    color: Colors.white, fontSize: 40, fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget _icon(IconData ic, VoidCallback onTap) => Material(
        color: _key,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(child: Icon(ic, color: Colors.white70, size: 34)),
        ),
      );
}
