import 'package:flutter/material.dart';

import '../../models/payment_calendar_entry.dart';
import '../../models/payment_calendar_rules.dart';
import '../../services/payment_calendar_repository.dart';
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
  const PaymentCalendarScreen({this.repository, this.initialMonth, super.key});
  final PaymentCalendarDataSource? repository;
  final DateTime? initialMonth;
  @override
  State<PaymentCalendarScreen> createState() => _PaymentCalendarScreenState();
}

class _PaymentCalendarScreenState extends State<PaymentCalendarScreen> {
  late final PaymentCalendarController controller = PaymentCalendarController(
      repository: widget.repository ?? PaymentCalendarRepository(),
      initialMonth: widget.initialMonth)
    ..addListener(_changed);
  @override
  void initState() {
    super.initState();
    controller.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  Future<void> _select(DateTime day) async {
    controller.select(day);
    final entries =
        controller.grouped[dateOnly(day)] ?? const <PaymentCalendarEntry>[];
    await showDayInvoicesDialog(context, day, entries, _edit);
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
        await showDayInvoicesDialog(context, edit.date, dayEntries, _edit);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Calendario de cobros')),
        body: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
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
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
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
                ]))),
      );
}
