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
    setState(() => _customers = future);
    await future;
  }

  Future<void> _edit(BillingCustomer customer) async {
    final controller =
        TextEditingController(text: customer.paymentTermDays?.toString() ?? '');
    final days = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(customer.name),
              content: TextField(
                controller: controller,
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
                      final parsed = parsePaymentTerm(controller.text);
                      if (parsed != null) Navigator.pop(context, parsed);
                    },
                    child: const Text('Continuar')),
              ],
            ));
    controller.dispose();
    if (days == null || !mounted) return;
    final impacted = await _repository.previewImpact(customer.id, days);
    if (!mounted) return;
    var apply = false;
    if (impacted > 0) {
      apply = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                    title: const Text('Facturas pendientes'),
                    content: Text(
                        '$impacted facturas activas sin recordatorio podrían recibir una fecha. ¿Deseas aplicarlo ahora?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Solo guardar plazo')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Aplicar y crear fechas')),
                    ],
                  )) ??
          false;
    }
    await _repository.savePaymentTerm(customer.id, days, applyExisting: apply);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apply
            ? 'Plazo guardado y $impacted facturas actualizadas.'
            : 'Plazo habitual guardado.')));
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
                return Card(
                  child: ListTile(
                    leading: Icon(customer.configured
                        ? Icons.check_circle_outline
                        : Icons.pending_outlined),
                    title: Text(customer.name),
                    subtitle: Text([
                      if (customer.commercialName.isNotEmpty)
                        customer.commercialName,
                      customer.configured
                          ? '${customer.paymentTermDays} días · Configurado'
                          : 'Plazo pendiente de configurar · Pendiente',
                    ].join('\n')),
                    trailing: IconButton(
                        tooltip: 'Editar y guardar',
                        onPressed: () => _edit(customer),
                        icon: const Icon(Icons.edit_outlined)),
                  ),
                );
              },
            );
          },
        ),
      );
}
