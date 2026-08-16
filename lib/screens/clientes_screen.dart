import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/billing_customer.dart';
import '../services/customer_terms_repository.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({this.repository, super.key});
  final CustomerTermsDataSource? repository;
  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  late final CustomerTermsDataSource _repository =
      widget.repository ?? CustomerTermsRepository();
  late Future<List<BillingCustomer>> _customers = _repository.listCustomers();
  final Set<String> _busy = {};
  String _key(BillingCustomer c) => '${c.name}\u0000${c.commercialName}';
  Future<void> _reload() async {
    final next = _repository.listCustomers();
    setState(() {
      _customers = next;
    });
    await next;
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _run(BillingCustomer c, Future<void> Function() action) async {
    if (_busy.contains(_key(c))) return;
    setState(() => _busy.add(_key(c)));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy.remove(_key(c)));
    }
  }

  Future<void> _edit(BillingCustomer c) async {
    final days = await showDialog<int>(
        context: context, builder: (_) => _PaymentTermDialog(customer: c));
    if (days == null || !mounted) return;
    final impacted = await _repository.previewImpact(c.id, days);
    final count =
        await _repository.savePaymentTerm(c.id, days, applyExisting: true);
    _message(impacted == 0
        ? 'Plazo habitual guardado.'
        : 'Plazo guardado y $count facturas programadas.');
    await _reload();
  }

  Future<void> _delete(BillingCustomer c) async {
    final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OperationDialog(
            title: 'Eliminar cliente',
            customer: c,
            confirmLabel: 'Eliminar cliente',
            destructive: true,
            body:
                'Se eliminará a este cliente únicamente del apartado Clientes.\n\nLas facturas, abonos y recordatorios relacionados se conservarán sin cambios.',
            operation: () => _repository.deleteCustomer(c)));
    if (ok != true || !mounted) return;
    _message(
        'Cliente eliminado del apartado Clientes. Sus facturas y recordatorios se conservaron.');
    await _reload();
  }

  Future<void> _schedule(BillingCustomer c) async {
    CustomerSchedulingResult? result;
    final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OperationDialog(
            title: 'Programar facturas pendientes',
            customer: c,
            confirmLabel: 'Programar',
            body:
                'Se buscarán las facturas con saldo de este cliente que todavía no tengan recordatorio en el calendario.\n\nPlazo configurado: ${c.paymentTermDays} días\n\nLos recordatorios existentes no serán modificados.',
            operation: () async {
              result = await _repository.schedulePending(c);
            }));
    if (ok != true || result == null || !mounted) return;
    if (result!.createdCount == 0) {
      _message(
          'Todas las facturas elegibles de este cliente ya están programadas.');
    } else if (result!.skippedCount > 0) {
      _message(
          'Se programaron ${result!.createdCount} facturas. Otras ${result!.skippedCount} no cumplían las condiciones.');
    } else {
      _message(
          'Se programaron ${result!.createdCount} facturas pendientes en el calendario.');
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<BillingCustomer>>(
        future: _customers,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(children: const [
              Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()))
            ]);
          }
          if (snapshot.hasError) {
            return ListView(children: [
              ListTile(
                  title: const Text('No se pudieron cargar los clientes.'),
                  trailing: TextButton(
                      onPressed: _reload, child: const Text('Reintentar')))
            ]);
          }
          final values = snapshot.data ?? const [];
          return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: values.length + 1,
              itemBuilder: (_, index) {
                if (index == 0) {
                  return const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Clientes',
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text(
                                'Configura los plazos de pago y administra la programación de cobros.')
                          ]));
                }
                final c = values[index - 1];
                final busy = _busy.contains(_key(c));
                return _CustomerCard(
                    customer: c,
                    busy: busy,
                    onEdit: () => _run(c, () => _edit(c)),
                    onSchedule:
                        c.configured ? () => _run(c, () => _schedule(c)) : null,
                    onDelete: () => _run(c, () => _delete(c)));
              });
        },
      ));
}

class _PaymentTermDialog extends StatefulWidget {
  const _PaymentTermDialog({required this.customer});
  final BillingCustomer customer;
  @override
  State<_PaymentTermDialog> createState() => _PaymentTermDialogState();
}

class _PaymentTermDialogState extends State<_PaymentTermDialog> {
  late final TextEditingController controller = TextEditingController(
      text: widget.customer.paymentTermDays?.toString() ?? '');
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.customer.name),
          content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Plazo habitual en días',
                  helperText: 'Usa 0 para pago el mismo día.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  final value = parsePaymentTerm(controller.text);
                  if (value != null) Navigator.pop(context, value);
                },
                child: const Text('Continuar'))
          ]);
}

class _OperationDialog extends StatefulWidget {
  const _OperationDialog(
      {required this.title,
      required this.body,
      required this.customer,
      required this.confirmLabel,
      required this.operation,
      this.destructive = false});
  final String title, body, confirmLabel;
  final BillingCustomer customer;
  final Future<void> Function() operation;
  final bool destructive;
  @override
  State<_OperationDialog> createState() => _OperationDialogState();
}

class _OperationDialogState extends State<_OperationDialog> {
  bool loading = false;
  String? error;
  Future<void> confirm() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.operation();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'No se pudo completar la operación. Inténtalo nuevamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(widget.body),
                const SizedBox(height: 16),
                const Text('Cliente:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(widget.customer.name),
                const SizedBox(height: 8),
                const Text('Nombre comercial:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(widget.customer.commercialName.isEmpty
                    ? 'Sin nombre comercial'
                    : widget.customer.commercialName),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
                ]
              ])),
          actions: [
            TextButton(
                autofocus: true,
                onPressed: loading ? null : () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                style: widget.destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error)
                    : null,
                onPressed: loading ? null : confirm,
                child: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.confirmLabel))
          ]);
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard(
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
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: LayoutBuilder(builder: (_, box) {
            final compact = box.maxWidth < 1100, mobile = box.maxWidth < 620;
            final name = _CustomerField(label: 'Cliente', value: customer.name);
            final commercial = _CustomerField(
                label: 'Nombre comercial',
                value: customer.commercialName.isEmpty
                    ? 'Sin nombre comercial'
                    : customer.commercialName);
            final badge = _StatusBadge(customer: customer);
            final actions = _Actions(
                customer: customer,
                compact: compact,
                busy: busy,
                onEdit: busy ? null : onEdit,
                onSchedule: busy ? null : onSchedule,
                onDelete: busy ? null : onDelete);
            if (mobile) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    name,
                    const SizedBox(height: 8),
                    commercial,
                    const SizedBox(height: 8),
                    Row(children: [badge, const Spacer(), actions])
                  ]);
            }
            return Row(children: [
              Expanded(flex: 31, child: name),
              const SizedBox(width: 14),
              Expanded(flex: 29, child: commercial),
              const SizedBox(width: 14),
              Expanded(
                  flex: 17,
                  child: Align(alignment: Alignment.centerLeft, child: badge)),
              Expanded(
                  flex: 23,
                  child:
                      Align(alignment: Alignment.centerRight, child: actions))
            ]);
          })));
}

class _Actions extends StatelessWidget {
  const _Actions(
      {required this.customer,
      required this.compact,
      required this.busy,
      required this.onEdit,
      required this.onSchedule,
      required this.onDelete});
  final BillingCustomer customer;
  final bool compact, busy;
  final VoidCallback? onEdit, onSchedule, onDelete;
  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox.square(
          dimension: 24, child: CircularProgressIndicator(strokeWidth: 2));
    }
    final identity =
        '${customer.name}, ${customer.commercialName.isEmpty ? 'sin nombre comercial' : customer.commercialName}';
    Widget action(String tooltip, String semantic, IconData icon,
            VoidCallback? callback, [Color? color]) =>
        Semantics(
            label: semantic,
            button: true,
            enabled: callback != null,
            child: IconButton(
                tooltip: tooltip,
                onPressed: callback,
                color: color,
                icon: Icon(icon),
                constraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44)));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      action('Editar cliente', 'Editar cliente $identity', Icons.edit_outlined,
          onEdit),
      action(
          customer.configured
              ? 'Programar facturas pendientes'
              : 'Configura primero los días de pago',
          'Programar facturas pendientes de $identity',
          Icons.event_repeat_outlined,
          onSchedule,
          Theme.of(context).colorScheme.primary),
      if (!compact) const Text('Programar'),
      action('Eliminar cliente', 'Eliminar cliente $identity',
          Icons.delete_outline, onDelete, Theme.of(context).colorScheme.error)
    ]);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.customer});
  final BillingCustomer customer;
  @override
  Widget build(BuildContext context) {
    final color = customer.configured ? Colors.green : Colors.amber;
    final text =
        customer.configured ? '${customer.paymentTermDays} días' : 'Pendiente';
    return Semantics(
        label: 'Días configurados: $text',
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withValues(alpha: .45))),
            child: Text(text,
                style: TextStyle(
                    color: color.shade200, fontWeight: FontWeight.w600))));
  }
}

class _CustomerField extends StatelessWidget {
  const _CustomerField({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Tooltip(
      message: value,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600))
          ]));
}
