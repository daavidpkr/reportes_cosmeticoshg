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
      this.onPayment,
      this.onPaid,
      super.key});
  final PaymentCalendarEntry entry;
  final VoidCallback onEdit;
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
            Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                      onPressed: onPayment,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Registrar abono')),
                  OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.event_repeat_outlined),
                      label: const Text('Reprogramar')),
                  FilledButton.icon(
                      onPressed: onPaid,
                      icon: const Icon(Icons.task_alt),
                      label: const Text('Marcar como pagada')),
                ]),
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
}
