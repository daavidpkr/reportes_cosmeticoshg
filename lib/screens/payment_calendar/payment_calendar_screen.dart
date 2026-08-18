import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/payment_calendar_entry.dart';
import '../../models/payment_calendar_rules.dart';
import '../../services/payment_calendar_repository.dart';
import '../../services/payment_calendar_refresh.dart';
import 'dialogs/day_invoices_dialog.dart';
import 'dialogs/reschedule_reminder_dialog.dart';
import 'payment_calendar_controller.dart';
import 'widgets/calendar_grid.dart';
import 'widgets/calendar_header.dart';

const _monthNames = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre'
];

class PaymentCalendarScreen extends StatefulWidget {
  const PaymentCalendarScreen(
      {this.repository, this.initialMonth, this.initialDate, super.key});
  final PaymentCalendarDataSource? repository;
  final DateTime? initialMonth;
  final DateTime? initialDate;
  @override
  State<PaymentCalendarScreen> createState() => _PaymentCalendarScreenState();
}

class _PaymentCalendarScreenState extends State<PaymentCalendarScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Calendario de cobros')),
        body: PaymentCalendarView(
          repository: widget.repository,
          initialMonth: widget.initialMonth,
          initialDate: widget.initialDate,
        ),
      );
}

class PaymentCalendarView extends StatefulWidget {
  const PaymentCalendarView(
      {this.repository,
      this.initialMonth,
      this.initialDate,
      this.onPaymentPersisted,
      super.key});
  final PaymentCalendarDataSource? repository;
  final DateTime? initialMonth;
  final DateTime? initialDate;
  final Future<void> Function()? onPaymentPersisted;
  @override
  State<PaymentCalendarView> createState() => _PaymentCalendarViewState();
}

class _PaymentCalendarViewState extends State<PaymentCalendarView> {
  late final PaymentCalendarController controller = PaymentCalendarController(
      repository: widget.repository ?? PaymentCalendarRepository(),
      initialMonth: widget.initialMonth,
      initialDate: widget.initialDate)
    ..addListener(_changed);
  @override
  void initState() {
    super.initState();
    paymentCalendarRefresh.addListener(_externalRefresh);
    controller.load();
  }

  void _externalRefresh() => controller.load(refresh: true);

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    paymentCalendarRefresh.removeListener(_externalRefresh);
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  Future<void> _select(DateTime day) async {
    controller.select(day);
    final entries =
        controller.grouped[dateOnly(day)] ?? const <PaymentCalendarEntry>[];
    await showDayInvoicesDialog(context, day, entries, _edit, _payment, _paid);
  }

  Future<void> _edit(PaymentCalendarEntry entry) async {
    final edit = await showRescheduleReminderDialog(context, entry);
    if (edit == null || !mounted) return;
    final saved = await controller.update(entry, edit.date, edit.comment);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(saved
            ? 'Recordatorio actualizado.'
            : 'No fue posible actualizar el recordatorio. No se guardaron los cambios.')));
    if (saved) {
      final dayEntries = controller.grouped[dateOnly(edit.date)] ??
          const <PaymentCalendarEntry>[];
      if (edit.date.year == controller.visibleMonth.year &&
          edit.date.month == controller.visibleMonth.month) {
        await showDayInvoicesDialog(
            context, edit.date, dayEntries, _edit, _payment, _paid);
      }
    }
  }

  Future<void> _payment(PaymentCalendarEntry entry) async {
    final amount = TextEditingController();
    final comment = TextEditingController();
    final receipt = TextEditingController();
    final result = await showDialog<(double, String, int?)>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Registrar abono'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        'Factura ${entry.invoiceNumber.isEmpty ? entry.facturaId : entry.invoiceNumber}'),
                    subtitle: Text(
                        '${entry.cliente}\nSaldo actual: \$${entry.balance.toStringAsFixed(2)}')),
                TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Valor del abono')),
                const SizedBox(height: 10),
                TextField(
                    controller: comment,
                    decoration: const InputDecoration(
                        labelText: 'Comentario opcional')),
                const SizedBox(height: 10),
                TextField(
                    controller: receipt,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Recibo opcional')),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () {
                      final value =
                          double.tryParse(amount.text.replaceAll(',', '.'));
                      final receiptValue = receipt.text.trim().isEmpty
                          ? null
                          : int.tryParse(receipt.text.trim());
                      if (value == null ||
                          value <= 0 ||
                          value > entry.balance + .005 ||
                          (receipt.text.trim().isNotEmpty &&
                              receiptValue == null)) {
                        return;
                      }
                      Navigator.pop(
                          context, (value, comment.text, receiptValue));
                    },
                    child: const Text('Guardar')),
              ],
            ));
    unawaited(Future<void>.delayed(kThemeAnimationDuration, () {
      amount.dispose();
      comment.dispose();
      receipt.dispose();
    }));
    if (result == null || !mounted) return;
    await _savePayment(entry, result.$1,
        comment: result.$2, receipt: result.$3);
  }

  Future<void> _paid(PaymentCalendarEntry entry) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Marcar factura como pagada'),
              content: Text(
                  'Factura: ${entry.invoiceNumber.isEmpty ? entry.facturaId : entry.invoiceNumber}\nCliente: ${entry.cliente}\nSaldo pendiente: \$${entry.balance.toStringAsFixed(2)}\n\nSe registrará un abono final por el saldo pendiente.\nLa factura no será anulada ni eliminada.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Marcar como pagada'))
              ],
            ));
    if (confirmed == true && mounted) {
      final saved = await controller.payInFull(entry);
      if (!mounted) return;
      var refreshed = saved;
      if (saved) {
        try {
          await widget.onPaymentPersisted?.call();
        } catch (_) {
          refreshed = false;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saved && refreshed
              ? 'Factura marcada como pagada.'
              : saved
                  ? 'El pago se guardó, pero no se pudieron actualizar los reportes. Usa Actualizar datos.'
                  : 'No fue posible completar el pago. Actualiza e inténtalo nuevamente.')));
    }
  }

  Future<void> _savePayment(PaymentCalendarEntry entry, double amount,
      {String comment = '', int? receipt}) async {
    final saved = await controller.recordPayment(entry, amount,
        comment: comment, receiptNumber: receipt);
    if (!mounted) return;
    var refreshed = saved;
    if (saved) {
      try {
        await widget.onPaymentPersisted?.call();
      } catch (_) {
        refreshed = false;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(saved && refreshed
            ? 'Abono registrado correctamente.'
            : saved
                ? 'El abono se guardó, pero no se pudieron actualizar los reportes. Usa Actualizar datos.'
                : 'No fue posible registrar el abono. El saldo pudo cambiar; actualiza e inténtalo nuevamente.')));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Calendario de cobros',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const Text(
                      'Consulta y reprogramación de facturas pendientes'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CalendarHeader(
                monthLabel:
                    '${_monthNames[controller.visibleMonth.month - 1]} ${controller.visibleMonth.year}',
                onPrevious: () => controller.moveMonth(-1),
                onNext: () => controller.moveMonth(1),
                onToday: controller.today,
                onRefresh: () => controller.load(refresh: true)),
            const SizedBox(height: 8),
            Expanded(
                child: controller.loading
                    ? const Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Cargando facturas pendientes…')
                      ]))
                    : controller.error != null
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                Text(controller.error!,
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                    onPressed: () =>
                                        controller.load(refresh: true),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Reintentar'))
                              ]))
                        : SingleChildScrollView(
                            child: Column(children: [
                            CalendarGrid(
                                month: controller.visibleMonth,
                                grouped: controller.grouped,
                                selected: controller.selectedDay,
                                onSelect: _select),
                            if (controller.entries.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                      'No hay facturas pendientes programadas para este mes.'))
                          ]))),
          ])));
}
