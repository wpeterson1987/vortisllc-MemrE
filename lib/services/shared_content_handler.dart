import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import '../screens/memo_input_screen.dart';
import '../screens/login_screen.dart';
import '../models/memo_models.dart';
import '../services/auth_service.dart';
import '../screens/memo_screen.dart';
import 'package:path/path.dart' as path;

class SharedContentHandler {
  static const platform = MethodChannel('com.vortisllc.memre/share');

  static Future<void> handleIncomingShares(BuildContext context) async {
    print("\n========== HANDLING INCOMING SHARES ==========");
    print("Starting handleIncomingShares");
    final authService = AuthService();
    final userId = await authService.getLoggedInUserId();
    print("Current userId: $userId");

    if (userId == null) {
      print("User ID is null, cannot handle shares");
      return;
    }

    try {
      print("Attempting to get shared data from platform channel");
      final Map<String, dynamic>? sharedData =
          await platform.invokeMapMethod<String, dynamic>('getSharedData');

      print("\nReceived shared data details:");
      print("Full shared data: $sharedData");
      print("Type: ${sharedData?['type']}");

      if (sharedData?['content'] != null) {
        if (sharedData!['content'] is List) {
          print(
              "Content length: ${(sharedData['content'] as List).length} bytes");
        } else {
          print("Content type: ${sharedData['content'].runtimeType}");
          if (sharedData['content'] is String) {
            final content = sharedData['content'] as String;
            final previewLength = math.min(100, content.length);
            print("Content preview: ${content.substring(0, previewLength)}...");
          }
        }
      } else {
        print("Content is null");
      }
      print("File name: ${sharedData?['fileName']}");
      print("MIME type: ${sharedData?['mimeType']}");

      if (sharedData != null) {
        print("\nProcessing shared data...");
        await _processSharedData(context, sharedData, userId);
      } else {
        print("Shared data is null - nothing to process");
      }
    } catch (e, stackTrace) {
      print('\nError handling shared data:');
      print('Error: $e');
      print('Stack trace: $stackTrace');
    }
    print("========== SHARE HANDLING COMPLETE ==========\n");
  }

  static Future<void> _processSharedData(
    BuildContext context,
    Map<String, dynamic> sharedData,
    int userId,
  ) async {
    try {
      final String? type = sharedData['type'];
      print('Processing shared content of type: $type');

      dynamic content;
      String? fileName;
      AttachmentType? attachmentType;

      if (type == 'text') {
        content = sharedData['content'];
        print('Text content: $content');
      } else if (type == 'image' || type == 'video' || type == 'file') {
        // Handle file content
        final List<dynamic>? bytes = sharedData['content'];
        fileName = sharedData['fileName'] ?? 'shared_file';
        final String? mimeType = sharedData['mimeType'];

        print('Processing file: $fileName');
        print('MIME type: $mimeType');
        print('Bytes received: ${bytes?.length}');

        if (bytes != null && bytes.isNotEmpty) {
          // Convert List<dynamic> to Uint8List
          try {
            content = Uint8List.fromList(bytes.cast<int>());
            print(
                'Successfully converted to Uint8List: ${content.length} bytes');
          } catch (e) {
            print('Error converting bytes: $e');
            // Fallback conversion
            content = Uint8List.fromList(bytes.map((b) => b as int).toList());
            print('Fallback conversion successful: ${content.length} bytes');
          }

          // Determine attachment type
          if (type == 'image' || mimeType?.startsWith('image/') == true) {
            attachmentType = AttachmentType.image;
          } else if (type == 'video' ||
              mimeType?.startsWith('video/') == true) {
            attachmentType = AttachmentType.video;
          } else {
            attachmentType = AttachmentType.document;
          }

          print('Determined attachment type: $attachmentType');
        } else {
          print('No file bytes received');
          return;
        }
      }

      if (content != null && context.mounted) {
        print('Navigating to MemoInputScreen with:');
        print('Content type: ${content.runtimeType}');
        print('File name: $fileName');
        print('Attachment type: $attachmentType');

        // Show confirmation dialog first
        bool? shouldCreate = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Create New MemrE'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create a new MemrE with the shared content?'),
                SizedBox(height: 12),
                if (fileName != null) ...[
                  Row(
                    children: [
                      Icon(Icons.attach_file, size: 16),
                      SizedBox(width: 4),
                      Expanded(child: Text('File: $fileName')),
                    ],
                  ),
                  SizedBox(height: 4),
                ],
                if (content is String) ...[
                  Row(
                    children: [
                      Icon(Icons.text_fields, size: 16),
                      SizedBox(width: 4),
                      Text('Text content included'),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Create MemrE'),
              ),
            ],
          ),
        );

        if (shouldCreate == true) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MemoInputScreen(
                userId: userId,
                sharedContent: content,
                attachmentFileName: fileName,
                attachmentType: attachmentType,
                fromSharedContent: true,
              ),
            ),
          );
        }
      } else {
        print('No content to share or context not mounted');
      }
    } catch (e, stackTrace) {
      print('Error processing shared data: $e');
      print('Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error handling shared content: $e')),
        );
      }
    }
  }
}
