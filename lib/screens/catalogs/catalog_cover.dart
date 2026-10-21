import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/catalog.dart';
import '../../theme/hg_theme.dart';

class CatalogCover extends StatelessWidget {
  const CatalogCover({
    required this.catalog,
    required this.bytes,
    super.key,
  });

  final Catalog catalog;
  final Future<Uint8List?> bytes;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        key: ValueKey(
          'catalog-list-cover-${catalog.id}-v${catalog.version}',
        ),
        child: FutureBuilder<Uint8List?>(
          future: bytes,
          builder: (_, snapshot) {
            final imageBytes = snapshot.data;
            if (imageBytes == null) return _placeholder(context);
            return Image.memory(
              imageBytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _placeholder(context),
            );
          },
        ),
      );

  Widget _placeholder(BuildContext context) => ColoredBox(
        key: const Key('cover-placeholder'),
        color: context.hg.tableHeader,
        child: Center(
          child: Icon(
            Icons.auto_stories_outlined,
            size: 56,
            color: context.hg.mutedText,
          ),
        ),
      );
}
