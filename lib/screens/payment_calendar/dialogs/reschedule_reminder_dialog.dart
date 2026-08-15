import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/payment_calendar_entry.dart';
import '../../../models/payment_calendar_rules.dart';
import '../widgets/pending_invoice_card.dart';

class ReminderEdit {
  const ReminderEdit(this.date, this.comment);
  final DateTime date;
  final String comment;
}

Future<ReminderEdit?> showRescheduleReminderDialog(
    BuildContext context, PaymentCalendarEntry entry) async {
  var selected = entry.reminderDate;
  var adjusted = adjustedReminderDate(selected);
  final controller = TextEditingController(text: entry.comment);
  final result = await showDialog<ReminderEdit>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              title: const Text('Actualizar recordatorio'),
              content: SingleChildScrollView(
                  child: SizedBox(
                      width: 420,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Fecha actual: ${calendarDate(entry.reminderDate)}'),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_month_outlined),
                                label: Text(calendarDate(selected)),
                                onPressed: () async {
                                  final value = await showDatePicker(
                                      context: context,
                                      initialDate: selected,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2100));
                                  if (value != null) {
                                    setState(() {
                                      selected = value;
                                      adjusted = adjustedReminderDate(value);
                                    });
                                  }
                                }),
                            if (adjusted != dateOnly(selected))
                              Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                      'La fecha seleccionada cae en fin de semana. El recordatorio se programará para el lunes ${calendarDate(adjusted)}.',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.w600))),
                            const SizedBox(height: 16),
                            TextField(
                                controller: controller,
                                maxLength: 500,
                                maxLines: 4,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(500)
                                ],
                                decoration: const InputDecoration(
                                    labelText: 'Comentario (opcional)',
                                    alignLabelWithHint: true)),
                          ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                                  title: const Text('Confirmar cambios'),
                                  content: Text(
                                      'Se guardará el recordatorio para el ${calendarDate(adjusted)}.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Volver')),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Confirmar'))
                                  ]));
                      if (confirmed == true && context.mounted) {
                        Navigator.pop(context,
                            ReminderEdit(adjusted, controller.text.trim()));
                      }
                    },
                    child: const Text('Guardar'))
              ],
            );
          }));
  controller.dispose();
  return result;
}
