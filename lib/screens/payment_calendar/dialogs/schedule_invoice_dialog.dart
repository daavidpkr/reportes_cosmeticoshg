import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/payment_calendar_entry.dart';
import '../../../services/payment_calendar_repository.dart';
import '../widgets/pending_invoice_card.dart';
import 'day_invoices_dialog.dart';

Future<String?> showScheduleInvoiceDialog(
  BuildContext context, {
  required DateTime day,
  required CalendarInvoiceSchedulingDataSource repository,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ScheduleInvoiceDialog(day: day, repository: repository),
    );

class _ScheduleInvoiceDialog extends StatefulWidget {
  const _ScheduleInvoiceDialog({required this.day, required this.repository});

  final DateTime day;
  final CalendarInvoiceSchedulingDataSource repository;

  @override
  State<_ScheduleInvoiceDialog> createState() => _ScheduleInvoiceDialogState();
}

class _ScheduleInvoiceDialogState extends State<_ScheduleInvoiceDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<SchedulableInvoice> _invoices = const [];
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await widget.repository.searchSchedulableInvoices(_search.text);
      if (!mounted || generation != _generation) return;
      setState(() => _invoices = result);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'No se pudieron buscar las facturas pendientes.');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Programar factura',
                            style: Theme.of(context).textTheme.headlineSmall),
                        Text(longCalendarDate(widget.day)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('schedule-invoice-search'),
                  controller: _search,
                  autofocus: true,
                  onChanged: _changed,
                  decoration: const InputDecoration(
                    labelText: 'Buscar factura o cliente',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!, textAlign: TextAlign.center),
                                  const SizedBox(height: 8),
                                  FilledButton.tonal(
                                    onPressed: _load,
                                    child: const Text('Reintentar'),
                                  ),
                                ],
                              ),
                            )
                          : _invoices.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No hay facturas pendientes elegibles.\n'
                                    'Las facturas anuladas, pagadas o sin plazo no se pueden programar.',
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: _invoices.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final invoice = _invoices[index];
                                    return ListTile(
                                      key: ValueKey(
                                          'schedulable-${invoice.facturaId}'),
                                      title: Text(
                                        'REF. ${visibleInvoiceReference(invoice.facturaId)} · ${invoice.cliente}',
                                      ),
                                      subtitle: Text([
                                        if (invoice.nombreComercial.isNotEmpty)
                                          invoice.nombreComercial,
                                        'Factura: ${invoice.invoiceNumber}',
                                        'Saldo: \$${invoice.balance.toStringAsFixed(2)}',
                                        if (invoice.reminderDate != null)
                                          'Programada: ${calendarDate(invoice.reminderDate!)}',
                                      ].join('\n')),
                                      isThreeLine: true,
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => Navigator.pop(
                                          context, invoice.facturaId),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
        ),
      );
}
