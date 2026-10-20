import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget catalogCoverImage(Uint8List bytes) => _WebCatalogCover(bytes: bytes);

class _WebCatalogCover extends StatefulWidget {
  const _WebCatalogCover({required this.bytes});

  final Uint8List bytes;

  @override
  State<_WebCatalogCover> createState() => _WebCatalogCoverState();
}

class _WebCatalogCoverState extends State<_WebCatalogCover> {
  late String _objectUrl;

  @override
  void initState() {
    super.initState();
    _objectUrl = _createObjectUrl(widget.bytes);
  }

  @override
  void didUpdateWidget(covariant _WebCatalogCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.bytes, widget.bytes)) return;
    web.URL.revokeObjectURL(_objectUrl);
    _objectUrl = _createObjectUrl(widget.bytes);
  }

  @override
  void dispose() {
    web.URL.revokeObjectURL(_objectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
        tagName: 'img',
        onElementCreated: (element) {
          final image = element as web.HTMLImageElement;
          image
            ..src = _objectUrl
            ..alt = '';
          image.style
            ..width = '100%'
            ..height = '100%'
            ..objectFit = 'cover'
            ..display = 'block';
        },
      );

  String _createObjectUrl(Uint8List bytes) {
    final type = bytes.length > 8 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47
        ? 'image/png'
        : 'image/webp';
    final blob = web.Blob(
      <JSUint8Array>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: type),
    );
    return web.URL.createObjectURL(blob);
  }
}
