import 'package:flutter/material.dart';

import '../models/fila_venta.dart';
import '../services/supabase_reportes_service.dart';
import '../theme/hg_theme.dart';
import 'reporte/report_invoice_table.dart';

typedef InvoiceDetailLoader = Future<InvoiceDetailSnapshot?> Function(
  String canonicalReference,
);

enum _InvoiceDetailActionType {
  payment,
  editPayment,
  payInFull,
  reschedule,
  viewCustomer,
}

class _InvoiceDetailAction {
  const _InvoiceDetailAction(this.type, [this.paymentIndex]);
  final _InvoiceDetailActionType type;
  final int? paymentIndex;
}

Future<void> showInvoiceDetailDialog(
  BuildContext context, {
  required FilaVenta invoice,
  DateTime? scheduledDate,
  String? reportMonth,
  InvoiceDetailLoader? loadDetail,
  Future<void> Function()? onPayment,
  Future<void> Function(int index)? onEditPayment,
  Future<void> Function()? onPayInFull,
  Future<void> Function()? onReschedule,
  Future<bool> Function()? onViewCustomerProfile,
  Future<void> Function()? onClosed,
}) async {
  final fallback = InvoiceDetailSnapshot(
    invoice: invoice,
    reportMonth: reportMonth ?? '',
    overdue: scheduledDate != null &&
        scheduledDate.isBefore(
          DateTime(
              DateTime.now().year, DateTime.now().month, DateTime.now().day),
        ) &&
        !invoice.pagada &&
        !invoice.anulada,
    scheduledDate: scheduledDate,
    nextCollectionDate:
        !invoice.pagada && !invoice.anulada ? scheduledDate : null,
  );
  final loader = loadDetail ??
      (String reference) =>
          SupabaseReportesService().obtenerDetalleFactura(reference);
  final action = await showDialog<_InvoiceDetailAction>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .68),
    builder: (_) => _InvoiceDetailDialog(
      canonicalReference: invoice.referencia.trim(),
      fallback: fallback,
      loader: loader,
      canAddPayment: onPayment != null,
      canEditPayment: onEditPayment != null,
      canPayInFull: onPayInFull != null,
      canReschedule: onReschedule != null,
      canViewCustomer: onViewCustomerProfile != null,
    ),
  );
  switch (action?.type) {
    case _InvoiceDetailActionType.payment:
      await onPayment?.call();
    case _InvoiceDetailActionType.editPayment:
      if (action?.paymentIndex != null) {
        await onEditPayment?.call(action!.paymentIndex!);
      }
    case _InvoiceDetailActionType.payInFull:
      await onPayInFull?.call();
    case _InvoiceDetailActionType.reschedule:
      await onReschedule?.call();
    case _InvoiceDetailActionType.viewCustomer:
      final opened = await onViewCustomerProfile?.call();
      if (opened == false && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo identificar al cliente de esta factura.',
            ),
          ),
        );
      }
    case null:
      break;
  }
  await onClosed?.call();
}

class _InvoiceDetailDialog extends StatefulWidget {
  const _InvoiceDetailDialog({
    required this.canonicalReference,
    required this.fallback,
    required this.loader,
    required this.canAddPayment,
    required this.canEditPayment,
    required this.canPayInFull,
    required this.canReschedule,
    required this.canViewCustomer,
  });

  final String canonicalReference;
  final InvoiceDetailSnapshot fallback;
  final InvoiceDetailLoader loader;
  final bool canAddPayment;
  final bool canEditPayment;
  final bool canPayInFull;
  final bool canReschedule;
  final bool canViewCustomer;

  @override
  State<_InvoiceDetailDialog> createState() => _InvoiceDetailDialogState();
}

class _InvoiceDetailDialogState extends State<_InvoiceDetailDialog> {
  late InvoiceDetailSnapshot _detail = widget.fallback;
  bool _loading = true;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = await widget.loader(widget.canonicalReference);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        if (loaded == null) {
          _error = 'No se encontró esta factura en la organización actual.';
        } else {
          _detail = loaded;
        }
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error =
          'No se pudo actualizar el detalle. Se muestra la última información disponible.');
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _finish(_InvoiceDetailActionType type, [int? index]) {
    Navigator.pop(context, _InvoiceDetailAction(type, index));
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _longDate(DateTime value) {
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${value.day} de ${months[value.month - 1]} de ${value.year}';
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  String get _status {
    final invoice = _detail.invoice;
    if (invoice.anulada) return 'Anulada';
    if (invoice.pagada) return 'Pagada';
    if (_detail.overdue) return 'Vencida';
    if (invoice.abonoParcial) return 'Abonada';
    return 'Pendiente';
  }

  ReportInvoiceRowStatus get _rowStatus {
    final invoice = _detail.invoice;
    if (invoice.anulada) return ReportInvoiceRowStatus.cancelled;
    if (invoice.pagada) return ReportInvoiceRowStatus.paid;
    if (invoice.abonoParcial || _detail.overdue) {
      return ReportInvoiceRowStatus.partialPayment;
    }
    return ReportInvoiceRowStatus.normal;
  }

  String get _scheduleStatus {
    if (_detail.scheduledDate == null) return 'Sin programación';
    return switch (_detail.scheduleSource) {
      'manual' => 'Manual',
      'customer_term' => 'Según plazo del cliente',
      _ => 'Activa',
    };
  }

  bool get _canChangeInvoice {
    final invoice = _detail.invoice;
    return !invoice.anulada && !invoice.pagada;
  }

  String get _initials {
    final source = _detail.invoice.nombreComercial.trim().isNotEmpty
        ? _detail.invoice.nombreComercial
        : _detail.invoice.cliente;
    final words = source.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '—';
    return words.take(2).map((word) => word[0]).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, viewport) {
      final compact = viewport.maxWidth <= 760;
      final veryCompact = viewport.maxWidth <= 410;
      final horizontalInset = compact ? 10.0 : 22.0;
      return Dialog(
        insetPadding:
            EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 10),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(compact ? 20 : 25),
        ),
        child: ConstrainedBox(
          key: const ValueKey('invoice-detail-modal'),
          constraints: BoxConstraints(
            maxWidth: 1040,
            maxHeight: viewport.maxHeight - 20,
          ),
          child: Column(children: [
            _header(compact),
            if (_loading) const LinearProgressIndicator(minHeight: 3),
            if (_error != null) _errorBanner(),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('invoice-detail-scroll'),
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 24,
                  compact ? 14 : 20,
                  compact ? 14 : 24,
                  compact ? 14 : 26,
                ),
                child: _content(compact, veryCompact),
              ),
            ),
            _footer(compact),
          ]),
        ),
      );
    });
  }

  Widget _header(bool compact) {
    final theme = Theme.of(context);
    final invoice = _detail.invoice;
    final statusColor = _statusColor(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
          compact ? 16 : 24, compact ? 16 : 22, 10, compact ? 16 : 19),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface,
          context.hg.input,
        ]),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: compact ? 44 : 52,
          height: compact ? 44 : 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFB3265A), Color(0xFF5D194E)],
            ),
            borderRadius: BorderRadius.circular(compact ? 13 : 16),
          ),
          child: const Icon(Icons.receipt_long_outlined, color: Colors.white),
        ),
        SizedBox(width: compact ? 11 : 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Detalle de factura',
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.hg.mutedText,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Factura ${invoice.numeroFactura.trim().isEmpty ? '—' : invoice.numeroFactura}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (compact
                      ? theme.textTheme.titleLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  Container(
                    key: const ValueKey('invoice-status-pill'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: reportInvoiceRowBackground(context, _rowStatus),
                      border: Border.all(color: statusColor),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle, size: 9, color: statusColor),
                      const SizedBox(width: 7),
                      Text(_status,
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                    ]),
                  ),
                  Text('REF. ${visibleTableReference(invoice.referencia)}',
                      style:
                          TextStyle(color: context.hg.mutedText, fontSize: 13)),
                  if (!compact && _detail.reportMonth.isNotEmpty)
                    Text(_detail.reportMonth,
                        style: TextStyle(
                            color: context.hg.mutedText, fontSize: 13)),
                ]),
          ]),
        ),
        IconButton(
          key: const ValueKey('close-invoice-detail'),
          tooltip: 'Cerrar',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
          style: IconButton.styleFrom(
            minimumSize: const Size(45, 45),
            backgroundColor: context.hg.input,
            side: BorderSide(color: theme.dividerColor),
          ),
        ),
      ]),
    );
  }

  Color _statusColor(BuildContext context) {
    if (_rowStatus == ReportInvoiceRowStatus.normal) {
      return context.hg.mutedText;
    }
    return reportInvoiceRowBorder(context, _rowStatus);
  }

  Widget _errorBanner() => MaterialBanner(
        content: Text(_error!),
        actions: [
          TextButton(
              onPressed: _loading ? null : _load,
              child: const Text('Reintentar'))
        ],
      );

  Widget _content(bool compact, bool veryCompact) {
    final left = Column(children: [
      _clientPanel(),
      const SizedBox(height: 17),
      _totalsPanel(veryCompact),
      const SizedBox(height: 17),
      _paymentsPanel(),
    ]);
    final right = Column(children: [
      _informationPanel(veryCompact),
      const SizedBox(height: 17),
      _schedulePanel(),
      const SizedBox(height: 17),
      _actionsPanel(),
      const SizedBox(height: 12),
      _informationNote(),
    ]);
    if (compact) {
      return Column(children: [left, const SizedBox(height: 13), right]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 135, child: left),
      const SizedBox(width: 17),
      Expanded(flex: 65, child: right),
    ]);
  }

  Widget _panel(
      {required IconData icon,
      required String title,
      Widget? trailing,
      required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.hg.input,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20),
          const SizedBox(width: 9),
          Expanded(
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800))),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 15),
        child,
      ]),
    );
  }

  Widget _clientPanel() {
    final invoice = _detail.invoice;
    final subtitle = [
      if (invoice.nombreComercial.trim().isNotEmpty)
        invoice.nombreComercial.trim(),
      invoice.paymentTermDays == null
          ? 'Sin plazo configurado'
          : 'Plazo configurado: ${invoice.paymentTermDays} días',
    ].join(' · ');
    return _panel(
      icon: Icons.person_outline,
      title: 'Cliente',
      child: LayoutBuilder(builder: (context, constraints) {
        final stackButton = constraints.maxWidth < 460;
        final identity = Row(children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.hg.burgundy.withValues(alpha: .18),
              border:
                  Border.all(color: context.hg.burgundy.withValues(alpha: .55)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(_initials,
                style: TextStyle(
                    color: context.hg.burgundy, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 13),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    invoice.cliente.trim().isEmpty
                        ? 'Cliente no disponible'
                        : invoice.cliente,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style:
                        TextStyle(color: context.hg.mutedText, fontSize: 13)),
              ])),
        ]);
        final button = OutlinedButton(
          key: const ValueKey('view-customer-profile'),
          onPressed: widget.canViewCustomer
              ? () => _finish(_InvoiceDetailActionType.viewCustomer)
              : null,
          child: const Text('Ver perfil'),
        );
        if (stackButton) {
          return Column(children: [
            identity,
            const SizedBox(height: 13),
            SizedBox(width: double.infinity, child: button)
          ]);
        }
        return Row(children: [
          Expanded(child: identity),
          const SizedBox(width: 12),
          button
        ]);
      }),
    );
  }

  Widget _totalsPanel(bool veryCompact) {
    final invoice = _detail.invoice;
    final cards = [
      _TotalData('Total de venta', _money(invoice.venta), false),
      _TotalData('Total abonado', _money(invoice.totalAbonos), false),
      _TotalData('Saldo pendiente', _money(invoice.saldo), true),
    ];
    return _panel(
      icon: Icons.attach_money,
      title: 'Resumen de valores',
      child: LayoutBuilder(builder: (context, constraints) {
        final twoRows = veryCompact || constraints.maxWidth < 390;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards.map((data) {
            final width = twoRows
                ? (data.balance
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 10) / 2)
                : (constraints.maxWidth - 20) / 3;
            return SizedBox(width: width, child: _totalCard(data));
          }).toList(),
        );
      }),
    );
  }

  Widget _totalCard(_TotalData data) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 16),
        decoration: BoxDecoration(
          color: data.balance
              ? context.hg.warningContainer
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
              color: data.balance
                  ? context.hg.warning
                  : Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(data.label.toUpperCase(),
              style: TextStyle(
                  color: context.hg.mutedText,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(data.value,
                  style: const TextStyle(
                      fontSize: 23, fontWeight: FontWeight.w800))),
        ]),
      );

  Widget _paymentsPanel() {
    final invoice = _detail.invoice;
    final payments = invoice.abonos.indexed
        .where((entry) =>
            entry.$2.valor != 0 ||
            entry.$2.numeroRecibo != null ||
            entry.$2.comentario.trim().isNotEmpty)
        .toList(growable: false);
    return _panel(
      icon: Icons.view_list_outlined,
      title: 'Historial de abonos',
      trailing: Text(
          '${payments.length} ${payments.length == 1 ? 'registrado' : 'registrados'}',
          style: TextStyle(color: context.hg.mutedText, fontSize: 12)),
      child: Column(children: [
        if (payments.isEmpty)
          Container(
            key: const ValueKey('empty-payments'),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(14)),
            child:
                const Text('No existen abonos registrados para esta factura.'),
          )
        else
          for (final entry in payments) ...[
            _paymentCard(entry.$1, entry.$2),
            if (entry != payments.last) const SizedBox(height: 10),
          ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('add-payment-history'),
            onPressed: _canChangeInvoice && widget.canAddPayment
                ? () => _finish(_InvoiceDetailActionType.payment)
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Añadir abono'),
          ),
        ),
      ]),
    );
  }

  Widget _paymentCard(int index, Abono payment) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: context.hg.burgundy.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(10)),
            child: Text('${index + 1}',
                style: TextStyle(
                    color: context.hg.burgundy, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 11),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Abono registrado',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                    '${payment.fecha == null ? 'Fecha no disponible' : _date(payment.fecha!)} · ${payment.numeroRecibo == null ? 'Sin recibo' : 'Recibo ${payment.numeroRecibo}'}',
                    style:
                        TextStyle(color: context.hg.mutedText, fontSize: 12)),
                Text(
                    payment.comentario.trim().isEmpty
                        ? 'Sin comentario'
                        : payment.comentario.trim(),
                    style:
                        TextStyle(color: context.hg.mutedText, fontSize: 12)),
                const SizedBox(height: 4),
                Text(_money(payment.valor),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ])),
          IconButton(
            key: ValueKey('edit-payment-$index'),
            tooltip: 'Editar o eliminar abono ${index + 1}',
            onPressed: !_detail.invoice.anulada && widget.canEditPayment
                ? () => _finish(_InvoiceDetailActionType.editPayment, index)
                : null,
            icon: const Icon(Icons.edit_outlined),
            style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                side: BorderSide(color: Theme.of(context).dividerColor)),
          ),
        ]),
      );

  Widget _informationPanel(bool veryCompact) {
    final invoice = _detail.invoice;
    final fields = [
      ('Fecha de emisión', invoice.fecha),
      (
        'Fecha programada',
        _detail.scheduledDate == null
            ? 'Sin programación'
            : _date(_detail.scheduledDate!)
      ),
      (
        'Próximo cobro',
        _detail.nextCollectionDate == null
            ? 'Sin próximo cobro'
            : _date(_detail.nextCollectionDate!)
      ),
      (
        'Plazo',
        invoice.paymentTermDays == null
            ? 'Sin configurar'
            : '${invoice.paymentTermDays} días'
      ),
      ('Vendedor', invoice.vendedor),
      ('Programación', _scheduleStatus),
    ];
    return _panel(
      icon: Icons.info_outline,
      title: 'Información',
      child: LayoutBuilder(builder: (context, constraints) {
        final oneColumn = veryCompact || constraints.maxWidth < 290;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: fields
              .map((field) => SizedBox(
                    width: oneColumn
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 10) / 2,
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(13)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(field.$1.toUpperCase(),
                                style: TextStyle(
                                    color: context.hg.mutedText,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .4)),
                            const SizedBox(height: 5),
                            Text(field.$2.trim().isEmpty ? '—' : field.$2,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700)),
                          ]),
                    ),
                  ))
              .toList(),
        );
      }),
    );
  }

  Widget _schedulePanel() {
    final date = _detail.nextCollectionDate ?? _detail.scheduledDate;
    return _panel(
      icon: Icons.schedule,
      title: 'Próximo cobro',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: context.hg.burgundy.withValues(alpha: .14),
            border:
                Border.all(color: context.hg.burgundy.withValues(alpha: .52)),
            borderRadius: BorderRadius.circular(15)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                    color: context.hg.burgundy.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.calendar_month_outlined,
                    color: context.hg.burgundy, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(date == null ? 'Sin fecha programada' : _longDate(date),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(_scheduleStatus,
                      style:
                          TextStyle(color: context.hg.mutedText, fontSize: 13)),
                ])),
          ]),
          const SizedBox(height: 12),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey('edit-schedule'),
                onPressed: _canChangeInvoice && widget.canReschedule
                    ? () => _finish(_InvoiceDetailActionType.reschedule)
                    : null,
                child: Text(_detail.scheduledDate == null
                    ? 'Crear programación'
                    : 'Editar programación'),
              )),
        ]),
      ),
    );
  }

  Widget _actionsPanel() => _panel(
        icon: Icons.settings_outlined,
        title: 'Acciones',
        child: Column(children: [
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('add-payment-action'),
                onPressed: _canChangeInvoice && widget.canAddPayment
                    ? () => _finish(_InvoiceDetailActionType.payment)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Registrar abono'),
              )),
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('pay-in-full-action'),
                onPressed: _canChangeInvoice && widget.canPayInFull
                    ? () => _finish(_InvoiceDetailActionType.payInFull)
                    : null,
                icon: const Icon(Icons.check),
                label: const Text('Registrar pago completo'),
              )),
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('schedule-action'),
                onPressed: _canChangeInvoice && widget.canReschedule
                    ? () => _finish(_InvoiceDetailActionType.reschedule)
                    : null,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_detail.scheduledDate == null
                    ? 'Programar cobro'
                    : 'Reprogramar cobro'),
              )),
        ]),
      );

  Widget _informationNote() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(13)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 18, color: context.hg.mutedText),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  'Los valores y el estado se calculan desde los abonos canónicos. Abrir esta ventana no modifica la factura.',
                  style: TextStyle(
                      color: context.hg.mutedText,
                      fontSize: 12,
                      height: 1.45))),
        ]),
      );

  Widget _footer(bool compact) {
    final invoice = _detail.invoice;
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: compact ? 14 : 24, vertical: 12),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border:
              Border(top: BorderSide(color: Theme.of(context).dividerColor))),
      child: Row(children: [
        if (!compact)
          Expanded(
              child: Text(
                  'Estado actual: $_status · ${_money(invoice.saldo)} pendientes',
                  style: TextStyle(color: context.hg.mutedText, fontSize: 13))),
        Expanded(
          flex: compact ? 1 : 0,
          child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: compact ? 1 : 0,
          child: FilledButton(
            key: const ValueKey('add-payment-footer'),
            onPressed: _canChangeInvoice && widget.canAddPayment
                ? () => _finish(_InvoiceDetailActionType.payment)
                : null,
            child: const Text('Añadir abono'),
          ),
        ),
      ]),
    );
  }
}

class _TotalData {
  const _TotalData(this.label, this.value, this.balance);
  final String label;
  final String value;
  final bool balance;
}
