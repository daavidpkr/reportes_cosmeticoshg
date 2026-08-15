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
  late Future<List<BillingCustomer>> _customers = _load();

  Future<List<BillingCustomer>> _load() => _repository.listCustomers();

  Future<void> _reload() async {
    final future = _repository.listCustomers();
    setState(() {
      _customers = future;
    });
    await future;
  }

  Future<void> _edit(BillingCustomer customer) async {
    final days = await showDialog<int>(
        context: context,
        builder: (context) => _PaymentTermDialog(customer: customer));
    if (days == null || !mounted) return;
    final impacted = await _repository.previewImpact(customer.id, days);
    if (!mounted) return;
    final scheduled = await _repository.savePaymentTerm(customer.id, days,
        applyExisting: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(impacted == 0
            ? 'Plazo habitual guardado.'
            : 'Plazo guardado y $scheduled facturas programadas.')));
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
                        onPressed: () => setState(() => _customers = _load()),
                        child: const Text('Reintentar')))
              ]);
            }
            final values = snapshot.data ?? const [];
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: values.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Clientes',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                  );
                }
                final customer = values[index - 1];
                return _CustomerCard(
                  customer: customer,
                  onEdit: () => _edit(customer),
                );
              },
            );
          },
        ),
      );
}

class _PaymentTermDialog extends StatefulWidget {
  const _PaymentTermDialog({required this.customer});

  final BillingCustomer customer;

  @override
  State<_PaymentTermDialog> createState() => _PaymentTermDialogState();
}

class _PaymentTermDialogState extends State<_PaymentTermDialog> {
  late final TextEditingController _controller = TextEditingController(
      text: widget.customer.paymentTermDays?.toString() ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.customer.name),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Plazo habitual en días',
            helperText: 'Usa 0 para pago el mismo día.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                final parsed = parsePaymentTerm(_controller.text);
                if (parsed != null) Navigator.pop(context, parsed);
              },
              child: const Text('Continuar')),
        ],
      );
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onEdit});

  final BillingCustomer customer;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                _CustomerField(label: 'Cliente', value: customer.name),
                _CustomerField(
                  label: 'Nombre comercial',
                  value: customer.commercialName.isEmpty
                      ? 'Sin nombre comercial'
                      : customer.commercialName,
                ),
                _CustomerField(
                  label: 'Días configurados',
                  value: customer.configured
                      ? '${customer.paymentTermDays} días'
                      : 'Pendiente',
                  statusColor: customer.configured
                      ? Colors.green.shade700
                      : Theme.of(context).colorScheme.error,
                ),
              ];

              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < fields.length; index++) ...[
                      fields[index],
                      if (index < fields.length - 1) const SizedBox(height: 10),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Editar y guardar',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: fields[0]),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: fields[1]),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: fields[2]),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Editar y guardar',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              );
            },
          ),
        ),
      );
}

class _CustomerField extends StatelessWidget {
  const _CustomerField({
    required this.label,
    required this.value,
    this.statusColor,
  });

  final String label;
  final String value;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      );
}
