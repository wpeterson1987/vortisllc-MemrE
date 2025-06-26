import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlatformSMSService {
  static const MethodChannel _channel =
      MethodChannel('com.vortisllc.memre/sms');

  static Future<bool> canSendSMS() async {
    try {
      final bool result = await _channel.invokeMethod('canSendSMS');
      return result;
    } on PlatformException catch (e) {
      print('Failed to check SMS capability: ${e.message}');
      return false;
    }
  }

  static Future<bool> sendSMS({
    required String to,
    required String message,
  }) async {
    try {
      print('=== PLATFORM SMS DEBUG START ===');
      print('Phone: $to');
      print('Message: $message');

      // First check if SMS is available
      bool canSend = await canSendSMS();
      print('Can send SMS: $canSend');

      if (!canSend) {
        print('SMS not available on this device');
        return false;
      }

      final bool result = await _channel.invokeMethod('sendSMS', {
        'phone': to,
        'message': message,
      });

      print('Platform SMS result: $result');
      return result;
    } on PlatformException catch (e) {
      print('Failed to send SMS: ${e.message}');
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

  // Call this when app comes to foreground to continue SMS queue
  static Future<void> resumePendingSMS() async {
    final prefs = await SharedPreferences.getInstance();
    final isActive = prefs.getBool('sms_queue_active') ?? false;
    final recipients = prefs.getStringList('sms_queue_recipients');

    if (isActive && recipients != null && recipients.isNotEmpty) {
      print('Resuming pending SMS queue...');

      // Small delay to ensure app is fully active
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
