import 'package:flutter/material.dart';

import '../models/fila_venta.dart';

enum PaymentEditorAction { save, delete }

class PaymentEditorResult {
  const PaymentEditorResult.save(this.payment)
      : action = PaymentEditorAction.save;

  const PaymentEditorResult.delete()
      : action = PaymentEditorAction.delete,
        payment = null;

  final PaymentEditorAction action;
  final Abono? payment;
}

Future<PaymentEditorResult?> showPaymentEditorDialog({
  required BuildContext context,
  required String title,
  required Abono initialPayment,
  required double availableBalance,
  bool initialFullPayment = false,
  bool lockFullPayment = false,
  bool fullPaymentEnabled = true,
  bool allowDelete = false,
  String invoiceLabel = '',
  String deleteSemanticLabel = 'Eliminar pago',
}) async {
  final amountController = TextEditingController(
    text: initialPayment.valor == 0
        ? ''
        : initialPayment.valor.toStringAsFixed(2),
  );
  final receiptController = TextEditingController(
    text: initialPayment.numeroRecibo?.toString() ?? '',
  );
  final commentController = TextEditingController(
    text: initialPayment.comentario,
  );
  final formKey = GlobalKey<FormState>();
  var fullPayment = initialFullPayment || lockFullPayment;
  var manualValue = amountController.text;
  if (fullPayment && availableBalance > .005) {
    amountController.text = availableBalance.toStringAsFixed(2);
  }

  final result = await showDialog<PaymentEditorResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('payment-amount'),
                  controller: amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  readOnly: fullPayment,
                  decoration: const InputDecoration(
                    labelText: 'Valor',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => validarValorAbono(value ?? ''),
                ),
                CheckboxListTile(
                  key: const ValueKey('full-payment-checkbox'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pago completo'),
                  value: fullPayment,
                  onChanged: lockFullPayment ||
                          !fullPaymentEnabled ||
                          availableBalance <= .005
                      ? null
                      : (value) => update(() {
                            fullPayment = value ?? false;
                            if (fullPayment) {
                              manualValue = amountController.text;
                              amountController.text =
                                  availableBalance.toStringAsFixed(2);
                            } else {
                              amountController.text = manualValue;
                            }
                          }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('payment-receipt'),
                  controller: receiptController,
                  keyboardType: TextInputType.number,
                  validator: (value) => validarNumeroRecibo(value ?? ''),
                  decoration: const InputDecoration(
                    labelText: 'Número de recibo (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('payment-comment'),
                  controller: commentController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Comentario',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          if (allowDelete && initialPayment.valor > 0)
            Semantics(
              label: deleteSemanticLabel,
              button: true,
              child: Tooltip(
                message: 'Eliminar abono',
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        title: const Text('Eliminar abono'),
                        content: Text(
                          'Se eliminará el abono de '
                          '\$${initialPayment.valor.toStringAsFixed(2)}'
                          '${invoiceLabel.trim().isEmpty ? '' : ' de la factura $invoiceLabel'}.\n\n'
                          'El saldo pendiente aumentará nuevamente y los '
                          'totales de cobros serán recalculados.\n\n'
                          '¿Deseas continuar?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Volver'),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Eliminar abono'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      Navigator.pop(
                        context,
                        const PaymentEditorResult.delete(),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar abono'),
                ),
              ),
            ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(
                context,
                PaymentEditorResult.save(
                  Abono(
                    valor: double.tryParse(
                          amountController.text.replaceAll(',', '.'),
                        ) ??
                        0,
                    numeroRecibo: receiptController.text.trim().isEmpty
                        ? null
                        : int.parse(receiptController.text.trim()),
                    comentario: commentController.text.trim(),
                  ),
                ),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );

  await Future<void>.delayed(kThemeAnimationDuration);
  amountController.dispose();
  receiptController.dispose();
  commentController.dispose();
  return result;
}
