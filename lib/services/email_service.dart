import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import '../models/memo_models.dart';

class EmailService {
  final String _senderName;
  final String _username;

  EmailService({
    String? username,
    String? senderName,
  })  : _username = username ?? 'MemrE App',
        _senderName = senderName ?? 'MemrE App';

  // NEW: Send to multiple recipients in one email
  Future<bool> sendEmailToMultipleRecipients({
    required List<String> recipients,
    required String subject,
    required String body,
    Uint8List? attachmentData,
    String? attachmentFileName,
    AttachmentType? attachmentType,
  }) async {
    try {
      print('=== SENDING EMAIL TO MULTIPLE RECIPIENTS ===');
      print('Recipients: ${recipients.join(", ")}');
      print('Subject: $subject');
      
      List<String> attachments = [];
      Directory? tempDir;

      // Handle attachment if present
      if (attachmentData != null && attachmentFileName != null) {
        try {
          // Get the app's documents directory
          tempDir = await getApplicationDocumentsDirectory();

          // Create a unique filename
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final uniqueFileName = '${timestamp}_$attachmentFileName';
          final filePath = path.join(tempDir.path, uniqueFileName);

          // Write the file
          final file = File(filePath);
          await file.writeAsBytes(attachmentData);

          // Verify the file exists and is readable
          if (await file.exists()) {
            final fileSize = await file.length();
            print('File created successfully. Size: $fileSize bytes');
            print('File path: $filePath');
            attachments.add(filePath);
          } else {
            print('Failed to create file at $filePath');
            return false;
          }
        } catch (e) {
          print('Error handling attachment: $e');
          return false;
        }
      }

      // Prepare email with ALL recipients
      final Email email = Email(
        body: body,
        subject: subject,
        recipients: recipients, // Send to ALL recipients at once
        attachmentPaths: attachments,
        isHTML: false,
      );

      // Launch email client
      print('Launching email client with ${recipients.length} recipients and ${attachments.length} attachments');
      await FlutterEmailSender.send(email);

      return true;
    } catch (e) {
      print('Error sending email to multiple recipients: $e');
      return false;
    }
  }

  // ORIGINAL: Single recipient method (keep for compatibility)
  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String body,
    Uint8List? attachmentData,
    String? attachmentFileName,
    AttachmentType? attachmentType,
  }) async {
    try {
      List<String> attachments = [];
      Directory? tempDir;

      // Handle attachment if present
      if (attachmentData != null && attachmentFileName != null) {
        try {
          // Get the app's documents directory instead of temporary directory
          tempDir = await getApplicationDocumentsDirectory();

          // Create a unique filename
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final uniqueFileName = '${timestamp}_$attachmentFileName';
          final filePath = path.join(tempDir.path, uniqueFileName);

          // Write the file
          final file = File(filePath);
          await file.writeAsBytes(attachmentData);

          // Verify the file exists and is readable
          if (await file.exists()) {
            final fileSize = await file.length();
            print('File created successfully. Size: $fileSize bytes');
            print('File path: $filePath');
            attachments.add(filePath);
          } else {
            print('Failed to create file at $filePath');
            return false;
          }
        } catch (e) {
          print('Error handling attachment: $e');
          return false;
        }
      }

      // Prepare email
      final Email email = Email(
        body: body,
        subject: subject,
        recipients: [to],
        attachmentPaths: attachments,
        isHTML: false,
      );

      // Launch email client
      print('Launching email client with ${attachments.length} attachments');
      await FlutterEmailSender.send(email);

      return true;
    } catch (e) {
      print('Error sending email: $e');
      if (e.toString().contains('attachment')) {
        print('Attachment-specific error: $e');
      }
      return false;
    }
  }

  // NEW: Sequential email sending (fallback option)
  Future<Map<String, bool>> sendEmailToRecipientsSequentially({
    required List<String> recipients,
    required String subject,
    required String body,
    Uint8List? attachmentData,
    String? attachmentFileName,
    AttachmentType? attachmentType,
  }) async {
    Map<String, bool> results = {};
    
    print('=== SENDING EMAILS SEQUENTIALLY ===');
    print('Recipients: ${recipients.length}');
    
    for (int i = 0; i < recipients.length; i++) {
      final recipient = recipients[i];
      print('📧 Sending email ${i + 1} of ${recipients.length} to: $recipient');
      
      try {
        final success = await sendEmail(
          to: recipient,
          subject: subject,
          body: body,
          attachmentData: attachmentData,
          attachmentFileName: attachmentFileName,
          attachmentType: attachmentType,
        );
        
        results[recipient] = success;
        
        if (success) {
          print('✅ Email sent successfully to: $recipient');
        } else {
          print('❌ Failed to send email to: $recipient');
        }
        
        // If not the last email, wait longer for user to send and return
        if (i < recipients.length - 1) {
          print('⏳ Please send the email and return to the app...');
          print('⏳ Waiting 8 seconds before opening next email...');
          await Future.delayed(Duration(seconds: 8));
        }
        
      } catch (e) {
        print('❌ Error sending email to $recipient: $e');
        results[recipient] = false;
      }
    }
    
    print('=== SEQUENTIAL EMAIL SENDING COMPLETE ===');
    results.forEach((recipient, success) {
      print('  $recipient: ${success ? "SUCCESS" : "FAILED"}');
    });
    
    return results;
  }

  // Call this method periodically to clean up old attachment files
  Future<void> cleanupOldAttachments() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync();

      // Delete files older than 24 hours
      final now = DateTime.now();
      for (var entity in files) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          // Check if this is one of our attachment files
          if (fileName.contains('_') && fileName.split('_').length > 1) {
            try {
              final timestamp = int.parse(fileName.split('_')[0]);
              final fileDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
              if (now.difference(fileDate).inHours > 24) {
                await entity.delete();
                print('Deleted old attachment: $fileName');
              }
            } catch (e) {
              print('Error parsing filename $fileName: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error cleaning up attachments: $e');
    }
  }
}