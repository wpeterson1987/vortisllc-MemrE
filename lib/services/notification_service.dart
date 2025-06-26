// Updated NotificationService.dart with SMS on-screen notifications
import 'package:flutter/material.dart';
import 'dart:async';
import '../services/email_service.dart';
import '../services/sms_service.dart';
import 'dart:typed_data';
import '../models/memo_models.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:provider/provider.dart';
import 'subscription_provider.dart';
import '../services/simple_notification_manager.dart';
import 'dart:convert';
import 'platform_sms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attachment_storage_service.dart';

class NotificationService {
  // Add class fields
  final EmailService _emailService = EmailService();
  SubscriptionProvider? _subscriptionProvider;
  final Map<int, Timer> _timerMap = {};
  final Set<String> _activeNotifications = {};

  // Constructor
  NotificationService({SubscriptionProvider? subscriptionProvider}) {
    _subscriptionProvider = subscriptionProvider;
  }

  void setSubscriptionProvider(SubscriptionProvider provider) {
    _subscriptionProvider = provider;
    print('Subscription provider set in NotificationService');
  }

  // Make these methods static
  static Future<void> initialize() async {
    await AwesomeNotifications().initialize(
      null, // No icon needed for initialization
      [
        NotificationChannel(
          channelKey: 'memre_reminders',
          channelName: 'MemrE Reminders',
          channelDescription: 'Notifications for MemrE reminders',
          defaultColor: Color(0xFF2196F3),
          ledColor: Colors.blue,
          importance: NotificationImportance.High,
          defaultPrivacy: NotificationPrivacy.Private,
        ),
        NotificationChannel(
          channelKey: 'scheduled_channel',
          channelName: 'Scheduled Reminders',
          channelDescription: 'Channel for scheduled reminders',
          defaultColor: Color(0xFF2196F3),
          ledColor: Colors.blue,
          importance: NotificationImportance.High,
          defaultPrivacy: NotificationPrivacy.Private,
        )
      ],
    );

    // Request notification permissions
    await AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
      if (!isAllowed) {
        AwesomeNotifications().requestPermissionToSendNotifications();
      }
    });
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'memre_reminders',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
      ),
    );
  }

  Future<void> scheduleReminderNotification({
    required int memoId,
    required String description,
    required String memoContent,
    required DateTime reminderTime,
    required bool useScreenNotification,
    String? emailAddress,
    String? phoneNumber,
    List<String>? emailAddresses,
    List<String>? phoneNumbers,
    Uint8List? attachmentData,
    String? attachmentFileName,
    AttachmentType? attachmentType,
  }) async {
    final notificationId =
        (memoId % 100000) * 1000 + DateTime.now().millisecondsSinceEpoch % 1000;
    final duration = reminderTime.difference(DateTime.now());
    final notificationKey = '${memoId}_${reminderTime.millisecondsSinceEpoch}';

    if (_activeNotifications.contains(notificationKey)) {
      print('Notification already scheduled: $notificationKey');
      return;
    }

    if (duration.isNegative) {
      print('ERROR: Reminder time is in the past!');
      return;
    }

    // Consolidate email addresses
    final List<String> allEmailAddresses = [];
    if (emailAddress != null && emailAddress.isNotEmpty) {
      allEmailAddresses.add(emailAddress);
    }
    if (emailAddresses != null) {
      for (final email in emailAddresses) {
        if (email.isNotEmpty && !allEmailAddresses.contains(email)) {
          allEmailAddresses.add(email);
        }
      }
    }

    // Consolidate phone numbers
    final List<String> allPhoneNumbers = [];
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      allPhoneNumbers.add(phoneNumber);
    }
    if (phoneNumbers != null) {
      for (final phone in phoneNumbers) {
        if (phone.isNotEmpty && !allPhoneNumbers.contains(phone)) {
          allPhoneNumbers.add(phone);
        }
      }
    }

    // Schedule screen notification with both email and SMS data
    if (useScreenNotification || allPhoneNumbers.isNotEmpty) {
      await _scheduleScreenNotificationWithSMS(
        notificationId: notificationId,
        description: description,
        memoContent: memoContent,
        reminderTime: reminderTime,
        emailAddresses: allEmailAddresses.isNotEmpty ? allEmailAddresses : null,
        phoneNumbers: allPhoneNumbers.isNotEmpty ? allPhoneNumbers : null,
        // ADD THESE LINES:
        attachmentData: attachmentData,
        attachmentFileName: attachmentFileName,
        attachmentType: attachmentType,
      );
    }

    print(
        'Scheduling notifications for ${allEmailAddresses.length} email addresses and ${allPhoneNumbers.length} phone numbers');

    _activeNotifications.add(notificationKey);
    _timerMap[notificationId] = Timer(duration, () async {
      print('Reminder time reached for MemrE: $description');

      // DON'T send emails OR SMS here - let the notification handle everything
      // This ensures consistent behavior whether app is active or inactive

      print('On-screen notification created for both email and SMS');
      print('Email recipients: ${allEmailAddresses.join(', ')}');
      print('SMS recipients: ${allPhoneNumbers.join(', ')}');

      _timerMap.remove(notificationId);
      _activeNotifications.remove(notificationKey);
    });

    print(
        'Scheduled notification with ID $notificationId for ${reminderTime.toString()}');
    print('Email recipients: ${allEmailAddresses.join(', ')}');
    print('SMS recipients: ${allPhoneNumbers.join(', ')}');
  }

  Future<void> _scheduleScreenNotificationWithSMS({
    required int notificationId,
    required String description,
    required String memoContent,
    required DateTime reminderTime,
    List<String>? emailAddresses,
    List<String>? phoneNumbers,
    Uint8List? attachmentData,
    String? attachmentFileName,
    AttachmentType? attachmentType,
  }) async {
    try {
      final isAllowed = await AwesomeNotifications().isNotificationAllowed();
      if (!isAllowed) {
        await AwesomeNotifications().requestPermissionToSendNotifications();
      }

      // Create notification message based on what's available
      String notificationBody = '';

      if (emailAddresses != null && emailAddresses.isNotEmpty) {
        notificationBody +=
            'Tap to send email reminders to ${emailAddresses.length} recipients\n';
      }

      if (phoneNumbers != null && phoneNumbers.isNotEmpty) {
        notificationBody +=
            'Tap to send SMS reminders to ${phoneNumbers.length} recipients\n';
      }

      notificationBody += '\n$memoContent';

      // Create basic payload
      Map<String, String?> payload = {
        'hasEmails':
            (emailAddresses != null && emailAddresses.isNotEmpty).toString(),
        'hasSMS': (phoneNumbers != null && phoneNumbers.isNotEmpty).toString(),
        'emailAddresses':
            emailAddresses != null ? jsonEncode(emailAddresses) : '[]',
        'phoneNumbers': phoneNumbers != null ? jsonEncode(phoneNumbers) : '[]',
        'description': description,
        'memoContent': memoContent,
      };

      // Handle attachment data by storing it separately
      if (attachmentData != null && attachmentFileName != null) {
        print('📎 Storing attachment data separately for notification...');

        // Store attachment to file system
        final storedFilePath =
            await AttachmentStorageService.storeAttachmentForNotification(
          attachmentData: attachmentData,
          fileName: attachmentFileName,
          memoId: 0, // You might want to pass actual memoId here
          notificationId: notificationId,
        );

        if (storedFilePath != null) {
          // Include file path in payload (much smaller than base64 data)
          payload['hasAttachment'] = 'true';
          payload['attachmentFilePath'] = storedFilePath;
          payload['attachmentFileName'] = attachmentFileName;
          payload['attachmentType'] =
              attachmentType?.toString() ?? 'AttachmentType.image';

          print('✅ Attachment stored at: $storedFilePath');
        } else {
          payload['hasAttachment'] = 'false';
          print('❌ Failed to store attachment, proceeding without it');
        }
      } else {
        payload['hasAttachment'] = 'false';
      }

      print(
          'Creating notification with payload keys: ${payload.keys.toList()}');
      print('Payload hasAttachment: ${payload['hasAttachment']}');

      // Create the notification with file path reference
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notificationId,
          channelKey: 'scheduled_channel',
          title: description,
          body: notificationBody,
          notificationLayout: NotificationLayout.Default,
          wakeUpScreen: true,
          payload: payload,
        ),
        schedule: NotificationCalendar(
          year: reminderTime.year,
          month: reminderTime.month,
          day: reminderTime.day,
          hour: reminderTime.hour,
          minute: reminderTime.minute,
          second: reminderTime.second,
          preciseAlarm: true,
        ),
      );

      print(
          '✅ Notification scheduled successfully (with attachment file path)');
    } catch (e) {
      print('❌ Screen notification error: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  void cancelTimer(int baseNotificationId) {
    _timerMap.entries
        .where((entry) =>
            entry.key >= baseNotificationId &&
            entry.key < baseNotificationId + 1000)
        .forEach((entry) {
      entry.value.cancel();
      _timerMap.remove(entry.key);
    });
  }

  Future<void> cancelAllNotifications() async {
    await AwesomeNotifications().cancelAllSchedules();
    for (var timer in _timerMap.values) {
      timer.cancel();
    }
    _timerMap.clear();
    _activeNotifications.clear();
  }

  Future<void> testScreenNotification() async {
    print('Testing screen notification...');

    try {
      final isAllowed = await AwesomeNotifications().isNotificationAllowed();
      print('Notifications allowed: $isAllowed');

      if (!isAllowed) {
        print('Requesting notification permission...');
        final request =
            await AwesomeNotifications().requestPermissionToSendNotifications();
        print('Permission request result: $request');
      }

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: 1,
          channelKey: 'scheduled_channel',
          title: 'Test Notification',
          body: 'This is a test notification',
          notificationLayout: NotificationLayout.Default,
          wakeUpScreen: true,
        ),
      );
      print('Test notification sent');
    } catch (e) {
      print('Error testing notifications: $e');
    }
  }

  // Process SMS notifications when notification is tapped
  static Future<void> processSMSNotifications({
    required BuildContext context,
    required List<String> phoneNumbers,
    required String description,
    required String memoContent,
  }) async {
    print('Processing SMS notifications for ${phoneNumbers.length} recipients');

    final message = 'Reminder: $description\n$memoContent';

    // Show confirmation dialog
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
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child:
                  Text(message, style: TextStyle(fontStyle: FontStyle.italic)),
            ),
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
      await PlatformSMSService.sendBulkSMS(
        recipients: phoneNumbers,
        message: message,
      );
    }
  }

  // Test method to verify notifications are working with multiple recipients
  Future<void> testMultipleRecipients() async {
    print('Testing multiple recipient notifications...');

    final testPhoneNumbers = ['11234567890', '15551234567'];
    final testEmailAddresses = ['test1@example.com', 'test2@example.com'];

    try {
      // Test SMS sending via platform service
      if (testPhoneNumbers.length > 1) {
        print('Testing bulk SMS with ${testPhoneNumbers.length} recipients');
        final result = await PlatformSMSService.sendBulkSMS(
          recipients: testPhoneNumbers,
          message: 'Test bulk SMS message',
        );
        print('Bulk SMS result: $result');
      } else {
        print('Testing single SMS');
        final result = await PlatformSMSService.sendSMS(
          to: testPhoneNumbers.first,
          message: 'Test single SMS message',
        );
        print('Single SMS result: $result');
      }

      // Test email sending
      for (final email in testEmailAddresses) {
        print('Testing email to: $email');
        final result = await _emailService.sendEmail(
          to: email,
          subject: 'Test Email',
          body: 'Test email body',
        );
        print('Email result: $result');
      }

      print('Multiple recipient test completed');
    } catch (e) {
      print('Error testing multiple recipients: $e');
    }
  }
}
