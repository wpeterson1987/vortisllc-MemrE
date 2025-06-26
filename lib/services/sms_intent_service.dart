import 'package:flutter/material.dart';
import 'platform_sms_service.dart';

class SMSIntentService {
  /// Send SMS using intent (opens SMS app like email service opens email app)
  Future<bool> sendSMS({
    required String to,
    required String message,
  }) async {
    try {
      print('Opening SMS app for: $to');

      // Use the platform SMS service to open SMS app
      bool success = await PlatformSMSService.sendSMS(
        to: to,
        message: message,
      );

      if (success) {
        print('SMS app opened successfully for $to');
        return true;
      } else {
        print('Failed to open SMS app for $to');
        return false;
      }
    } catch (e) {
      print('Error opening SMS app: $e');
      return false;
    }
  }

  /// Send SMS to multiple recipients (like email service)
  Future<Map<String, bool>> sendBulkSMS({
    required List<String> recipients,
    required String message,
  }) async {
    final results = <String, bool>{};

    print('Sending SMS to ${recipients.length} recipients');

    for (int i = 0; i < recipients.length; i++) {
      String recipient = recipients[i];

      // Show progress like your email service might
      print(
          'Opening SMS app for recipient ${i + 1} of ${recipients.length}: $recipient');

      bool success = await sendSMS(to: recipient, message: message);
      results[recipient] = success;

      // Add delay between SMS apps (like your current implementation)
      if (i < recipients.length - 1) {
        print('Waiting before next SMS...');
        await Future.delayed(Duration(seconds: 3));
      }
    }

    return results;
  }

  /// Process SMS notifications from notification tap (mirrors email handling)
  static Future<void> processSMSNotifications({
    required BuildContext context,
    required List<String> phoneNumbers,
    required String description,
    required String memoContent,
  }) async {
    print('Processing SMS notifications for ${phoneNumbers.length} recipients');

    final smsService = SMSIntentService();
    final message = 'Reminder: $description\n$memoContent';

    // Show confirmation dialog (like you might for email)
    bool? shouldSend = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send SMS Reminders'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send SMS to ${phoneNumbers.length} recipients:'),
            SizedBox(height: 10),
            ...phoneNumbers.map((phone) => Text('• $phone')).toList(),
            SizedBox(height: 10),
            Text('Your SMS app will open for each recipient.'),
            SizedBox(height: 10),
            Text('Message:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(message, style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Send SMS'),
          ),
        ],
      ),
    );

    if (shouldSend == true) {
      // Send SMS to all recipients (opens SMS app for each)
      await smsService.sendBulkSMS(
        recipients: phoneNumbers,
        message: message,
      );
    }
  }
}
