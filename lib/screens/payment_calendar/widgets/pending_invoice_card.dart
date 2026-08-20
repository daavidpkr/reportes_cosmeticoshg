import 'package:flutter/material.dart';

import '../../../models/payment_calendar_entry.dart';

String calendarDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String visibleInvoiceReference(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  final withoutLeadingZeroes = trimmed.replaceFirst(RegExp(r'^0+'), '');
  return withoutLeadingZeroes.isEmpty ? '0' : withoutLeadingZeroes;
}

class PendingInvoiceCard extends StatelessWidget {
  const PendingInvoiceCard(
      {required this.entry,
      required this.onEdit,
      required this.onHistory,
      this.onPayment,
      this.onPaid,
      super.key});
  final PaymentCalendarEntry entry;
  final VoidCallback onEdit;
  final VoidCallback? onHistory;
  final VoidCallback? onPayment, onPaid;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('REF. ${visibleInvoiceReference(entry.facturaId)}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _line(
                'Nro. factura',
                visibleInvoiceReference(entry.invoiceNumber.isEmpty
                    ? entry.facturaId
                    : entry.invoiceNumber)),
            _line('Cliente', entry.cliente),
            _line('Nombre comercial', entry.nombreComercial),
            _line('Fecha de factura', calendarDate(entry.invoiceDate)),
            _line('Saldo pendiente', '\$${entry.balance.toStringAsFixed(2)}'),
            _line('Fecha de recordatorio', calendarDate(entry.reminderDate)),
            _line('Comentario',
                entry.comment.isEmpty ? 'Sin comentario' : entry.comment),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, constraints) {
              // Four icon buttons need roughly 145 logical pixels each.
              final wide = constraints.maxWidth >= 580;
              final buttons = <Widget>[
                _action('Registrar abono', 'Abono', Icons.payments_outlined,
                    onPayment),
                _action('Reprogramar factura', 'Reprogramar',
                    Icons.event_repeat_outlined, onEdit),
                _action('Marcar como pagada', 'Marcar pagada', Icons.task_alt,
                    onPaid,
                    filled: true),
                _action('Ver historial del cliente', 'Historial', Icons.history,
                    onHistory),
              ];
              if (wide) {
                return Row(
                    key: const ValueKey('invoice-actions-row'),
                    children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        Expanded(child: buttons[i]),
                        if (i < buttons.length - 1) const SizedBox(width: 6),
                      ]
                    ]);
              }
              return GridView.count(
                key: const ValueKey('invoice-actions-grid'),
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 3.2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: buttons,
              );
            }),
          ]),
        ),
      );

  Widget _line(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: value.trim().isEmpty ? 'Sin registrar' : value)
      ])));

  Widget _action(
      String tooltip, String label, IconData icon, VoidCallback? callback,
      {bool filled = false}) {
    final child = filled
        ? FilledButton.icon(
            onPressed: callback,
            icon: Icon(icon, size: 18),
            label: Text(label, maxLines: 1))
        : OutlinedButton.icon(
            onPressed: callback,
            icon: Icon(icon, size: 18),
            label: Text(label, maxLines: 1));
    return Semantics(
        label: tooltip,
        button: true,
        child: Tooltip(message: tooltip, child: child));
  }
}
