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
  Future<void> deleteCustomer(BillingCustomer customer);
  Future<CustomerSchedulingResult> schedulePending(BillingCustomer customer);
}

class CustomerSchedulingResult {
  const CustomerSchedulingResult({
    required this.eligibleCount,
    required this.createdCount,
    required this.skippedExistingCount,
    required this.skippedCount,
  });

  final int eligibleCount;
  final int createdCount;
  final int skippedExistingCount;
  final int skippedCount;

  factory CustomerSchedulingResult.fromJson(Map<String, dynamic> json) =>
      CustomerSchedulingResult(
        eligibleCount: (json['eligible_count'] as num?)?.toInt() ?? 0,
        createdCount: (json['created_count'] as num?)?.toInt() ?? 0,
        skippedExistingCount:
            (json['skipped_existing_count'] as num?)?.toInt() ?? 0,
        skippedCount: (json['skipped_count'] as num?)?.toInt() ?? 0,
      );
}

class CustomerTermsRepository implements CustomerTermsDataSource {
  CustomerTermsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<List<BillingCustomer>> listCustomers() async => (await _client
          .from('billing_customers')
          .select('id,name,commercial_name,payment_term_days')
          .eq('configuration_active', true)
          .order('name'))
      .map<BillingCustomer>((row) => BillingCustomer.fromJson(row))
      .toList();

  Map<String, dynamic> _identity(BillingCustomer customer) => {
        'p_name': customer.name,
        'p_commercial_name': customer.commercialName,
      };

  @override
  Future<void> deleteCustomer(BillingCustomer customer) async {
    await _client.rpc('delete_enterprise_customer_configuration', params: {
      'p_request_id': newRequestId(),
      ..._identity(customer),
    });
  }

  @override
  Future<CustomerSchedulingResult> schedulePending(
      BillingCustomer customer) async {
    final value =
        await _client.rpc('schedule_enterprise_customer_pending', params: {
      'p_request_id': newRequestId(),
      ..._identity(customer),
    });
    return CustomerSchedulingResult.fromJson(
        Map<String, dynamic>.from(value as Map));
  }

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
