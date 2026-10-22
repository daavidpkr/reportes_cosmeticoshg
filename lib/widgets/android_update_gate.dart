import 'package:flutter/material.dart';

import '../screens/updates_screen.dart';
import '../services/android_update_controller.dart';

class AndroidUpdateGate extends StatefulWidget {
  const AndroidUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  State<AndroidUpdateGate> createState() => _AndroidUpdateGateState();
}

class _AndroidUpdateGateState extends State<AndroidUpdateGate> {
  final _controller = AndroidUpdateController.instance;
  int? _offeredBuild;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _controller.start();
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final update = _controller.manifest;
    if (_controller.status == AndroidUpdateStatus.available &&
        update != null &&
        _controller.installed != null &&
        !update.isMandatoryFor(_controller.installed!) &&
        _offeredBuild != update.build) {
      _offeredBuild = update.build;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _offerOptional(update.build));
    }
  }

  Future<void> _offerOptional(int build) async {
    if (!mounted || _controller.manifest?.build != build) return;
    final now = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_controller.manifest!.title),
        content: Text(
          'Versión ${_controller.manifest!.version} '
          '(${_controller.manifest!.build})\n\n${_controller.manifest!.description}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Después'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ahora'),
          ),
        ],
      ),
    );
    if (now == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UpdatesScreen(controller: _controller),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.blocksNormalUse) return widget.child;
    return PopScope(
      canPop: false,
      child: UpdatesScreen(controller: _controller),
    );
  }
}
