import 'dart:async';

import 'package:flutter/material.dart';

import '../services/xboom_lead_api.dart';
import 'lead_form_screen.dart';

/// Catalog-first step of the Order / Enquiry flow: the visitor searches the
/// XBoom price list (spine GET /xboom/catalog → robot-catalog edge function),
/// taps a product, and lands in LeadFormScreen with the product + real SKU
/// prefilled. Search-first by design — the catalog is thousands of rows, so we
/// page 30 at a time and debounce the search box. If the catalog is
/// unreachable (spine down, XBoom down) the visitor can still type the
/// product by hand — capturing the lead always beats a perfect SKU.
class ProductPickerScreen extends StatefulWidget {
  const ProductPickerScreen({super.key, required this.kind});

  final LeadKind kind;

  @override
  State<ProductPickerScreen> createState() => _ProductPickerScreenState();
}

class _ProductPickerScreenState extends State<ProductPickerScreen> {
  static const _accent = Color(0xFFFF6B35);
  static const _bg = Color(0xFF0F0F0F);
  static const _card = Color(0xFF1A1A1A);
  static const _stroke = Color(0xFF3A3A3A);
  static const _pageSize = 30;

  final _api = XboomLeadApi();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  Timer? _idleClose;

  final List<CatalogProduct> _products = [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _failed = false; // catalog unreachable → offer free-text path only

  bool get _isOrder => widget.kind == LeadKind.order;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(_maybeLoadMore);
    _restartIdleTimer();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _idleClose?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Same abandon rule as the lead form: a browsing visitor who walks away
  // must not leave the kiosk sitting on a search screen.
  void _restartIdleTimer() {
    _idleClose?.cancel();
    _idleClose = Timer(const Duration(minutes: 2), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _onSearchChanged(String _) {
    _restartIdleTimer();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _failed = false;
        _products.clear();
        _total = 0;
      });
    } else {
      if (_loadingMore || _products.length >= _total) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = await _api.fetchProducts(
        search: _search.text.trim(),
        limit: _pageSize,
        offset: reset ? 0 : _products.length,
      );
      if (!mounted) return;
      setState(() {
        _products.addAll(page.products);
        _total = page.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('ProductPicker: catalog fetch failed — $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _failed = true;
      });
    }
  }

  void _maybeLoadMore() {
    if (_scroll.position.extentAfter < 400) _load(reset: false);
  }

  Future<void> _pick(CatalogProduct? product) async {
    // Replace so Back from the form returns to the FACE, not a stale search.
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LeadFormScreen(
        kind: widget.kind,
        initialProduct: product?.name,
        initialProductCode: product?.sku,
      ),
    ));
  }

  String _priceLabel(CatalogProduct p) {
    if (p.price == null || p.price! <= 0) return 'Price on request';
    final s = p.price!.toStringAsFixed(0).replaceAllMapped(
        // Indian digit grouping: 12,34,567
        RegExp(r'(\d)(?=(\d\d)+\d$)'),
        (m) => '${m[1]},');
    return '₹$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
            child: Row(children: [
              Icon(
                _isOrder ? Icons.shopping_cart_rounded : Icons.contact_support_rounded,
                color: _accent,
                size: 34,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _isOrder ? 'What would you like to order?' : 'What are you interested in?',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Text('Search our products and tap one to continue',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                ]),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 34),
                tooltip: 'Close',
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 19),
              decoration: InputDecoration(
                hintText: 'Search drones, brands, categories…',
                hintStyle: const TextStyle(color: Colors.white24),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 28),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                        onPressed: () {
                          _search.clear();
                          _load(reset: true);
                        },
                      ),
                filled: true,
                fillColor: _card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _stroke),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _accent, width: 2),
                ),
              ),
            ),
          ),
          Expanded(child: _body()),
          // Always-available escape hatch: not in the catalog → free-text form.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => _pick(null),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _stroke),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.edit_note_rounded, color: Colors.white70),
                label: const Text("Can't find it? Type it yourself",
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_failed) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white24, size: 56),
          const SizedBox(height: 12),
          const Text('Product catalog is unavailable right now',
              style: TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('You can still type what you need below',
              style: TextStyle(color: Colors.white38, fontSize: 14)),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh_rounded, color: _accent),
            label: const Text('Retry', style: TextStyle(color: _accent, fontSize: 16)),
          ),
        ]),
      );
    }
    if (_products.isEmpty) {
      return const Center(
        child: Text('No products match your search',
            style: TextStyle(color: Colors.white38, fontSize: 16)),
      );
    }
    return Listener(
      onPointerDown: (_) => _restartIdleTimer(),
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        itemCount: _products.length + (_products.length < _total ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i >= _products.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                  child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(color: _accent, strokeWidth: 3))),
            );
          }
          final p = _products[i];
          final subtitleBits = <String>[
            if ((p.brand ?? '').isNotEmpty) p.brand!,
            if ((p.category ?? '').isNotEmpty) p.category!,
          ];
          return InkWell(
            onTap: () => _pick(p),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _stroke),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                    if (subtitleBits.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitleBits.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white38, fontSize: 13)),
                    ],
                  ]),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_priceLabel(p),
                      style: const TextStyle(
                          color: _accent, fontSize: 17, fontWeight: FontWeight.bold)),
                  if ((p.availability ?? '').isNotEmpty && p.availability != 'In Stock')
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(p.availability!,
                          style: const TextStyle(color: Colors.amber, fontSize: 12)),
                    ),
                ]),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 28),
              ]),
            ),
          );
        },
      ),
    );
  }
}
