import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/factura.dart';
import '../models/payment_reminder.dart';

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
  Future<List<PaymentReminder>> list() async =>
      (await _client.from('payment_reminders').select().order('payment_date'))
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
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Se requiere una sesión activa.');
    }
    await _client.from('payment_reminders').upsert({
      'user_id': user.id,
      'factura_id': facturaId.trim(),
      'payment_date': _date(paymentDate),
      'active': active,
      'notify_three_days': notifyThreeDays,
      'notify_one_day': notifyOneDay,
    }, onConflict: 'user_id,factura_id');
  }

  @override
  Future<void> delete(String id) =>
      _client.from('payment_reminders').delete().eq('id', id);

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
