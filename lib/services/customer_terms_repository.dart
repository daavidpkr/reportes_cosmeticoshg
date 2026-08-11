import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/billing_customer.dart';
import 'request_id.dart';

abstract interface class CustomerTermsDataSource {
  Future<List<BillingCustomer>> listCustomers();
  Future<int> previewImpact(String customerId, int days);
  Future<int> savePaymentTerm(String customerId, int days,
      {required bool applyExisting});
  Future<InvoicePaymentPlan?> getInvoicePlan(String facturaId);
  Future<DateTime?> saveInvoiceException(String facturaId, int? days,
      {required bool confirmManualOverride});
}

class CustomerTermsRepository implements CustomerTermsDataSource {
  CustomerTermsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<List<BillingCustomer>> listCustomers() async => (await _client
          .from('billing_customers')
          .select('id,name,commercial_name,payment_term_days')
          .order('name'))
      .map<BillingCustomer>((row) => BillingCustomer.fromJson(row))
      .toList();

  @override
  Future<int> previewImpact(String customerId, int days) async =>
      (await _client.rpc('preview_enterprise_customer_term', params: {
        'p_customer_id': customerId,
        'p_days': days,
      }) as num)
          .toInt();

  @override
  Future<int> savePaymentTerm(String customerId, int days,
          {required bool applyExisting}) async =>
      (await _client.rpc('save_enterprise_customer_term', params: {
        'p_request_id': newRequestId(),
        'p_customer_id': customerId,
        'p_days': days,
        'p_apply': applyExisting,
      }) as num)
          .toInt();

  @override
  Future<InvoicePaymentPlan?> getInvoicePlan(String facturaId) async {
    final results = await Future.wait([
      _client
          .from('invoice_payment_terms')
          .select(
              'exceptional_term_days,billing_customers(payment_term_days),facturas_maestras(fecha)')
          .eq('factura_id', facturaId)
          .maybeSingle(),
      _client
          .from('payment_reminders')
          .select('payment_date,date_source')
          .eq('factura_id', facturaId)
          .maybeSingle(),
    ]);
    final terms = results[0];
    if (terms == null) return null;
    final customer = terms['billing_customers'] as Map<String, dynamic>?;
    final invoice = terms['facturas_maestras'] as Map<String, dynamic>?;
    final reminder = results[1];
    return InvoicePaymentPlan(
      invoiceDate: invoice?['fecha'] == null
          ? null
          : DateTime.parse(invoice!['fecha'].toString()),
      customerTermDays: (customer?['payment_term_days'] as num?)?.toInt(),
      exceptionalTermDays: (terms['exceptional_term_days'] as num?)?.toInt(),
      currentPaymentDate: reminder?['payment_date'] == null
          ? null
          : DateTime.parse(reminder!['payment_date'].toString()),
      manualSchedule: reminder?['date_source'] == 'manual',
    );
  }

  @override
  Future<DateTime?> saveInvoiceException(String facturaId, int? days,
      {required bool confirmManualOverride}) async {
    final value =
        await _client.rpc('save_enterprise_invoice_exception', params: {
      'p_request_id': newRequestId(),
      'p_factura_id': facturaId,
      'p_exceptional_days': days,
      'p_confirm_manual_override': confirmManualOverride,
    });
    return value == null ? null : DateTime.parse(value.toString());
  }
}
