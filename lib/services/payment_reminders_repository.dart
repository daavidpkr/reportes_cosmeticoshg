import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/factura.dart';
import '../models/payment_reminder.dart';
import 'request_id.dart';

abstract interface class PaymentRemindersDataSource {
  Future<List<PaymentReminder>> list();
  Future<PaymentReminder?> findForInvoice(String facturaId);
  Future<void> save(
      {required String facturaId,
      required DateTime paymentDate,
      required bool active,
      required bool notifyThreeDays,
      required bool notifyOneDay});
  Future<void> delete(String id);
  Future<List<PaymentFollowup>> listFollowups(String reminderId);
  Future<FollowupResult> addFollowup({
    required String reminderId,
    required String requestId,
    String? comment,
    DateTime? requestedPaymentDate,
  });
  Future<List<Factura>> listInvoices();
  Future<Factura?> findInvoice(String facturaId);
}

class PaymentRemindersRepository implements PaymentRemindersDataSource {
  PaymentRemindersRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Future<List<PaymentReminder>> list() async => (await _client
          .from('payment_reminders')
          .select('*,facturas_maestras(cliente,nombre_comercial)')
          .order('payment_date'))
      .map<PaymentReminder>((row) => PaymentReminder.fromJson(row))
      .toList();

  @override
  Future<PaymentReminder?> findForInvoice(String facturaId) async {
    final row = await _client
        .from('payment_reminders')
        .select()
        .eq('factura_id', facturaId.trim())
        .maybeSingle();
    return row == null ? null : PaymentReminder.fromJson(row);
  }

  @override
  Future<void> save(
      {required String facturaId,
      required DateTime paymentDate,
      required bool active,
      required bool notifyThreeDays,
      required bool notifyOneDay}) async {
    if (_client.auth.currentUser == null) {
      throw const AuthException('Se requiere una sesión activa.');
    }
    await _client.rpc('enterprise_save_payment_reminder', params: {
      'p_request_id': newRequestId(),
      'p_factura_id': facturaId.trim(),
      'p_payment_date': _date(paymentDate),
      'p_active': active,
      'p_notify_three_days': notifyThreeDays,
      'p_notify_one_day': notifyOneDay,
    });
  }

  @override
  Future<void> delete(String id) =>
      _client.rpc('enterprise_deactivate_payment_reminder', params: {
        'p_request_id': newRequestId(),
        'p_reminder_id': id,
      });

  @override
  Future<List<PaymentFollowup>> listFollowups(String reminderId) async =>
      (await _client
              .from('payment_followups')
              .select()
              .eq('reminder_id', reminderId)
              .order('created_at', ascending: false)
              .order('id', ascending: false))
          .map<PaymentFollowup>((row) => PaymentFollowup.fromJson(row))
          .toList();

  @override
  Future<FollowupResult> addFollowup({
    required String reminderId,
    required String requestId,
    String? comment,
    DateTime? requestedPaymentDate,
  }) async {
    final rows = await _client.rpc('add_payment_followup', params: {
      'p_reminder_id': reminderId,
      'p_request_id': requestId,
      'p_comment': comment?.trim().isEmpty ?? true ? null : comment!.trim(),
      'p_requested_payment_date':
          requestedPaymentDate == null ? null : _date(requestedPaymentDate),
    });
    final row = (rows as List).single as Map<String, dynamic>;
    return FollowupResult(
        actionType: row['action_type'].toString(),
        effectivePaymentDate:
            DateTime.parse(row['effective_payment_date'].toString()));
  }

  @override
  Future<List<Factura>> listInvoices() async => (await _client
          .from('facturas_maestras')
          .select('ref_fact,cliente,nombre_comercial,fecha,venta')
          .order('ref_fact'))
      .map<Factura>(_invoice)
      .toList();

  @override
  Future<Factura?> findInvoice(String facturaId) async {
    final row = await _client
        .from('facturas_maestras')
        .select('ref_fact,cliente,nombre_comercial,fecha,venta')
        .eq('ref_fact', facturaId.trim())
        .maybeSingle();
    return row == null ? null : _invoice(row);
  }

  Factura _invoice(Map<String, dynamic> row) => Factura(
      cliente: row['cliente']?.toString() ?? '',
      nombreComercial: row['nombre_comercial']?.toString() ?? '',
      fecha: row['fecha']?.toString() ?? '',
      secuencial: row['ref_fact']?.toString() ?? '',
      total: (row['venta'] as num?)?.toDouble() ?? 0);
}
