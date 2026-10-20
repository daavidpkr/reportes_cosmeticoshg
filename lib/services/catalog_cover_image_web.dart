import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget catalogCoverImage(Uint8List bytes) {
  final type = bytes.length > 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47
      ? 'image/png'
      : 'image/webp';
  final source = 'data:$type;base64,${base64Encode(bytes)}';
  return HtmlElementView.fromTagName(
    tagName: 'img',
    onElementCreated: (element) {
      final image = element as web.HTMLImageElement;
      image
        ..src = source
        ..alt = '';
      image.style
        ..width = '100%'
        ..height = '100%'
        ..objectFit = 'cover'
        ..display = 'block';
    },
  );
}
