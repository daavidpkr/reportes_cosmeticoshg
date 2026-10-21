import 'package:flutter/material.dart';

import '../../models/catalog.dart';
import '../../theme/hg_theme.dart';

class FeaturedCatalogBanner extends StatelessWidget {
  const FeaturedCatalogBanner({
    required this.catalog,
    required this.mobile,
    required this.cover,
    required this.metadata,
    required this.onView,
    required this.onDownload,
    this.fileMessage,
    super.key,
  });

  final Catalog catalog;
  final bool mobile;
  final Widget cover;
  final String metadata;
  final String? fileMessage;
  final VoidCallback? onView;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) => Semantics(
        key: ValueKey('featured-${catalog.id}-v${catalog.version}'),
        label: 'Catálogo destacado: ${catalog.title}',
        child: Container(
          constraints: BoxConstraints(minHeight: mobile ? 190 : 255),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: Row(
                  children: List.generate(64, (index) {
                    final color = Color.lerp(
                          context.hg.burgundy,
                          context.hg.plum,
                          index / 63,
                        ) ??
                        context.hg.burgundy;
                    return Expanded(child: ColoredBox(color: color));
                  }),
                ),
              ),
              Row(children: [
                Expanded(flex: 4, child: cover),
                Expanded(flex: mobile ? 6 : 7, child: _text()),
              ]),
            ],
          ),
        ),
      );

  Widget _text() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'DESTACADO',
              style: TextStyle(
                color: Color(0xFFF1D487),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              catalog.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(metadata, style: const TextStyle(color: Colors.white70)),
            if (fileMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                fileMessage!,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: onView,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Ver'),
              ),
              IconButton.filledTonal(
                tooltip: 'Descargar',
                onPressed: onDownload,
                icon: const Icon(Icons.download_outlined),
              ),
            ]),
          ],
        ),
      );
}
