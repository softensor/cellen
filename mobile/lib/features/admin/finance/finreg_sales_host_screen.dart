import 'dart:typed_data';

import 'package:cellen/core/api/api_client.dart';
import 'package:finreg_client_sdk/finreg_client_sdk.dart';
import 'package:finreg_sales_ui/finreg_sales_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'invoices_screen.dart';

class FinregSalesHostScreen extends ConsumerWidget {
  const FinregSalesHostScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<dynamic>(
        future: ref.read(apiClientProvider).get('/finreg/connection'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final value = Map<String, dynamic>.from(snapshot.data as Map);
          if (!{'fake', 'pilot', 'live'}.contains(value['mode'])) {
            return const InvoicesScreen();
          }
          final adapter = _CellenFinregAdapter(ref.read(apiClientProvider));
          return FinregSalesWorkspace(repository: adapter, host: adapter);
        },
      );
}

class _CellenFinregAdapter implements FinregSalesRepository, FinregHostAdapter {
  _CellenFinregAdapter(this.api);
  final ApiClient api;
  InvoicePreview? lastPreview;

  @override
  Future<FinregCapabilities> capabilities() async {
    final value =
        Map<String, dynamic>.from(await api.get('/finreg/capabilities') as Map);
    return FinregCapabilities(
        apiVersion: value['api_version'] as String,
        schemaVersion: value['schema_version'] as String,
        vertical: value['vertical'] as String,
        terminology:
            Map<String, String>.from(value['terminology'] as Map? ?? {}),
        enabledModules:
            Set<String>.from(value['enabled_modules'] as List? ?? []),
        nonFiscal: value['non_fiscal'] as bool? ?? false);
  }

  @override
  Future<SchoolFinanceContext> currentSchool() async {
    final now = DateTime.now();
    return SchoolFinanceContext(
        schoolExternalId: 'current',
        billingPeriod: '${now.year}-${now.month.toString().padLeft(2, '0')}');
  }

  @override
  Future<List<ExternalReference>> searchGuardians(String query) async {
    final rows = await api.get('/guardians') as List;
    return rows
        .map((raw) {
          final v = Map<String, dynamic>.from(raw as Map);
          return ExternalReference(
              id: v['id'].toString(),
              displayName: '${v['first_name']} ${v['last_name']}');
        })
        .where((x) => x.displayName.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  Future<List<ExternalReference>> searchPupils(String query) async {
    final rows = await api.get('/children') as List;
    return rows
        .map((raw) {
          final v = Map<String, dynamic>.from(raw as Map);
          return ExternalReference(
              id: v['id'].toString(),
              displayName: '${v['first_name']} ${v['last_name']}');
        })
        .where((x) => x.displayName.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  Future<List<FinregProduct>> searchProducts(String query) async {
    final rows = await api.get('/finance/billing-items') as List;
    return rows
        .map((raw) {
          final v = Map<String, dynamic>.from(raw as Map);
          return FinregProduct(
              id: v['id'].toString(),
              code: v['code'].toString(),
              name: v['name'].toString(),
              unitPrice: v['unit_price'] as num,
              taxRate: v['iva_rate'] as num);
        })
        .where((x) =>
            '${x.code} ${x.name}'.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  Map<String, dynamic> _payload(InvoiceDraft draft) => {
        'request_id': draft.externalReference,
        'guardian_id': draft.customerId,
        'pupil_id': draft.context.pupilExternalId,
        'academic_year_id': draft.context.academicYearExternalId,
        'academic_year_label': draft.context.academicYearLabel,
        'billing_period': draft.context.billingPeriod,
        'lines': draft.lines
            .map((x) => {
                  'billing_item_id': x.productId,
                  'quantity': x.quantity,
                  'unit_price': x.unitPrice,
                  'discount_pct': 0
                })
            .toList(),
      };

  @override
  Future<InvoicePreview> previewInvoice(InvoiceDraft draft) async {
    final v = Map<String, dynamic>.from(
        await api.post('/finreg/sales/preview', data: _payload(draft)) as Map);
    return lastPreview = InvoicePreview(
        netTotal: v['net_total'] as num,
        taxTotal: v['tax_total'] as num,
        grossTotal: v['gross_total'] as num);
  }

  @override
  Future<FiscalDocument> issueInvoice(InvoiceDraft draft,
      {required String idempotencyKey}) async {
    final v = Map<String, dynamic>.from(
        await api.post('/finreg/sales/issue', data: _payload(draft)) as Map);
    return FiscalDocument(
        id: (v['finreg_document_id'] ?? v['id']).toString(),
        status: v['status'].toString(),
        grossTotal: lastPreview?.grossTotal ?? 0);
  }

  @override
  Future<void> recordMapping(
      String entityType, String externalId, String finregId) async {}
  @override
  Future<Uint8List> downloadOfficialDocument(String documentId) =>
      throw const FinregException('not_available', 'Use document detail');
  @override
  Future<PaymentResult> registerPayment(RegisterPayment command,
          {required String idempotencyKey}) =>
      throw const FinregException('not_available', 'Use payments workspace');
}
