import 'package:flutter/material.dart';

import '../services/android_update_controller.dart';

class UpdatesScreen extends StatefulWidget {
  UpdatesScreen({
    super.key,
    AndroidUpdateController? controller,
  }) : controller = controller ?? AndroidUpdateController.instance;

  final AndroidUpdateController controller;

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.start();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final update = controller.manifest;
    final installed = controller.installed;
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              update != null &&
                                      installed != null &&
                                      update.isMandatoryFor(installed)
                                  ? Icons.system_update_alt
                                  : Icons.system_update_outlined,
                              size: 42,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    update?.title ??
                                        'Actualizaciones de Android',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(_statusText(controller)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (installed != null)
                          Text(
                              'Instalada: ${installed.version} (${installed.build})'),
                        if (update != null) ...[
                          const SizedBox(height: 6),
                          Text(
                              'Disponible: ${update.version} (${update.build})'),
                          const SizedBox(height: 16),
                          Text(update.description),
                          const SizedBox(height: 12),
                          Chip(
                            avatar: Icon(
                              installed != null &&
                                      update.isMandatoryFor(installed)
                                  ? Icons.lock_outline
                                  : Icons.schedule,
                              size: 18,
                            ),
                            label: Text(installed != null &&
                                    update.isMandatoryFor(installed)
                                ? 'Actualización obligatoria'
                                : 'Actualización opcional para esta versión'),
                          ),
                        ],
                        if (controller.status ==
                            AndroidUpdateStatus.downloading) ...[
                          const SizedBox(height: 20),
                          LinearProgressIndicator(value: controller.progress),
                          const SizedBox(height: 8),
                          Text(
                              '${(controller.progress * 100).toStringAsFixed(0)} %'),
                        ],
                        if (controller.message != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            controller.message!,
                            style: TextStyle(
                              color:
                                  controller.status == AndroidUpdateStatus.error
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        _actions(context, controller),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'La descarga se acepta únicamente desde la última GitHub Release pública. '
                  'Antes de instalar se verifican tamaño, SHA-256, paquete, build y firma.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, AndroidUpdateController controller) {
    switch (controller.status) {
      case AndroidUpdateStatus.checking:
        return const Center(child: CircularProgressIndicator());
      case AndroidUpdateStatus.downloading:
        return OutlinedButton.icon(
          onPressed: controller.cancel,
          icon: const Icon(Icons.close),
          label: const Text('Cancelar descarga'),
        );
      case AndroidUpdateStatus.ready:
        return const LinearProgressIndicator();
      case AndroidUpdateStatus.permissionNeeded:
        return FilledButton.icon(
          onPressed: controller.install,
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Ya autoricé, continuar'),
        );
      case AndroidUpdateStatus.available:
      case AndroidUpdateStatus.cancelled:
        return FilledButton.icon(
          onPressed: controller.download,
          icon: const Icon(Icons.download),
          label: const Text('Descargar ahora'),
        );
      case AndroidUpdateStatus.error:
        final installed = controller.installed;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: installed != null &&
                      controller.manifest?.isNewerThan(installed) == true
                  ? controller.download
                  : controller.check,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
            OutlinedButton(
              onPressed: controller.check,
              child: const Text('Consultar de nuevo'),
            ),
          ],
        );
      case AndroidUpdateStatus.current:
      case AndroidUpdateStatus.idle:
        return OutlinedButton.icon(
          onPressed: controller.check,
          icon: const Icon(Icons.refresh),
          label: const Text('Buscar actualizaciones'),
        );
    }
  }

  String _statusText(AndroidUpdateController controller) =>
      switch (controller.status) {
        AndroidUpdateStatus.idle => 'Sin consultar',
        AndroidUpdateStatus.checking => 'Consultando la última release…',
        AndroidUpdateStatus.current => 'La aplicación está actualizada',
        AndroidUpdateStatus.available => 'Hay una actualización disponible',
        AndroidUpdateStatus.downloading => 'Descargando y verificando…',
        AndroidUpdateStatus.ready => 'Lista para instalar',
        AndroidUpdateStatus.permissionNeeded => 'Falta autorización de Android',
        AndroidUpdateStatus.cancelled => 'Descarga cancelada',
        AndroidUpdateStatus.error => 'No se pudo completar la operación',
      };
}
