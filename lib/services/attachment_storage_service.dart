import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/memo_models.dart';

class AttachmentStorageService {
  // Store attachment data for notification use
  static Future<String?> storeAttachmentForNotification({
    required Uint8List attachmentData,
    required String fileName,
    required int memoId,
    required int notificationId,
  }) async {
    try {
      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();

      // Create a subdirectory for notification attachments
      final attachmentsDir =
          Directory(path.join(directory.path, 'notification_attachments'));
      if (!await attachmentsDir.exists()) {
        await attachmentsDir.create(recursive: true);
      }

      // Create unique filename with memo and notification IDs
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(fileName);
      final uniqueFileName =
          '${memoId}_${notificationId}_${timestamp}$extension';
      final filePath = path.join(attachmentsDir.path, uniqueFileName);

      // Write the file
      final file = File(filePath);
      await file.writeAsBytes(attachmentData);

      // Verify the file was created
      if (await file.exists()) {
        final fileSize = await file.length();
        print('✅ Attachment stored: $filePath (${fileSize} bytes)');
        return filePath;
      } else {
        print('❌ Failed to store attachment');
        return null;
      }
    } catch (e) {
      print('❌ Error storing attachment: $e');
      return null;
    }
  }

  // Load attachment data from stored file
  static Future<Uint8List?> loadAttachmentFromPath(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final data = await file.readAsBytes();
        print('✅ Attachment loaded: $filePath (${data.length} bytes)');
        return data;
      } else {
        print('❌ Attachment file not found: $filePath');
        return null;
      }
    } catch (e) {
      print('❌ Error loading attachment: $e');
      return null;
    }
  }

  // Clean up old attachment files (call periodically)
  static Future<void> cleanupOldAttachments({int daysOld = 7}) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final attachmentsDir =
          Directory(path.join(directory.path, 'notification_attachments'));

      if (!await attachmentsDir.exists()) {
        return;
      }

      final files = attachmentsDir.listSync();
      final now = DateTime.now();

      for (var entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          final fileAge = now.difference(stat.modified);

          if (fileAge.inDays > daysOld) {
            try {
              await entity.delete();
              print(
                  '🗑️ Cleaned up old attachment: ${path.basename(entity.path)}');
            } catch (e) {
              print('❌ Error deleting old attachment: $e');
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error during cleanup: $e');
    }
  }

  // Delete specific attachment file
  static Future<bool> deleteAttachment(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        print('🗑️ Deleted attachment: $filePath');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error deleting attachment: $e');
      return false;
    }
  }

  // Get attachment type from file extension
  static AttachmentType getAttachmentTypeFromPath(String filePath) {
    final extension = path.extension(filePath).toLowerCase();

    switch (extension) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.bmp':
      case '.webp':
        return AttachmentType.image;

      case '.mp4':
      case '.avi':
      case '.mov':
      case '.wmv':
      case '.flv':
      case '.webm':
        return AttachmentType.video;

      case '.pdf':
      case '.doc':
      case '.docx':
      case '.txt':
      case '.rtf':
      default:
        return AttachmentType.document;
    }
  }
}
