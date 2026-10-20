import 'dart:typed_data';

import 'package:flutter/material.dart';

Widget catalogCoverImage(Uint8List bytes) => Image.memory(
      bytes,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
