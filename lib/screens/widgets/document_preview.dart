// lib/widgets/document_preview.dart
import 'package:flutter/material.dart';
import 'dart:typed_data';

class DocumentPreview extends StatelessWidget {
  final Uint8List documentBytes;
  final String fileName;

  const DocumentPreview({
    Key? key,
    required this.documentBytes,
    required this.fileName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(
            Icons.description,
            size: 64,
            color: Colors.blue[300],
          ),
          const SizedBox(height: 8),
          Text(
            fileName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'File size: ${(documentBytes.length / 1024).toStringAsFixed(2)} KB',
            style: TextStyle(color: Colors.grey[600]),
          ),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open in system viewer'),
            onPressed: () {
              // We can add system viewer integration later
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Document viewer will be added in a future update')),
              );
            },
          ),
        ],
      ),
    );
  }
}
