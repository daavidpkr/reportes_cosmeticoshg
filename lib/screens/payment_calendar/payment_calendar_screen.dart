import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../models/billing_customer.dart';
import '../../models/payment_calendar_entry.dart';
import '../../models/payment_calendar_rules.dart';
import '../../services/customer_terms_repository.dart';
import '../../services/customer_history_repository.dart';
import '../../services/payment_calendar_repository.dart';
import '../../services/payment_calendar_refresh.dart';
import '../customer_history_screen.dart';
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
      {this.repository,
      this.historyRepository,
      this.customerTermsRepository,
      this.initialMonth,
      this.initialDate,
      super.key});
  final PaymentCalendarDataSource? repository;
  final CustomerHistoryDataSource? historyRepository;
  final CustomerTermsDataSource? customerTermsRepository;
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
          historyRepository: widget.historyRepository,
          customerTermsRepository: widget.customerTermsRepository,
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
      this.historyRepository,
      this.customerTermsRepository,
      super.key});
  final PaymentCalendarDataSource? repository;
  final DateTime? initialMonth;
  final DateTime? initialDate;
  final Future<void> Function()? onPaymentPersisted;
  final CustomerHistoryDataSource? historyRepository;
  final CustomerTermsDataSource? customerTermsRepository;
  @override
  State<PaymentCalendarView> createState() => _PaymentCalendarViewState();
}

class _PaymentCalendarViewState extends State<PaymentCalendarView> {
  static const double _minScale = .75;
  static const double _maxScale = 2;
  final TransformationController _transformation = TransformationController();
  bool _transforming = false;
  late final CustomerTermsDataSource _customerTerms =
      widget.customerTermsRepository ?? CustomerTermsRepository();
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
    _transformation.dispose();
    super.dispose();
  }

  double get _scale => _transformation.value.getMaxScaleOnAxis();

  void _setScale(double value) {
    final next = value.clamp(_minScale, _maxScale).toDouble();
    _transformation.value = Matrix4.diagonal3Values(next, next, 1);
    setState(() {});
  }

  void _fitGrid() {
    _transformation.value = Matrix4.identity();
    setState(() {});
  }

  void _moveMonth(int offset) {
    _fitGrid();
    controller.moveMonth(offset);
  }

  Widget _zoomControls() => Semantics(
        label: 'Controles de zoom del calendario',
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton.outlined(
            key: const ValueKey('calendar-zoom-out'),
            tooltip: 'Reducir zoom',
            onPressed:
                _scale <= _minScale ? null : () => _setScale(_scale - .25),
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 48,
            child:
                Text('${(_scale * 100).round()}%', textAlign: TextAlign.center),
          ),
          IconButton.outlined(
            key: const ValueKey('calendar-zoom-in'),
            tooltip: 'Aumentar zoom',
            onPressed:
                _scale >= _maxScale ? null : () => _setScale(_scale + .25),
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: const ValueKey('calendar-zoom-fit'),
            onPressed: _fitGrid,
            child: const Text('Ajustar'),
          ),
        ]),
      );

  Widget _calendarGrid(bool mobile) {
    final grid = CalendarGrid(
      month: controller.visibleMonth,
      grouped: controller.grouped,
      selected: controller.selectedDay,
      onSelect: _transforming ? (_) {} : _select,
      showEntryText: kIsWeb || defaultTargetPlatform != TargetPlatform.android,
    );
    if (!mobile) return grid;
    return InteractiveViewer(
      key: const ValueKey('payment-calendar-zoom'),
      transformationController: _transformation,
      minScale: _minScale,
      maxScale: _maxScale,
      panEnabled: _scale > 1,
      boundaryMargin: const EdgeInsets.all(80),
      onInteractionStart: (_) => setState(() => _transforming = true),
      onInteractionUpdate: (_) => setState(() {}),
      onInteractionEnd: (_) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (mounted) setState(() => _transforming = false);
        });
      },
      child: grid,
    );
  }

  Future<void> _select(DateTime day) async {
    controller.select(day);
    final entries =
        controller.grouped[dateOnly(day)] ?? const <PaymentCalendarEntry>[];
    await showDayInvoicesDialog(context, day, entries, _edit, _payment, _paid,
        (entry) => _history(entry, day));
  }

  Future<void> _history(PaymentCalendarEntry entry, DateTime day) async {
    BillingCustomer? customer;
    try {
      final source = controller.repository;
      if (source is CalendarCustomerDataSource) {
        customer = await (source as CalendarCustomerDataSource)
            .resolveCustomer(entry.facturaId);
      }
    } catch (_) {
      customer = null;
    }
    if (!mounted) return;
    if (customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo identificar al cliente de esta factura.')));
      return;
    }
    await showDialog<void>(
        context: context,
        builder: (_) => CustomerHistoryScreen(
            customer: customer!,
            repository: widget.historyRepository,
            onEditTerm: _editCustomerTerm,
            onSchedule: _scheduleCustomer,
            onDelete: _deleteCustomer));
    if (!mounted) return;
    await controller.load(refresh: true);
    try {
      await widget.onPaymentPersisted?.call();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
    final refreshed =
        controller.grouped[dateOnly(day)] ?? const <PaymentCalendarEntry>[];
    await showDayInvoicesDialog(context, day, refreshed, _edit, _payment, _paid,
        (item) => _history(item, day));
  }

  Future<int?> _editCustomerTerm(BillingCustomer customer) async {
    final input =
        TextEditingController(text: customer.paymentTermDays?.toString() ?? '');
    final days = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Plazo habitual de pago'),
              content: TextField(
                  controller: input,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Días')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(
                        dialogContext, int.tryParse(input.text.trim())),
                    child: const Text('Guardar'))
              ],
            ));
    input.dispose();
    if (days == null || days < 0) return null;
    final impacted = await _customerTerms.previewImpact(customer.id, days);
    if (!mounted) return null;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Confirmar plazo'),
              content: Text(impacted == 0
                  ? 'Se guardará el plazo habitual del cliente.'
                  : 'Se actualizarán $impacted facturas existentes con el nuevo plazo.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Confirmar'))
              ],
            ));
    if (confirmed != true) return null;
    await _customerTerms.savePaymentTerm(customer.id, days,
        applyExisting: true);
    paymentCalendarRefresh.refresh();
    return days;
  }

  Future<void> _scheduleCustomer(BillingCustomer customer) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Programar facturas pendientes'),
              content: Text(
                  'Se programarán las facturas elegibles de ${customer.name} sin modificar recordatorios existentes.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Programar'))
              ],
            ));
    if (confirmed != true) return;
    await _customerTerms.schedulePending(customer);
    paymentCalendarRefresh.refresh();
  }

  Future<bool> _deleteCustomer(BillingCustomer customer) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Eliminar cliente'),
              content: const Text(
                  'Se quitará al cliente del apartado Clientes. Sus facturas, abonos y recordatorios se conservarán.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Eliminar cliente'))
              ],
            ));
    if (confirmed != true) return false;
    await _customerTerms.deleteCustomer(customer);
    paymentCalendarRefresh.refresh();
    return true;
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
        await showDayInvoicesDialog(context, edit.date, dayEntries, _edit,
            _payment, _paid, (entry) => _history(entry, edit.date));
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
          child: LayoutBuilder(builder: (context, constraints) {
            final mobile = constraints.maxWidth < 700;
            return Column(children: [
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
                  onPrevious: () => _moveMonth(-1),
                  onNext: () => _moveMonth(1),
                  onToday: () {
                    _fitGrid();
                    controller.today();
                  },
                  onRefresh: () => controller.load(refresh: true)),
              if (mobile) _zoomControls(),
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
                              _calendarGrid(mobile),
                              if (controller.entries.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                        'No hay facturas pendientes programadas para este mes.'))
                            ]))),
            ]);
          })));
}
