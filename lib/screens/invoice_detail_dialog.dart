import 'package:flutter/material.dart';

import '../models/fila_venta.dart';
import 'payment_calendar/widgets/pending_invoice_card.dart';
import 'reporte/report_invoice_table.dart';

enum _InvoiceDetailAction { payment, payInFull, reschedule }

Future<void> showInvoiceDetailDialog(
  BuildContext context, {
  required FilaVenta invoice,
  DateTime? scheduledDate,
  String? reportMonth,
  Future<void> Function()? onPayment,
  Future<void> Function()? onPayInFull,
  Future<void> Function()? onReschedule,
  Future<void> Function()? onClosed,
}) async {
  final action = await showDialog<_InvoiceDetailAction>(
    context: context,
    builder: (context) => _InvoiceDetailDialog(
      invoice: invoice,
      scheduledDate: scheduledDate,
      reportMonth: reportMonth,
      canChange: !invoice.anulada && !invoice.pagada,
      canReschedule:
          !invoice.anulada && !invoice.pagada && onReschedule != null,
    ),
  );
  if (action == _InvoiceDetailAction.payment) await onPayment?.call();
  if (action == _InvoiceDetailAction.payInFull) await onPayInFull?.call();
  if (action == _InvoiceDetailAction.reschedule) await onReschedule?.call();
  await onClosed?.call();
}

class _InvoiceDetailDialog extends StatelessWidget {
  const _InvoiceDetailDialog({
    required this.invoice,
    required this.scheduledDate,
    required this.reportMonth,
    required this.canChange,
    required this.canReschedule,
  });

  final FilaVenta invoice;
  final DateTime? scheduledDate;
  final String? reportMonth;
  final bool canChange;
  final bool canReschedule;

  String get _status => invoice.anulada
      ? 'Anulada'
      : invoice.pagada
          ? 'Pagada'
          : invoice.abonoParcial
              ? 'Pendiente con abonos'
              : 'Pendiente';

  Widget _field(String label, String value, {bool emphasized = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: SelectableText(
                value.trim().isEmpty ? '—' : value,
                style: emphasized
                    ? const TextStyle(fontWeight: FontWeight.bold)
                    : null,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final payments = invoice.abonos
        .where((payment) =>
            payment.valor != 0 ||
            payment.numeroRecibo != null ||
            payment.comentario.trim().isNotEmpty)
        .toList(growable: false);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('Detalle de factura',
                      style: Theme.of(context).textTheme.headlineSmall),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ]),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field('REF. (FACT)',
                          visibleTableReference(invoice.referencia),
                          emphasized: true),
                      _field('Número de factura', invoice.numeroFactura),
                      _field('Cliente', invoice.cliente),
                      _field('Nombre comercial', invoice.nombreComercial),
                      _field('Vendedor', invoice.vendedor),
                      _field('Fecha de factura', invoice.fecha),
                      _field(
                        'Fecha de cobro',
                        scheduledDate == null
                            ? 'Sin programación'
                            : calendarDate(scheduledDate!),
                      ),
                      if (reportMonth?.isNotEmpty ?? false)
                        _field('Reporte', reportMonth!),
                      _field('Venta', '\$${invoice.venta.toStringAsFixed(2)}'),
                      const Divider(height: 28),
                      Text('Abonos',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (payments.isEmpty)
                        const Text('No hay abonos registrados.')
                      else
                        for (final (index, payment) in payments.indexed)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                  'Abono ${index + 1}: \$${payment.valor.toStringAsFixed(2)}'),
                              subtitle: Text(
                                'Recibo: ${payment.numeroRecibo?.toString() ?? 'Sin número'}\n'
                                'Comentario: ${payment.comentario.trim().isEmpty ? 'Sin comentario' : payment.comentario}',
                              ),
                            ),
                          ),
                      const Divider(height: 28),
                      _field('Total abonado',
                          '\$${invoice.totalAbonos.toStringAsFixed(2)}'),
                      _field('Saldo', '\$${invoice.saldo.toStringAsFixed(2)}',
                          emphasized: true),
                      _field('Estado', _status, emphasized: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: canReschedule
                        ? () => Navigator.pop(
                            context, _InvoiceDetailAction.reschedule)
                        : null,
                    icon: const Icon(Icons.event_repeat),
                    label: const Text('Reprogramar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canChange
                        ? () =>
                            Navigator.pop(context, _InvoiceDetailAction.payment)
                        : null,
                    icon: const Icon(Icons.add_card),
                    label: const Text('Registrar abono'),
                  ),
                  FilledButton.icon(
                    onPressed: canChange
                        ? () => Navigator.pop(
                            context, _InvoiceDetailAction.payInFull)
                        : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Pago completo'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
