import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/voice_language.dart';
import '../services/voice_agent.dart';

const _bg = Color(0xFF0A0A0A);
const _card = Color(0xFF151515);
const _line = Color(0xFF262626);
const _accent = Color(0xFFFF6B35); // app accent (orange)
const _ink = Color(0xFFF4F1EE);
const _muted = Color(0xFF9A9A9A);

/// Full-screen, dark voice-language picker. Pushed modally (Navigator.push) over
/// the ambient face or dashboard, sharing the singleton [VoiceAgent] so the live
/// session reconnects in the chosen language. The UI itself stays English.
class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key, required this.voiceAgent});

  final VoiceProvider voiceAgent;

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  late String _selectedCode = RobotConfig.voiceLanguageCode;
  Timer? _popTimer;

  @override
  void dispose() {
    _popTimer?.cancel();
    super.dispose();
  }

  Future<void> _select(VoiceLanguage lang) async {
    if (lang.code == _selectedCode) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _selectedCode = lang.code); // 1. immediate visual feedback
    await RobotConfig.updateVoiceLanguage(lang.code, lang.name); // 2. persist
    widget.voiceAgent.switchLanguage(lang.code); // 3. reconnect agent (background)

    if (!mounted) return;
    // 4. brief confirmation
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        backgroundColor: _card,
        duration: const Duration(milliseconds: 1600),
        content: Text('Switching to ${lang.name}… Mini will reconnect',
            style: const TextStyle(color: _ink)),
      ));
    // 5. auto-close — language is saved, the agent reconnects in the background
    _popTimer?.cancel();
    _popTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = languageForCode(_selectedCode);
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Expanded(
                child: Center(
                  child: Text('Voice Language',
                      style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              // current-language badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  border: Border.all(color: _accent.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('${current.flag}  ${current.code.toUpperCase()}',
                    style: const TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text('Mini will speak in your selected language',
                style: TextStyle(color: _muted, fontSize: 13)),
          ),
          // ── Grid of languages ──
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.6,
              ),
              itemCount: kSupportedLanguages.length,
              itemBuilder: (context, i) {
                final lang = kSupportedLanguages[i];
                return _LanguageCard(
                  lang: lang,
                  selected: lang.code == _selectedCode,
                  onTap: () => _select(lang),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({required this.lang, required this.selected, required this.onTap});
  final VoiceLanguage lang;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _accent : _line,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: _accent.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: 1)]
              : null,
        ),
        child: Stack(children: [
          Row(children: [
            Text(lang.flag, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lang.name,
                      style: TextStyle(
                          color: selected ? _accent : _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(lang.nativeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 13)),
                ],
              ),
            ),
          ]),
          if (selected)
            const Positioned(
              top: 0,
              right: 0,
              child: Icon(Icons.check_circle_rounded, color: _accent, size: 20),
            ),
        ]),
      ),
    );
  }
}

/// Reusable globe button + current-language badge. Tapping opens the picker with
/// the shared [voiceAgent]; [onReturned] fires on pop so the host can refresh its
/// badge. Used on both the ambient face and the dashboard top bar.
class LanguageButton extends StatelessWidget {
  const LanguageButton({
    super.key,
    required this.voiceAgent,
    this.onReturned,
    this.dark = false,
    this.large = false,
  });

  final VoiceProvider voiceAgent;
  final VoidCallback? onReturned;
  final bool dark; // darker chrome for the dashboard top bar
  final bool large; // bigger, more discoverable variant (ambient face screen)

  @override
  Widget build(BuildContext context) {
    final lang = languageForCode(RobotConfig.voiceLanguageCode);
    final code = lang.code.toUpperCase();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LanguageSelectionScreen(voiceAgent: voiceAgent),
        ));
        onReturned?.call();
      },
      child: Container(
        padding: large
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF171717) : Colors.black.withValues(alpha: 0.40),
          border: Border.all(
              color: dark ? _line : Colors.white30, width: large ? 1.5 : 1),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.language_rounded, size: large ? 30 : 18, color: _ink),
          SizedBox(width: large ? 12 : 6),
          // Big variant shows the flag + name so visitors recognise it as a
          // language switch, not just an icon.
          if (large) ...[
            Text(lang.flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Text(lang.name,
                style: const TextStyle(
                    color: _ink, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
          ],
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: large ? 10 : 6, vertical: large ? 5 : 2),
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(large ? 8 : 6),
            ),
            child: Text(code,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: large ? 15 : 10,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}
