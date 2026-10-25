import 'package:flutter/material.dart';

import '../models/fila_venta.dart';
import '../services/supabase_reportes_service.dart';
import 'reporte/report_invoice_table.dart';

typedef InvoiceDetailLoader = Future<InvoiceDetailSnapshot?> Function(
  String canonicalReference,
);

enum _InvoiceDetailActionType { payment, editPayment, payInFull, reschedule }

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
        scheduledDate.isBefore(DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day)) &&
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
    builder: (context) => _InvoiceDetailDialog(
      canonicalReference: invoice.referencia.trim(),
      fallback: fallback,
      loader: loader,
      canEditPayment: onEditPayment != null,
      onViewCustomerProfile: onViewCustomerProfile,
    ),
  );
  if (action?.type == _InvoiceDetailActionType.payment) await onPayment?.call();
  if (action?.type == _InvoiceDetailActionType.editPayment &&
      action?.paymentIndex != null) {
    await onEditPayment?.call(action!.paymentIndex!);
  }
  if (action?.type == _InvoiceDetailActionType.payInFull) {
    await onPayInFull?.call();
  }
  if (action?.type == _InvoiceDetailActionType.reschedule) {
    await onReschedule?.call();
  }
  await onClosed?.call();
}

class _InvoiceDetailDialog extends StatefulWidget {
  const _InvoiceDetailDialog({
    required this.canonicalReference,
    required this.fallback,
    required this.loader,
    required this.canEditPayment,
    required this.onViewCustomerProfile,
  });

  final String canonicalReference;
  final InvoiceDetailSnapshot fallback;
  final InvoiceDetailLoader loader;
  final bool canEditPayment;
  final Future<bool> Function()? onViewCustomerProfile;

  @override
  State<_InvoiceDetailDialog> createState() => _InvoiceDetailDialogState();
}

class _InvoiceDetailDialogState extends State<_InvoiceDetailDialog> {
  late InvoiceDetailSnapshot _detail = widget.fallback;
  bool _loading = true;
  bool _openingProfile = false;
  String? _error;
  String? _profileError;
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

  Future<void> _openCustomerProfile() async {
    final callback = widget.onViewCustomerProfile;
    if (callback == null || _openingProfile) return;
    setState(() {
      _openingProfile = true;
      _profileError = null;
    });
    final opened = await callback();
    if (!mounted) return;
    setState(() {
      _openingProfile = false;
      if (!opened) {
        _profileError = 'No se pudo identificar al cliente de esta factura.';
      }
    });
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

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
      'manual' => 'Programación manual',
      'customer_term' => 'Programada según el plazo del cliente',
      _ => 'Programada',
    };
  }

  Widget _field(String label, String value, {bool emphasized = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 480;
          final content = SelectableText(
            value.trim().isEmpty ? '—' : value,
            style: emphasized
                ? const TextStyle(fontWeight: FontWeight.bold)
                : null,
          );
          if (compact) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  content,
                ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 180,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: content),
          ]);
        }),
      );

  @override
  Widget build(BuildContext context) {
    final invoice = _detail.invoice;
    final payments = invoice.abonos.indexed
        .where((entry) =>
            entry.$2.valor != 0 ||
            entry.$2.numeroRecibo != null ||
            entry.$2.comentario.trim().isNotEmpty)
        .toList(growable: false);
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final body = Column(children: [
      Material(
        color: reportInvoiceRowBackground(context, _rowStatus),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Detalle de factura',
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text(
                      '${visibleTableReference(invoice.referencia)} · ${invoice.numeroFactura}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ]),
        ),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 3),
      if (_error != null)
        MaterialBanner(
          content: Text(_error!),
          actions: [
            TextButton(onPressed: _load, child: const Text('Reintentar'))
          ],
        ),
      Expanded(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(mobile ? 16 : 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(
                avatar: Icon(Icons.circle,
                    size: 12,
                    color: reportInvoiceRowBorder(context, _rowStatus)),
                label: Text(_status),
              ),
              Chip(label: Text(_scheduleStatus)),
            ]),
            const SizedBox(height: 16),
            _field('Referencia', visibleTableReference(invoice.referencia),
                emphasized: true),
            _field('Número de factura', invoice.numeroFactura),
            _field('Fecha de emisión', invoice.fecha),
            _field(
              'Fecha programada',
              _detail.scheduledDate == null
                  ? 'Sin programación'
                  : _date(_detail.scheduledDate!),
            ),
            _field(
              'Próxima fecha de cobro',
              _detail.nextCollectionDate == null
                  ? 'Sin próximo cobro programado'
                  : _date(_detail.nextCollectionDate!),
            ),
            _field('Cliente', invoice.cliente),
            _field('Nombre comercial', invoice.nombreComercial),
            _field('Vendedor', invoice.vendedor),
            if (_detail.reportMonth.isNotEmpty)
              _field('Reporte', _detail.reportMonth),
            _field(
                'Plazo de pago',
                invoice.paymentTermDays == null
                    ? 'Sin plazo configurado'
                    : '${invoice.paymentTermDays} días'),
            const Divider(height: 28),
            Text('Resumen', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _field('Total de venta', _money(invoice.venta)),
            _field('Total abonado', _money(invoice.totalAbonos)),
            _field('Saldo', _money(invoice.saldo), emphasized: true),
            const Divider(height: 28),
            Text('Historial de abonos',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (payments.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child:
                      Text('No existen abonos registrados para esta factura.'),
                ),
              )
            else
              for (final entry in payments)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    'Abono ${entry.$1 + 1} · ${_money(entry.$2.valor)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                Text(
                                    'Fecha: ${entry.$2.fecha == null ? 'No disponible' : _date(entry.$2.fecha!)}'),
                                Text(
                                    'Recibo: ${entry.$2.numeroRecibo?.toString() ?? 'Sin número'}'),
                                Text(
                                    'Comentario: ${entry.$2.comentario.trim().isEmpty ? 'Sin comentario' : entry.$2.comentario.trim()}'),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Editar o eliminar abono ${entry.$1 + 1}',
                            onPressed: invoice.anulada || !widget.canEditPayment
                                ? null
                                : () => Navigator.pop(
                                      context,
                                      _InvoiceDetailAction(
                                        _InvoiceDetailActionType.editPayment,
                                        entry.$1,
                                      ),
                                    ),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ]),
                  ),
                ),
          ]),
        ),
      ),
      if (_profileError != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_profileError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('view-customer-profile'),
                onPressed:
                    widget.onViewCustomerProfile == null || _openingProfile
                        ? null
                        : _openCustomerProfile,
                icon: const Icon(Icons.person_outline),
                label: const Text('Ver perfil del cliente'),
              ),
              OutlinedButton.icon(
                onPressed: invoice.anulada || invoice.pagada
                    ? null
                    : () => Navigator.pop(
                        context,
                        const _InvoiceDetailAction(
                            _InvoiceDetailActionType.reschedule)),
                icon: const Icon(Icons.event_repeat),
                label: Text(_detail.scheduledDate == null
                    ? 'Programar cobro'
                    : 'Reprogramar cobro'),
              ),
              OutlinedButton.icon(
                onPressed: invoice.anulada || invoice.pagada
                    ? null
                    : () => Navigator.pop(
                        context,
                        const _InvoiceDetailAction(
                            _InvoiceDetailActionType.payment)),
                icon: const Icon(Icons.add_card),
                label: const Text('Añadir abono'),
              ),
              FilledButton.icon(
                onPressed: invoice.anulada || invoice.pagada
                    ? null
                    : () => Navigator.pop(
                        context,
                        const _InvoiceDetailAction(
                            _InvoiceDetailActionType.payInFull)),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Pago completo'),
              ),
            ],
          ),
        ),
      ),
    ]);
    if (mobile) return Dialog.fullscreen(child: body);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 820),
        child: body,
      ),
    );
  }
}
