import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../services/email_service.dart';
import '../services/attachment_storage_service.dart';
import '../models/memo_models.dart';

class PlatformSMSService {
  static const MethodChannel _channel =
      MethodChannel('com.vortisllc.memre/sms');

  static Future<bool> canSendSMS() async {
    try {
      final bool result = await _channel.invokeMethod('canSendSMS');
      return result;
    } on PlatformException catch (e) {
      print('Error checking SMS capability: $e');
      return false;
    } on MissingPluginException catch (e) {
      print('SMS plugin not implemented: $e');
      return false;
    }
  }

  // FIXED: Updated method signature to match your existing calls
  static Future<bool> sendSMS({
    List<String>? recipients,
    String? to, // For single recipient calls
    required String message,
  }) async {
    // Handle both single recipient and multiple recipients
    List<String> finalRecipients = [];
    if (recipients != null && recipients.isNotEmpty) {
      finalRecipients = recipients;
    } else if (to != null && to.isNotEmpty) {
      finalRecipients = [to];
    } else {
      print('No recipients provided for SMS');
      return false;
    }

    try {
      // Check if we can send SMS via platform channel
      if (await canSendSMS()) {
        final bool result = await _channel.invokeMethod('sendSMS', {
          'recipients': finalRecipients,
          'message': message,
        });
        return result;
      } else {
        // Fallback to URL scheme
        return await _sendSMSViaURL(finalRecipients, message);
      }
    } on PlatformException catch (e) {
      print('Platform SMS error: $e');
      return await _sendSMSViaURL(finalRecipients, message);
    } on MissingPluginException catch (e) {
      print('SMS plugin missing, using URL fallback: $e');
      return await _sendSMSViaURL(finalRecipients, message);
    } catch (e) {
      print('Unexpected SMS error: $e');
      return await _sendSMSViaURL(finalRecipients, message);
    }
  }

  static Future<bool> _sendSMSViaURL(List<String> recipients, String message) async {
    try {
      // Use URL scheme as fallback
      final String recipientString = recipients.join(',');
      final String encodedMessage = Uri.encodeComponent(message);
      final String smsUrl = 'sms:$recipientString?body=$encodedMessage';
      
      final Uri uri = Uri.parse(smsUrl);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return true;
      } else {
        print('Cannot launch SMS URL: $smsUrl');
        return false;
      }
    } catch (e) {
      print('Error sending SMS via URL: $e');
      return false;
    }
  }

  // IMPROVED bulk SMS with better user experience
  static Future<Map<String, bool>> sendBulkSMS({
    required List<String> recipients,
    required String message,
  }) async {
    final results = <String, bool>{};

    if (recipients.isEmpty) {
      print('No recipients provided for bulk SMS');
      return results;
    }

    print('=== BULK SMS START ===');
    print('Recipients: ${recipients.length}');

    // If only one recipient, send immediately
    if (recipients.length == 1) {
      bool success = await sendSMS(to: recipients[0], message: message);
      results[recipients[0]] = success;
      print('Single SMS result: $success');
      return results;
    }

    // For multiple recipients, use a more reliable approach
    for (int i = 0; i < recipients.length; i++) {
      String recipient = recipients[i];

      print('=== SMS ${i + 1} of ${recipients.length} ===');
      print('Recipient: $recipient');

      try {
        // Send the SMS
        bool success = await sendSMS(to: recipient, message: message);
        results[recipient] = success;

        if (success) {
          print('✅ SMS app opened successfully for: $recipient');
        } else {
          print('❌ Failed to open SMS app for: $recipient');
        }

        // If this is not the last recipient, show a helpful message and wait
        if (i < recipients.length - 1) {
          print('📱 PLEASE SEND THE SMS MESSAGE AND RETURN TO THIS APP');
          print(
              '⏳ Waiting 10 seconds before opening SMS for next recipient...');
          print('   Next recipient: ${recipients[i + 1]}');

          // Longer delay to ensure user has time to send first SMS
          await Future.delayed(Duration(seconds: 10));
        }
      } catch (e) {
        print('❌ Error sending to $recipient: $e');
        results[recipient] = false;
      }
    }

    print('=== BULK SMS COMPLETE ===');
    print('Final results:');
    results.forEach((phone, success) {
      print('  $phone: ${success ? "SUCCESS" : "FAILED"}');
    });

    return results;
  }

  // Alternative approach - queue-based SMS for better reliability
  static Future<Map<String, bool>> sendBulkSMSWithQueue({
    required List<String> recipients,
    required String message,
  }) async {
    final results = <String, bool>{};

    if (recipients.isEmpty) {
      print('No recipients provided for queued bulk SMS');
      return results;
    }

    print('=== QUEUED BULK SMS START ===');
    print('Recipients: ${recipients.length}');

    // Save the SMS queue to SharedPreferences for persistence
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sms_queue_recipients', recipients);
    await prefs.setString('sms_queue_message', message);
    await prefs.setInt('sms_queue_current_index', 0);
    await prefs.setBool('sms_queue_active', true);

    // Start processing the queue
    return await _processSMSQueue();
  }

  // SMART QUEUE METHODS:

  // Smart queue approach that's more user-friendly
  static Future<Map<String, bool>> sendBulkSMSWithSmartQueue({
    required List<String> recipients,
    required String message,
  }) async {
    final results = <String, bool>{};

    if (recipients.isEmpty) {
      print('No recipients provided for smart queue SMS');
      return results;
    }

    print('=== SMART QUEUE SMS START ===');
    print('Recipients: ${recipients.length}');

    // Process first SMS immediately
    if (recipients.isNotEmpty) {
      final firstRecipient = recipients[0];
      print('📱 Opening SMS for recipient 1 of ${recipients.length}: $firstRecipient');
      
      final success = await sendSMS(to: firstRecipient, message: message);
      results[firstRecipient] = success;
      
      if (success) {
        print('✅ First SMS opened successfully');
      } else {
        print('❌ First SMS failed to open');
      }
    }

    // If there are more recipients, save them to the queue for later processing
    if (recipients.length > 1) {
      final remainingRecipients = recipients.sublist(1);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('sms_smart_queue_recipients', remainingRecipients);
      await prefs.setString('sms_smart_queue_message', message);
      await prefs.setInt('sms_smart_queue_current_index', 0);
      await prefs.setBool('sms_smart_queue_active', true);
      
      print('📱 Queued ${remainingRecipients.length} additional SMS messages');
      print('📱 They will be processed when you return to the app after sending the current SMS');
      
      // Mark remaining recipients as queued
      for (final recipient in remainingRecipients) {
        results[recipient] = true; // Mark as "processed" (queued)
      }
    }

    print('=== SMART QUEUE SMS INITIAL PROCESSING COMPLETE ===');
    return results;
  }

  // Process the next SMS in the smart queue WITH EMAIL HANDLING
  static Future<bool> processNextQueuedSMS() async {
    final prefs = await SharedPreferences.getInstance();
    
    final recipients = prefs.getStringList('sms_smart_queue_recipients') ?? [];
    final message = prefs.getString('sms_smart_queue_message') ?? '';
    final currentIndex = prefs.getInt('sms_smart_queue_current_index') ?? 0;
    final isActive = prefs.getBool('sms_smart_queue_active') ?? false;

    if (!isActive || recipients.isEmpty || currentIndex >= recipients.length) {
      print('No more SMS in smart queue');
      await _clearSmartSMSQueue();
      
      // Check if there are pending emails to process
      await _processPendingEmailsAfterSMS();
      return false;
    }

    final recipient = recipients[currentIndex];
    print('📱 Processing queued SMS ${currentIndex + 1} of ${recipients.length}: $recipient');

    final success = await sendSMS(to: recipient, message: message);
    
    // Update index for next SMS
    final nextIndex = currentIndex + 1;
    await prefs.setInt('sms_smart_queue_current_index', nextIndex);
    
    // Check if this was the last SMS
    if (nextIndex >= recipients.length) {
      print('✅ All queued SMS processed');
      await _clearSmartSMSQueue();
      
      // Process pending emails after all SMS are complete
      await _processPendingEmailsAfterSMS();
    } else {
      print('📱 ${recipients.length - nextIndex} SMS remaining in queue');
    }
    
    return success;
  }

  // Process pending emails after SMS queue is complete
  static Future<void> _processPendingEmailsAfterSMS() async {
  try {
    print('=== CHECKING FOR PENDING EMAILS AFTER SMS ===');
    
    final prefs = await SharedPreferences.getInstance();
    final pendingEmailsJson = prefs.getString('pending_emails_after_sms');
    
    print('Pending emails JSON: $pendingEmailsJson');
    
    if (pendingEmailsJson != null && pendingEmailsJson.isNotEmpty) {
      print('📧 Found pending emails, processing now...');
      
      // Clear the stored emails first
      await prefs.remove('pending_emails_after_sms');
      print('📧 Cleared stored email data');
      
      // Parse email data
      final emailData = Map<String, dynamic>.from(jsonDecode(pendingEmailsJson));
      print('📧 Parsed email data: $emailData');
      
      final emailAddressesJson = emailData['emailAddresses'] ?? '[]';
      print('📧 Email addresses JSON from storage: $emailAddressesJson');
      
      final List<dynamic> emailsList = jsonDecode(emailAddressesJson);
      final List<String> emailAddresses = emailsList.map((email) => email.toString()).toList();
      
      print('📧 Parsed email addresses: $emailAddresses');
      
      final description = emailData['description'] ?? 'Reminder';
      final memoContent = emailData['memoContent'] ?? '';
      final hasValidAttachment = emailData['hasValidAttachment'] ?? false;
      
      print('📧 Email details - Description: $description, Content: $memoContent, Has attachment: $hasValidAttachment');
      
      if (emailAddresses.isNotEmpty) {
        print('📧 Processing ${emailAddresses.length} pending emails');
        
        // Small delay before processing emails
        print('📧 Waiting 2 seconds before opening email client...');
        await Future.delayed(Duration(seconds: 2));
        
        // Load attachment if needed
        Uint8List? attachmentData;
        String? attachmentFileName;
        AttachmentType? attachmentType;
        
        if (hasValidAttachment) {
          final attachmentFilePath = emailData['attachmentFilePath'];
          attachmentFileName = emailData['attachmentFileName'];
          final attachmentTypeString = emailData['attachmentType'];
          
          print('📧 Loading attachment: $attachmentFilePath, $attachmentFileName, $attachmentTypeString');
          
          if (attachmentFilePath != null && attachmentFileName != null) {
            try {
              attachmentData = await AttachmentStorageService.loadAttachmentFromPath(attachmentFilePath);
              
              if (attachmentData != null) {
                print('📧 Attachment loaded successfully: ${attachmentData.length} bytes');
              
                if (attachmentTypeString != null) {
                  switch (attachmentTypeString) {
                    case 'AttachmentType.image':
                      attachmentType = AttachmentType.image;
                      break;
                    case 'AttachmentType.video':
                      attachmentType = AttachmentType.video;
                      break;
                    case 'AttachmentType.document':
                      attachmentType = AttachmentType.document;
                      break;
                    default:
                      attachmentType = AttachmentStorageService.getAttachmentTypeFromPath(attachmentFilePath);
                  }
                }
              } else {
                print('📧 Failed to load attachment data');
              }
            } catch (e) {
              print('❌ Error loading attachment for email: $e');
            }
          }
        }
        
        // Process emails
        print('📧 Creating email service and sending emails...');
        final emailService = EmailService();
        
        try {
          print('📧 Calling sendEmailToMultipleRecipients...');
          final success = await emailService.sendEmailToMultipleRecipients(
            recipients: emailAddresses,
            subject: 'MemrE Reminder: $description',
            body: 'Reminder for your MemrE:\n\n$description\n\n$memoContent',
            attachmentData: attachmentData,
            attachmentFileName: attachmentFileName,
            attachmentType: attachmentType,
          );
          
          if (success) {
            print('✅ Pending emails processed successfully');
          } else {
            print('❌ Failed to process pending emails');
          }
        } catch (e) {
          print('❌ Error processing pending emails: $e');
          print('Stack trace: ${StackTrace.current}');
        }
      } else {
        print('📧 No email addresses found in pending data');
      }
    } else {
      print('📧 No pending emails found after SMS completion');
    }
  } catch (e) {
    print('❌ Error in _processPendingEmailsAfterSMS: $e');
    print('Stack trace: ${StackTrace.current}');
  }
}

  // Get smart queue status
  static Future<Map<String, dynamic>> getSmartSMSQueueStatus() async {
    final prefs = await SharedPreferences.getInstance();

    return {
      'isActive': prefs.getBool('sms_smart_queue_active') ?? false,
      'recipients': prefs.getStringList('sms_smart_queue_recipients') ?? [],
      'currentIndex': prefs.getInt('sms_smart_queue_current_index') ?? 0,
      'message': prefs.getString('sms_smart_queue_message') ?? '',
    };
  }

  // Clear the smart SMS queue
  static Future<void> _clearSmartSMSQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sms_smart_queue_recipients');
    await prefs.remove('sms_smart_queue_message');
    await prefs.remove('sms_smart_queue_current_index');
    await prefs.remove('sms_smart_queue_active');
    print('Smart SMS queue cleared');
  }

  // ORIGINAL QUEUE METHODS:

  static Future<Map<String, bool>> _processSMSQueue() async {
    final results = <String, bool>{};
    final prefs = await SharedPreferences.getInstance();

    final recipients = prefs.getStringList('sms_queue_recipients') ?? [];
    final message = prefs.getString('sms_queue_message') ?? '';
    final currentIndex = prefs.getInt('sms_queue_current_index') ?? 0;
    final isActive = prefs.getBool('sms_queue_active') ?? false;

    if (!isActive || recipients.isEmpty || currentIndex >= recipients.length) {
      print('SMS queue complete or inactive');
      await _clearSMSQueue();
      return results;
    }

    print('Processing SMS queue from index $currentIndex');

    // Process only the current SMS in the queue
    if (currentIndex < recipients.length) {
      String recipient = recipients[currentIndex];

      print(
          'Processing SMS ${currentIndex + 1} of ${recipients.length} to: $recipient');

      bool success = await sendSMS(to: recipient, message: message);
      results[recipient] = success;

      // Update current index for next SMS
      await prefs.setInt('sms_queue_current_index', currentIndex + 1);

      // If there are more SMS to send, set a flag for the app to check when it resumes
      if (currentIndex + 1 < recipients.length) {
        print('More SMS remaining. Next will be processed when app resumes.');
      } else {
        print('All SMS in queue processed');
        await _clearSMSQueue();
      }
    }

    return results;
  }

  static Future<void> _clearSMSQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sms_queue_recipients');
    await prefs.remove('sms_queue_message');
    await prefs.remove('sms_queue_current_index');
    await prefs.remove('sms_queue_active');
    print('SMS queue cleared');
  }

  // Enhanced resume method that handles both queue types
  static Future<void> resumePendingSMS() async {
    print('=== RESUMING PENDING SMS ===');
    
    // Check for smart queue first
    final prefs = await SharedPreferences.getInstance();
    final smartQueueActive = prefs.getBool('sms_smart_queue_active') ?? false;
    
    if (smartQueueActive) {
      print('Found active smart SMS queue, processing next SMS...');
      await Future.delayed(Duration(milliseconds: 500)); // Small delay
      await processNextQueuedSMS();
      return;
    }
    
    // If no SMS queue, check for pending emails
    await _processPendingEmailsAfterSMS();
    
    // Fall back to original queue logic
    final isActive = prefs.getBool('sms_queue_active') ?? false;
    final recipients = prefs.getStringList('sms_queue_recipients');

    if (isActive && recipients != null && recipients.isNotEmpty) {
      print('Found active original SMS queue, processing...');
      await Future.delayed(Duration(milliseconds: 1000));
      await _processSMSQueue();
    } else {
      print('No active SMS queue found');
    }
  }

  // Helper method to get SMS queue status
  static Future<Map<String, dynamic>> getSMSQueueStatus() async {
    final prefs = await SharedPreferences.getInstance();

    return {
      'isActive': prefs.getBool('sms_queue_active') ?? false,
      'recipients': prefs.getStringList('sms_queue_recipients') ?? [],
      'currentIndex': prefs.getInt('sms_queue_current_index') ?? 0,
      'message': prefs.getString('sms_queue_message') ?? '',
    };
  }
}