import 'package:flutter/material.dart';

import '../../../models/payment_calendar_entry.dart';
import '../widgets/pending_invoice_card.dart';

const _weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo'
];
const _months = [
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
  'diciembre'
];
String longCalendarDate(DateTime date) =>
    '${_weekdays[date.weekday - 1]}, ${date.day} de ${_months[date.month - 1]} de ${date.year}';

Future<void> showDayInvoicesDialog(
    BuildContext context,
    DateTime day,
    List<PaymentCalendarEntry> entries,
    Future<void> Function(PaymentCalendarEntry) onEdit,
    Future<void> Function(PaymentCalendarEntry) onPayment,
    Future<void> Function(PaymentCalendarEntry) onPaid) async {
  await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 680, maxHeight: 760),
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text('Facturas pendientes',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall),
                                  Text(longCalendarDate(day))
                                ])),
                            IconButton(
                                tooltip: 'Cerrar',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close))
                          ]),
                          const SizedBox(height: 12),
                          Flexible(
                              child: entries.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'No hay facturas pendientes para este día.'))
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: entries.length,
                                      itemBuilder: (_, index) =>
                                          PendingInvoiceCard(
                                              entry: entries[index],
                                              onPayment: () async {
                                                Navigator.pop(context);
                                                await onPayment(entries[index]);
                                              },
                                              onPaid: () async {
                                                Navigator.pop(context);
                                                await onPaid(entries[index]);
                                              },
                                              onEdit: () async {
                                                Navigator.pop(context);
                                                await onEdit(entries[index]);
                                              }))),
                        ]))),
          ));
}
