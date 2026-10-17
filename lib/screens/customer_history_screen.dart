import 'dart:async';

import 'package:flutter/material.dart';

import '../models/billing_customer.dart';
import '../models/customer_history.dart';
import '../services/customer_history_repository.dart';
import 'reporte/report_invoice_table.dart';

typedef CustomerInvoiceDetail = Future<void> Function(
  CustomerHistoryInvoice invoice,
  BillingCustomer customer,
);

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen(
      {required this.customer,
      required this.onEditTerm,
      required this.onEditHours,
      required this.onSchedule,
      required this.onDelete,
      this.onOpenInvoiceDetail,
      this.repository,
      super.key});
  final BillingCustomer customer;
  final CustomerHistoryDataSource? repository;
  final Future<int?> Function(BillingCustomer) onEditTerm;
  final Future<BillingCustomer> Function(BillingCustomer, String?) onEditHours;
  final Future<void> Function(BillingCustomer) onSchedule;
  final Future<bool> Function(BillingCustomer) onDelete;
  final CustomerInvoiceDetail? onOpenInvoiceDetail;
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
  int _loadGeneration = 0;
  String? _activeRequestKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final offset = more ? invoices.length : 0;
    final requestKey = [
      customer.id,
      offset,
      status,
      searchController.text.trim(),
      sort,
    ].join('|');
    if (_activeRequestKey == requestKey) return;
    final generation = ++_loadGeneration;
    _activeRequestKey = requestKey;
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
        offset: offset,
        status: status,
        search: searchController.text,
        sort: sort,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (page.customer != null) {
          customer = BillingCustomer.fromJson(page.customer!);
        }
        summary = page.summary;
        filteredCount = page.filteredCount;
        if (!more) invoices.clear();
        invoices.addAll(page.invoices);
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => error = 'No se pudo cargar el historial.');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
        _activeRequestKey = null;
      }
    }
  }

  Future<void> _refreshPreservingView() async {
    final generation = ++_loadGeneration;
    _activeRequestKey = 'refresh-preserving-$generation';
    final targetCount = invoices.length.clamp(25, 1 << 31);
    try {
      final refreshed = <CustomerHistoryInvoice>[];
      CustomerHistoryPage? firstPage;
      while (refreshed.length < targetCount) {
        final page = await repository.load(
          customerId: customer.id,
          offset: refreshed.length,
          status: status,
          search: searchController.text,
          sort: sort,
        );
        firstPage ??= page;
        refreshed.addAll(page.invoices);
        if (page.invoices.isEmpty || refreshed.length >= page.filteredCount) {
          break;
        }
      }
      if (!mounted || generation != _loadGeneration || firstPage == null) {
        return;
      }
      final currentPage = firstPage;
      setState(() {
        if (currentPage.customer != null) {
          customer = BillingCustomer.fromJson(currentPage.customer!);
        }
        summary = currentPage.summary;
        filteredCount = currentPage.filteredCount;
        invoices
          ..clear()
          ..addAll(refreshed);
        error = null;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => error = 'No se pudo actualizar el historial.');
      }
    } finally {
      if (generation == _loadGeneration) _activeRequestKey = null;
    }
  }

  Future<void> _openInvoice(CustomerHistoryInvoice invoice) async {
    final callback = widget.onOpenInvoiceDetail;
    if (callback == null) return;
    await callback(invoice, customer);
    if (mounted) await _refreshPreservingView();
  }

  void _search(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _editTerm() async {
    if (actionBusy || !customer.configurationActive) return;
    setState(() => actionBusy = true);
    try {
      final days = await widget.onEditTerm(customer);
      if (days != null && mounted) {
        setState(() => customer = BillingCustomer(
            id: customer.id,
            name: customer.name,
            commercialName: customer.commercialName,
            paymentTermDays: days,
            businessHours: customer.businessHours,
            configurationActive: customer.configurationActive));
        await _load();
      }
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _editHours() async {
    if (actionBusy || !customer.configurationActive) return;
    final updated = await showDialog<BillingCustomer>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BusinessHoursDialog(
            customer: customer,
            onSave: (value) => widget.onEditHours(customer, value)));
    if (updated == null || !mounted) return;
    await _load();
    if (!mounted) return;
    if (customer.businessHours != updated.businessHours) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo verificar el horario guardado.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horario de atención guardado.')));
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
                      child: Text('Perfil del Cliente',
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                      tooltip: 'Cerrar Perfil del Cliente',
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
                        onEditHours: _editHours,
                        onSchedule: customer.configured ? _schedule : null,
                        onDelete: _delete),
                    if (!customer.configurationActive) ...[
                      const SizedBox(height: 8),
                      const Text(
                          'El cliente ya no está disponible para edición.'),
                    ],
                    const SizedBox(height: 16),
                    if (loading && summary == null)
                      const Padding(
                          padding: EdgeInsets.all(60),
                          child: Center(child: CircularProgressIndicator()))
                    else if (error != null && summary == null)
                      _ErrorState(message: error!, retry: _load)
                    else ...[
                      if (error != null) ...[
                        _ErrorState(message: error!, retry: _load),
                        const SizedBox(height: 12),
                      ],
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
                                  ? 'Este cliente todavía no tiene facturas asociadas.'
                                  : 'No se encontraron facturas con estos filtros.')),
                        )
                      else
                        for (final invoice in invoices)
                          _InvoiceCard(
                              invoice: invoice,
                              onOpenDetail: widget.onOpenInvoiceDetail == null
                                  ? null
                                  : () => _openInvoice(invoice)),
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
      key: const ValueKey('customer-history-search'),
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
            Text(
                'Horario de atención: ${customer.businessHours ?? 'Sin registrar'}',
                softWrap: true),
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
      required this.onEditHours,
      required this.onSchedule,
      required this.onDelete});
  final BillingCustomer customer;
  final bool busy;
  final VoidCallback onEdit, onDelete;
  final VoidCallback onEditHours;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(
            onPressed: busy || !customer.configurationActive ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar plazo')),
        Tooltip(
          message: customer.configurationActive
              ? 'Editar horario de atención'
              : 'El cliente ya no está disponible para edición',
          child: FilledButton.tonalIcon(
              onPressed:
                  busy || !customer.configurationActive ? null : onEditHours,
              icon: const Icon(Icons.schedule_outlined),
              label: const Text('Editar horario')),
        ),
        Tooltip(
          message: customer.configured
              ? 'Programar facturas pendientes'
              : 'Configura primero los días de pago',
          child: FilledButton.tonalIcon(
              onPressed:
                  busy || !customer.configurationActive ? null : onSchedule,
              icon: const Icon(Icons.event_repeat_outlined),
              label: const Text('Programar pendientes')),
        ),
        OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: busy || !customer.configurationActive ? null : onDelete,
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

class _BusinessHoursDialog extends StatefulWidget {
  const _BusinessHoursDialog({required this.customer, required this.onSave});
  final BillingCustomer customer;
  final Future<BillingCustomer> Function(String?) onSave;

  @override
  State<_BusinessHoursDialog> createState() => _BusinessHoursDialogState();
}

class _BusinessHoursDialogState extends State<_BusinessHoursDialog> {
  late final TextEditingController controller =
      TextEditingController(text: widget.customer.businessHours ?? '');
  bool saving = false;
  String? error;

  String? get normalized {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  bool get changed => normalized != widget.customer.businessHours;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !changed || controller.text.length > 120) return;
    if (normalized == null && widget.customer.businessHours != null) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Quitar horario'),
                content: const Text(
                    'El horario actual se eliminará. ¿Deseas continuar?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Quitar horario')),
                ],
              ));
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.onSave(normalized);
      if (mounted) Navigator.pop(context, result);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'No se pudo guardar el horario. Inténtalo nuevamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Editar horario de atención'),
        content: SizedBox(
          width: 480,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.customer.name,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                    'Horario actual: ${widget.customer.businessHours ?? 'Sin registrar'}'),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  enabled: !saving,
                  maxLength: 120,
                  maxLines: 3,
                  onChanged: (_) => setState(() => error = null),
                  decoration: InputDecoration(
                      labelText: 'Horario de atención',
                      hintText: 'Lunes a viernes, 09:00 - 17:00',
                      errorText: error),
                  onSubmitted: (_) => save(),
                ),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: saving || !changed || controller.text.length > 120
                  ? null
                  : save,
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar')),
        ],
      );
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
              height: wide ? 100 : 116,
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(item.$1,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center),
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
  const _InvoiceCard({required this.invoice, this.onOpenDetail});
  final CustomerHistoryInvoice invoice;
  final VoidCallback? onOpenDetail;
  String money(double v) => '\$${v.toStringAsFixed(2)}';
  String date(DateTime v) =>
      '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';

  ReportInvoiceRowStatus get rowStatus => invoice.cancelled
      ? ReportInvoiceRowStatus.cancelled
      : invoice.isPaid
          ? ReportInvoiceRowStatus.paid
          : invoice.paid > 0 && invoice.balance > 0
              ? ReportInvoiceRowStatus.partialPayment
              : ReportInvoiceRowStatus.normal;

  @override
  Widget build(BuildContext context) {
    final background = reportInvoiceRowBackground(context, rowStatus);
    final shape = rowStatus == ReportInvoiceRowStatus.normal
        ? null
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: reportInvoiceRowBorder(context, rowStatus),
              width: 1.4,
            ),
          );
    return Card(
      key: ValueKey('customer-invoice-${invoice.reference}'),
      color: background,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetail,
        child: ListTile(
          title: Text('Factura ${invoice.invoiceNumber}'),
          subtitle: Text('${date(invoice.date)} · ${invoice.status}'),
          trailing: Text(
            money(invoice.balance),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
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
