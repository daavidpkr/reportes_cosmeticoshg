import 'dart:async';

import 'package:flutter/material.dart';

import '../models/billing_customer.dart';
import '../models/customer_history.dart';
import '../services/customer_history_repository.dart';
import '../services/payment_calendar_refresh.dart';

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen(
      {required this.customer,
      required this.onEditTerm,
      required this.onSchedule,
      required this.onDelete,
      this.repository,
      super.key});
  final BillingCustomer customer;
  final CustomerHistoryDataSource? repository;
  final Future<int?> Function(BillingCustomer) onEditTerm;
  final Future<void> Function(BillingCustomer) onSchedule;
  final Future<bool> Function(BillingCustomer) onDelete;
  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  late final CustomerHistoryDataSource repository =
      widget.repository ?? CustomerHistoryRepository();
  final searchController = TextEditingController();
  Timer? debounce;
  CustomerHistorySummary? summary;
  final invoices = <CustomerHistoryInvoice>[];
  String status = 'all', sort = 'recent';
  int filteredCount = 0;
  bool loading = false, loadingMore = false;
  String? error;
  late BillingCustomer customer = widget.customer;
  bool actionBusy = false;
  final reprogramming = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more ? loadingMore : loading) return;
    setState(() {
      if (more) {
        loadingMore = true;
      } else {
        loading = true;
        error = null;
      }
    });
    try {
      final page = await repository.load(
        customerId: customer.id,
        offset: more ? invoices.length : 0,
        status: status,
        search: searchController.text,
        sort: sort,
      );
      if (!mounted) return;
      setState(() {
        summary = page.summary;
        filteredCount = page.filteredCount;
        if (!more) invoices.clear();
        invoices.addAll(page.invoices);
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo cargar el historial.');
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  void _search(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _editTerm() async {
    if (actionBusy) return;
    setState(() => actionBusy = true);
    try {
      final days = await widget.onEditTerm(customer);
      if (days != null && mounted) {
        setState(() => customer = BillingCustomer(
            id: customer.id,
            name: customer.name,
            commercialName: customer.commercialName,
            paymentTermDays: days));
        await _load();
      }
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _schedule() async {
    if (actionBusy || !customer.configured) return;
    setState(() => actionBusy = true);
    try {
      await widget.onSchedule(customer);
      await _load();
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _delete() async {
    if (actionBusy) return;
    setState(() => actionBusy = true);
    try {
      if (await widget.onDelete(customer) && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _reprogram(CustomerHistoryInvoice invoice) async {
    if (reprogramming.contains(invoice.reference)) return;
    if (!customer.configured) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configura primero el plazo de pago del cliente')));
      return;
    }
    setState(() => reprogramming.add(invoice.reference));
    try {
      var preview = await repository.previewRecalculation(invoice.reference);
      if (!mounted) return;
      if (preview.alreadyCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Esta factura ya está programada de acuerdo con el plazo actual.')));
        return;
      }
      while (mounted) {
        final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
                  title: const Text('Reprogramar factura'),
                  content: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text('Factura: ${preview.reference}'),
                        Text('Fecha de factura: ${_date(preview.invoiceDate)}'),
                        Text(
                            'Plazo actual del cliente: ${preview.termDays} ${preview.termDays == 1 ? 'día' : 'días'}'),
                        const SizedBox(height: 16),
                        Text(
                            'Fecha programada actual: ${preview.currentDate == null ? 'Sin programar' : _date(preview.currentDate!)}'),
                        Text('Nueva fecha calculada: ${_date(preview.newDate)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        if (preview.manualSchedule) ...[
                          const SizedBox(height: 12),
                          Text(
                              'Esta factura tiene una fecha reprogramada manualmente. Al continuar, se reemplazará por la fecha calculada con el plazo actual.',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 12),
                        const Text(
                            'Se modificará únicamente esta factura.\nLas demás facturas del cliente conservarán sus fechas.\n\n¿Deseas continuar?'),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Reprogramar factura')),
                  ],
                ));
        if (confirmed != true || !mounted) return;
        final result = await repository.reprogramInvoice(preview);
        if (!mounted) return;
        if (result.status == 'confirmation_required' ||
            result.confirmationRequired) {
          preview = result;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Los datos cambiaron en otro dispositivo. Revisa la nueva fecha antes de confirmar.')));
          continue;
        }
        if (result.status == 'already_current' || result.alreadyCurrent) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Esta factura ya está programada de acuerdo con el plazo actual.')));
          return;
        }
        if (result.status != 'updated' && result.status != 'created') {
          _showReprogramError(invoice, result.reason ?? result.status);
          return;
        }
        await _load(); // Authoritative second read; preserves modal/filter/scroll.
        final persisted = invoices
            .where((item) => item.reference == result.reference)
            .firstOrNull;
        if (persisted?.reminderDate != result.newDate) {
          _showReprogramError(invoice, 'schedule_changed');
          return;
        }
        paymentCalendarRefresh.refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.status == 'created'
                ? 'Recordatorio creado para el ${_date(result.newDate)}.'
                : 'Factura ${result.reference} reprogramada para el ${_date(result.newDate)}.')));
        return;
      }
    } on InvoiceReprogramException catch (error) {
      if (mounted) _showReprogramError(invoice, error.reason);
    } catch (_) {
      if (mounted) {
        _showReprogramError(invoice, 'conflict');
      }
    } finally {
      if (mounted) setState(() => reprogramming.remove(invoice.reference));
    }
  }

  void _showReprogramError(CustomerHistoryInvoice invoice, String reason) {
    if (!mounted) return;
    final message = switch (reason) {
      'paid' => 'La factura ya se encuentra pagada.',
      'cancelled' => 'No se puede reprogramar una factura anulada.',
      'payment_term_missing' =>
        'Configura primero el plazo de pago del cliente.',
      'invoice_not_found' ||
      'not_found' =>
        'No se encontró la factura con su referencia completa.',
      'monthly_row_missing' => 'La factura no tiene una fila mensual válida.',
      'schedule_changed' ||
      'customer_changed' ||
      'conflict' =>
        'La información cambió desde que abriste el historial. Revisa las fechas e inténtalo nuevamente.',
      _ => 'No se pudo reprogramar esta factura.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        content: Text(message,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer)),
        action: SnackBarAction(
            label: 'Reintentar', onPressed: () => _reprogram(invoice))));
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
          horizontal: viewport.width < 600 ? 8 : 32,
          vertical: viewport.height < 700 ? 8 : 24),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: SizedBox(
          width: viewport.width < 600 ? viewport.width : 1180,
          height:
              viewport.height < 600 ? viewport.height : viewport.height * .9,
          child: Column(children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(children: [
                  Expanded(
                      child: Text('Historial del cliente',
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                      tooltip: 'Cerrar historial',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ]),
              ),
            ),
            Expanded(child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth >= 760;
              return RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: EdgeInsets.all(wide ? 24 : 14),
                  children: [
                    _Header(customer: customer),
                    const SizedBox(height: 8),
                    _CustomerActions(
                        customer: customer,
                        busy: actionBusy,
                        onEdit: _editTerm,
                        onSchedule: customer.configured ? _schedule : null,
                        onDelete: _delete),
                    const SizedBox(height: 16),
                    if (loading && summary == null)
                      const Padding(
                          padding: EdgeInsets.all(60),
                          child: Center(child: CircularProgressIndicator()))
                    else if (error != null && summary == null)
                      _ErrorState(message: error!, retry: _load)
                    else ...[
                      _Kpis(summary: summary!, wide: wide),
                      const SizedBox(height: 12),
                      _DebtSummary(summary: summary!),
                      const SizedBox(height: 16),
                      _toolbar(wide),
                      const SizedBox(height: 12),
                      if (invoices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                              child: Text(searchController.text.isEmpty &&
                                      status == 'all'
                                  ? 'Este cliente todavía no tiene facturas registradas.'
                                  : 'No se encontraron facturas con estos filtros.')),
                        )
                      else
                        for (final invoice in invoices)
                          _InvoiceCard(
                              invoice: invoice,
                              termDays: customer.paymentTermDays,
                              busy: reprogramming.contains(invoice.reference),
                              onReprogram: () => _reprogram(invoice)),
                      if (invoices.length < filteredCount)
                        Center(
                            child: FilledButton.tonal(
                          onPressed:
                              loadingMore ? null : () => _load(more: true),
                          child: loadingMore
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Cargar más'),
                        )),
                    ],
                  ],
                ),
              );
            }))
          ]),
        ),
      ),
    );
  }

  Widget _toolbar(bool wide) {
    final search = TextField(
      controller: searchController,
      onChanged: _search,
      decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search), hintText: 'Buscar factura'),
    );
    final counts = summary;
    final controls = Wrap(spacing: 8, runSpacing: 8, children: [
      for (final item in {
        'all': 'Todas (${counts?.totalInvoices ?? 0})',
        'pending': 'Pendientes (${counts?.pendingInvoices ?? 0})',
        'paid': 'Pagadas (${counts?.paidInvoices ?? 0})',
        'overdue': 'Vencidas (${counts?.overdueInvoices ?? 0})',
        'cancelled': 'Anuladas (${counts?.cancelledInvoices ?? 0})'
      }.entries)
        ChoiceChip(
            label: Text(item.value),
            selected: status == item.key,
            onSelected: (_) {
              setState(() => status = item.key);
              _load();
            }),
      DropdownButton<String>(
          value: sort,
          items: const [
            DropdownMenuItem(value: 'recent', child: Text('Más recientes')),
            DropdownMenuItem(value: 'oldest', child: Text('Más antiguas')),
            DropdownMenuItem(value: 'sale', child: Text('Mayor venta')),
            DropdownMenuItem(value: 'balance', child: Text('Mayor saldo')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => sort = value);
              _load();
            }
          }),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      search,
      const SizedBox(height: 10),
      if (wide)
        controls
      else
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: controls)
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.customer});
  final BillingCustomer customer;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(customer.name, style: Theme.of(context).textTheme.titleLarge),
            Text(customer.commercialName.isEmpty
                ? 'Sin nombre comercial'
                : customer.commercialName),
            const SizedBox(height: 8),
            Text(customer.paymentTermDays == null
                ? 'Plazo pendiente'
                : 'Plazo de pago: ${customer.paymentTermDays} días'),
          ])));
}

class _CustomerActions extends StatelessWidget {
  const _CustomerActions(
      {required this.customer,
      required this.busy,
      required this.onEdit,
      required this.onSchedule,
      required this.onDelete});
  final BillingCustomer customer;
  final bool busy;
  final VoidCallback onEdit, onDelete;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(
            onPressed: busy ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar plazo')),
        Tooltip(
          message: customer.configured
              ? 'Programar facturas pendientes'
              : 'Configura primero los días de pago',
          child: FilledButton.tonalIcon(
              onPressed: busy ? null : onSchedule,
              icon: const Icon(Icons.event_repeat_outlined),
              label: const Text('Programar pendientes')),
        ),
        OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: busy ? null : onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar cliente')),
        if (busy)
          const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)))
      ]);
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.summary, required this.wide});
  final CustomerHistorySummary summary;
  final bool wide;
  @override
  Widget build(BuildContext context) {
    final items = [
      ('Total histórico', summary.totalSales),
      ('Total cobrado', summary.totalPaid),
      ('Deuda pendiente', summary.balance),
      ('Total de facturas', summary.totalInvoices.toDouble())
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = wide
          ? (constraints.maxWidth - 24) / 4
          : (constraints.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final item in items)
          SizedBox(
              width: width,
              height: 100,
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(item.$1, textAlign: TextAlign.center),
                            const SizedBox(height: 4),
                            FittedBox(
                                child: Text(
                                    item.$1 == 'Total de facturas'
                                        ? '${item.$2.toInt()}'
                                        : '\$${item.$2.toStringAsFixed(2)}',
                                    style:
                                        Theme.of(context).textTheme.titleLarge))
                          ]))))
      ]);
    });
  }
}

class _DebtSummary extends StatelessWidget {
  const _DebtSummary({required this.summary});
  final CustomerHistorySummary summary;
  String date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          leading: Icon(summary.balance <= .005
              ? Icons.verified_outlined
              : Icons.account_balance_wallet_outlined),
          title: Text(summary.balance <= .005
              ? 'Cliente al día'
              : 'Deuda pendiente: \$${summary.balance.toStringAsFixed(2)}'),
          subtitle: Text(summary.balance <= .005
              ? 'Sin deuda pendiente'
              : '${summary.pendingInvoices} facturas pendientes · ${summary.overdueInvoices} vencidas\n${summary.nextPayment == null ? 'Sin próximo cobro programado' : 'Próximo cobro: ${date(summary.nextPayment!)}'}')));
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard(
      {required this.invoice,
      required this.termDays,
      required this.busy,
      required this.onReprogram});
  final CustomerHistoryInvoice invoice;
  final int? termDays;
  final bool busy;
  final VoidCallback onReprogram;
  String money(double v) => '\$${v.toStringAsFixed(2)}';
  String date(DateTime v) =>
      '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';
  @override
  Widget build(BuildContext context) => Card(
          child: ExpansionTile(
              key: PageStorageKey(invoice.reference),
              title: Text('Factura ${invoice.invoiceNumber}'),
              subtitle: Text('${date(invoice.date)} · ${invoice.status}'),
              trailing: Text(money(invoice.balance),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'REF. ${invoice.reference} · ${invoice.reportMonth}'),
                      Text(
                          'Vendedor: ${invoice.seller.isEmpty ? 'Sin registrar' : invoice.seller}'),
                      Text(
                          'Venta: ${money(invoice.sale)} · Abonado: ${money(invoice.paid)} · Saldo: ${money(invoice.balance)}'),
                      if (invoice.reminderDate != null)
                        Text('Fecha de cobro: ${date(invoice.reminderDate!)}'),
                      if (invoice.calendarComment.isNotEmpty)
                        Text(
                            'Comentario del calendario: ${invoice.calendarComment}'),
                      const SizedBox(height: 8),
                      Tooltip(
                          message: termDays == null
                              ? 'Configura primero el plazo de pago del cliente'
                              : 'Recalcular esta factura con el plazo actual del cliente',
                          child: Semantics(
                              button: true,
                              label: termDays == null
                                  ? 'Configura primero el plazo de pago del cliente'
                                  : 'Reprogramar factura ${invoice.reference} con el plazo actual de $termDays ${termDays == 1 ? 'día' : 'días'}',
                              child: FilledButton.tonalIcon(
                                  key: ValueKey(
                                      'reprogram-${invoice.reference}'),
                                  onPressed: termDays == null ||
                                          invoice.cancelled ||
                                          invoice.isPaid ||
                                          invoice.reference.isEmpty ||
                                          busy
                                      ? null
                                      : onReprogram,
                                  icon: busy
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.event_repeat_outlined),
                                  label: const Text(
                                      'Reprogramar con plazo actual')))),
                      for (var i = 0; i < invoice.payments.length; i++)
                        Text(
                            'Abono ${i + 1}: ${money(invoice.payments[i].amount)} · Recibo: ${invoice.payments[i].receiptNumber ?? 'Sin recibo'}${invoice.payments[i].comment.isEmpty ? '' : ' · ${invoice.payments[i].comment}'}')
                    ]))
          ]));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
          child: Column(children: [
        Text(message),
        TextButton(onPressed: retry, child: const Text('Reintentar'))
      ]));
}
