import 'package:flutter/material.dart';

import '../services/vendedores_store.dart';
import '../theme/hg_theme.dart';

class VendedoresScreen extends StatelessWidget {
  const VendedoresScreen({required this.store, super.key});
  final VendedoresStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vendedores')),
        body: VendedoresContent(store: store),
      );
}

/// Contenido reutilizable de administración, sin Scaffold ni AppBar.
class VendedoresContent extends StatefulWidget {
  const VendedoresContent({required this.store, super.key});

  final VendedoresStore store;

  @override
  State<VendedoresContent> createState() => _VendedoresContentState();
}

class _VendedoresContentState extends State<VendedoresContent> {
  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final guardado = await widget.store.agregar(_codigo.text, _nombre.text);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (guardado) {
      _codigo.clear();
      _nombre.clear();
      setState(() {});
    } else {
      _mensaje('Ingresa código y nombre. No pueden estar repetidos.');
    }
  }

  Future<void> _editar(Vendedor vendedor) async {
    final codigo = TextEditingController(text: vendedor.codigo);
    final nombre = TextEditingController(text: vendedor.nombre);
    final datos = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar vendedor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codigo,
              decoration: const InputDecoration(labelText: 'Código'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nombre,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (codigo.text, nombre.text)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    codigo.dispose();
    nombre.dispose();
    if (datos == null) return;
    final guardado = await widget.store.editar(vendedor, datos.$1, datos.$2);
    if (!mounted) return;
    if (guardado) {
      setState(() {});
    } else {
      _mensaje('No se pudo editar. Revisa que los datos no estén repetidos.');
    }
  }

  Future<void> _eliminar(Vendedor vendedor) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar vendedor'),
        content: Text('¿Deseas eliminar a ${vendedor.nombre}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await widget.store.eliminar(vendedor);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) _mensaje('No se pudo eliminar el vendedor.');
    }
  }

  void _mensaje(String texto) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(texto)));

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Administración de vendedores',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _codigo,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Código del vendedor',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 320,
                        child: TextField(
                          controller: _nombre,
                          onSubmitted: (_) => _guardar(),
                          decoration: const InputDecoration(
                            labelText: 'Nombre del vendedor',
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _guardando ? null : _guardar,
                        icon: _guardando
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add),
                        label: const Text('Crear'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.store.vendedores.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Todavía no hay vendedores guardados.'),
                  ),
                )
              else
                ...widget.store.vendedores.map(
                  (vendedor) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(vendedor.codigo)),
                      title: Text(vendedor.nombre),
                      subtitle: Text('Código: ${vendedor.codigo}'),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Editar',
                            onPressed: () => _editar(vendedor),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Eliminar',
                            onPressed: () => _eliminar(vendedor),
                            icon: Icon(
                              Icons.delete_outline,
                              color: context.hg.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}
