import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/xboom_lead_api.dart';

/// Full-screen visitor form for the face screen's Order / Enquiry FABs.
/// Pushed modally over the ambient face (like LanguageSelectionScreen — no PIN:
/// this is FOR visitors). Collects name + phone + what they want, submits to
/// the spine (`/xboom/lead` → XBoom Workflow OS sales pipeline), then shows a
/// thank-you and returns to the face on its own so the kiosk never sits on a
/// stale form.
class LeadFormScreen extends StatefulWidget {
  const LeadFormScreen({
    super.key,
    required this.kind,
    this.initialProduct,
    this.initialProductCode,
  });

  final LeadKind kind;

  /// Prefill from the catalog picker. When the visitor keeps the product text
  /// unchanged, the real SKU ([initialProductCode]) is submitted as
  /// product_code; editing the text drops the SKU (it no longer matches).
  final String? initialProduct;
  final String? initialProductCode;

  @override
  State<LeadFormScreen> createState() => _LeadFormScreenState();
}

class _LeadFormScreenState extends State<LeadFormScreen> {
  static const _accent = Color(0xFFFF6B35);
  static const _bg = Color(0xFF0F0F0F);
  static const _card = Color(0xFF1A1A1A);
  static const _stroke = Color(0xFF3A3A3A);

  final _api = XboomLeadApi();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _product = TextEditingController();
  final _notes = TextEditingController();
  int _quantity = 1;

  bool _submitting = false;
  bool _submitted = false;
  String? _error;
  Timer? _autoClose;
  Timer? _idleClose;

  bool get _isOrder => widget.kind == LeadKind.order;

  @override
  void initState() {
    super.initState();
    if (widget.initialProduct != null) _product.text = widget.initialProduct!;
    _restartIdleTimer();
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    _idleClose?.cancel();
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _product.dispose();
    _notes.dispose();
    super.dispose();
  }

  // A visitor who walks away mid-form must not leave their details on screen
  // for the next person — abandon after 2 minutes without a keystroke.
  void _restartIdleTimer() {
    _idleClose?.cancel();
    _idleClose = Timer(const Duration(minutes: 2), () {
      if (mounted && !_submitted) Navigator.of(context).maybePop();
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    // The SKU only stays valid while the product text is what the catalog gave us.
    final productText = _product.text.trim();
    final code =
        productText == widget.initialProduct?.trim() ? widget.initialProductCode : null;
    final res = await _api.submit(
      kind: widget.kind,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      product: productText,
      productCode: code,
      email: _email.text.trim(),
      quantity: _isOrder ? _quantity : null,
      notes: _notes.text.trim(),
    );
    if (!mounted) return;
    if (res.ok) {
      setState(() {
        _submitting = false;
        _submitted = true;
      });
      _idleClose?.cancel();
      // Give the visitor a beat to read the thank-you, then back to the face.
      _autoClose = Timer(const Duration(seconds: 8), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    } else {
      setState(() {
        _submitting = false;
        _error =
            'Sorry, that didn’t go through. Please try again or ask our staff.';
      });
      debugPrint('LeadForm: submit failed — ${res.reason}');
    }
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 16),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: _card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5484D)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5484D), width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final title = _isOrder ? 'Place an Order' : 'Make an Enquiry';
    final subtitle = _isOrder
        ? 'Tell us what you’d like to buy — our sales team will get it ready.'
        : 'Tell us what you’re looking for — our team will get back to you.';
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _submitted ? _thankYou() : _form(title, subtitle),
      ),
    );
  }

  Widget _form(String title, String subtitle) {
    return Listener(
      // Any touch counts as activity for the abandon timer.
      onPointerDown: (_) => _restartIdleTimer(),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
          child: Row(children: [
            Icon(
              _isOrder
                  ? Icons.shopping_cart_rounded
                  : Icons.contact_support_rounded,
              color: _accent,
              size: 34,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 14)),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white70, size: 34),
              tooltip: 'Close',
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(children: [
                TextFormField(
                  controller: _name,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec('Your name *'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 18),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
                      ],
                      decoration: _dec('Phone number *'),
                      validator: (v) {
                        final digits =
                            (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                        return digits.length < 7
                            ? 'Please enter a valid phone number'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextFormField(
                      controller: _email,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 18),
                      keyboardType: TextInputType.emailAddress,
                      decoration: _dec('Email (optional)'),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return null;
                        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
                            ? null
                            : 'That email doesn’t look right';
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _product,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: _dec(
                    _isOrder
                        ? 'What would you like to order? *'
                        : 'What are you interested in? *',
                    hint: 'e.g. Agriculture drone, training, spare parts…',
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Please tell us what you need'
                      : null,
                ),
                if (_isOrder) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _stroke),
                    ),
                    child: Row(children: [
                      const Text('Quantity',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 16)),
                      const Spacer(),
                      _qtyButton(Icons.remove_rounded,
                          () => setState(() => _quantity = (_quantity - 1).clamp(1, 99))),
                      SizedBox(
                        width: 64,
                        child: Text('$_quantity',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                      ),
                      _qtyButton(Icons.add_rounded,
                          () => setState(() => _quantity = (_quantity + 1).clamp(1, 99))),
                    ]),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notes,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  maxLines: 2,
                  decoration: _dec('Anything else? (optional)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      style: const TextStyle(
                          color: Color(0xFFE5484D), fontSize: 15)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 3))
                        : Text(
                            _isOrder ? 'Submit Order Request' : 'Submit Enquiry',
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      );

  Widget _thankYou() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4ADE80).withValues(alpha: 0.15),
          ),
          child: const Icon(Icons.check_rounded,
              color: Color(0xFF4ADE80), size: 64),
        ),
        const SizedBox(height: 24),
        Text(
          _isOrder ? 'Order request received!' : 'Enquiry received!',
          style: const TextStyle(
              color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'Thank you — our team will be with you shortly.',
          style: TextStyle(color: Colors.white54, fontSize: 17),
        ),
        const SizedBox(height: 28),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Done',
              style: TextStyle(color: Color(0xFFFF6B35), fontSize: 18)),
        ),
      ]),
    );
  }
}
