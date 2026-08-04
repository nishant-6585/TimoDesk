/// xboom_lead_api.dart — spine HTTP call for showroom order / enquiry capture.
///
/// The face screen's Order and Enquiry FABs collect a visitor's details and
/// POST them to the spine (`/xboom/lead`), which forwards into XBoom Workflow
/// OS's sales pipeline (enquiries table → AI scoring → sales follow-up task).
/// Same auth as the other kiosk calls (RobotConfig.authToken); the robot never
/// holds XBoom credentials.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// What the visitor is asking for. `order` = wants to buy now (hot lead);
/// `enquiry` = wants information / a quote. Both land in XBoom's enquiries
/// pipeline — the kind sets the priority tagging on the spine side.
enum LeadKind { order, enquiry }

class LeadSubmitResult {
  const LeadSubmitResult({required this.ok, this.reference, this.reason});

  final bool ok;

  /// Human-readable reference from XBoom (e.g. an enquiry id) when available.
  final String? reference;
  final String? reason;
}

/// One kiosk-safe product row from XBoom's pricelist (via spine
/// GET /xboom/catalog). Prices are the PUBLIC website price only.
class CatalogProduct {
  const CatalogProduct({
    required this.name,
    this.sku,
    this.brand,
    this.category,
    this.description,
    this.price,
    this.currency,
    this.availability,
  });

  final String name;
  final String? sku; // woo_sku — sent as product_code on submit
  final String? brand;
  final String? category;
  final String? description;
  final double? price; // website_price
  final String? currency;
  final String? availability;

  static CatalogProduct? fromJson(Map<String, dynamic> j) {
    final name = (j['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    return CatalogProduct(
      name: name,
      sku: j['woo_sku'] as String?,
      brand: j['brand'] as String?,
      category: j['product_category'] as String?,
      description: j['description'] as String?,
      price: (j['website_price'] as num?)?.toDouble(),
      currency: j['currency'] as String? ?? 'INR',
      availability: j['availability'] as String?,
    );
  }
}

class CatalogPage {
  const CatalogPage({required this.products, required this.total});
  final List<CatalogProduct> products;
  final int total;
}

class XboomLeadApi {
  /// Search the product catalog (paged). Throws on transport/HTTP errors so
  /// the picker can show an honest "catalog unavailable" state and still let
  /// the visitor type the product by hand.
  Future<CatalogPage> fetchProducts({
    String search = '',
    int limit = 30,
    int offset = 0,
  }) async {
    final uri = Uri.parse('${RobotConfig.spineBaseUrl}/xboom/catalog').replace(
      queryParameters: {
        if (search.isNotEmpty) 'search': search,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final res = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${RobotConfig.authToken}'},
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('GET /xboom/catalog → ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final products = (body['products'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogProduct.fromJson)
        .whereType<CatalogProduct>()
        .toList();
    return CatalogPage(products: products, total: (body['total'] as num?)?.toInt() ?? products.length);
  }

  /// Submit a showroom lead. Never throws — the kiosk form needs a clean
  /// ok/failed answer to show the visitor, not a stack trace.
  Future<LeadSubmitResult> submit({
    required LeadKind kind,
    required String name,
    required String phone,
    required String product,
    String? productCode,
    String? email,
    int? quantity,
    String? notes,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('${RobotConfig.spineBaseUrl}/xboom/lead'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${RobotConfig.authToken}',
            },
            body: jsonEncode({
              'kind': kind.name,
              'name': name,
              'phone': phone,
              'product': product,
              if (productCode != null && productCode.isNotEmpty)
                'product_code': productCode,
              if (email != null && email.isNotEmpty) 'email': email,
              if (quantity != null) 'quantity': quantity,
              if (notes != null && notes.isNotEmpty) 'notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 12));
      final body = res.body.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['ok'] == true) {
        return LeadSubmitResult(
          ok: true,
          reference: body['reference'] as String?,
        );
      }
      return LeadSubmitResult(
        ok: false,
        reason: (body['reason'] as String?) ?? 'HTTP ${res.statusCode}',
      );
    } catch (e) {
      return LeadSubmitResult(ok: false, reason: e.toString());
    }
  }
}
