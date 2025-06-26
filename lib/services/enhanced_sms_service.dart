import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'subscription_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class EnhancedSMSService {
  final BuildContext context;

  EnhancedSMSService({
    required this.context,
    String? username, // Keep for compatibility but not used
    String? apiKey, // Keep for compatibility but not used
    String? senderId, // Keep for compatibility but not used
  });

  /// Opens the default SMS app with pre-filled recipient and message
  Future<bool> sendSMS({
    required String to,
    required String message,
  }) async {
    try {
      // Clean the phone number
      String cleanNumber = to.replaceAll(RegExp(r'[^\d+]'), '');

      // Create SMS URI
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: cleanNumber,
        queryParameters: {'body': message},
      );

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);

        // Still increment SMS count for tracking purposes
        await _incrementSmsCount(1);
        return true;
      } else {
        print('Could not launch SMS app');
        _showSMSNotAvailableDialog();
        return false;
      }
    } catch (e) {
      print('Error launching SMS: $e');
      return false;
    }
  }

  /// Send SMS to multiple recipients
  Future<Map<String, bool>> sendBulkSMS({
    required List<String> recipients,
    required String message,
  }) async {
    final results = <String, bool>{};

    if (recipients.isEmpty) {
      print('No recipients provided for bulk SMS');
      return results;
    }

    // Check if the user can send this many SMS
    if (!await _canSendSms(recipients.length)) {
      for (final recipient in recipients) {
        results[recipient] = false;
      }
      return results;
    }

    int successCount = 0;
    for (String recipient in recipients) {
      bool success = await sendSMS(to: recipient, message: message);
      results[recipient] = success;
      if (success) successCount++;

      // Add delay between SMS apps
      if (recipients.length > 1) {
        await Future.delayed(Duration(milliseconds: 500));
      }
    }

    return results;
  }

  // Keep existing subscription checking methods
  Future<bool> _canSendSms(int count) async {
    final subscriptionProvider =
        Provider.of<SubscriptionProvider>(context, listen: false);

    if (subscriptionProvider.smsLimit == 0 && !subscriptionProvider.isLoading) {
      await subscriptionProvider.refreshSubscriptionData();
    }

    if (subscriptionProvider.smsRemaining < count) {
      await _showUpgradeDialog(subscriptionProvider, count);
      return false;
    }

    return true;
  }

  Future<void> _incrementSmsCount(int count) async {
    try {
      final subscriptionProvider =
          Provider.of<SubscriptionProvider>(context, listen: false);
      await subscriptionProvider.incrementSmsCount(count);
    } catch (e) {
      print('Error incrementing SMS count: $e');
    }
  }

  // Show dialog when SMS app is not available
  Future<void> _showSMSNotAvailableDialog() async {
    return showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('SMS Not Available'),
          content: Text(
              'SMS messaging is not available on this device. Please try using email instead.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // Keep existing upgrade dialog method
  Future<void> _showUpgradeDialog(
      SubscriptionProvider provider, int messageCount) async {
    // Your existing upgrade dialog code here
    return showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('SMS Limit Reached'),
          content: Text('You don\'t have enough SMS messages remaining.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Not Now'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final url = provider.getSubscriptionUpgradeUrl();
                if (await canLaunchUrl(Uri.parse(url))) {
                  await launchUrl(Uri.parse(url));
                }
              },
              child: Text('Upgrade Now'),
            ),
          ],
        );
      },
    );
  }

  String getSubscriptionInfo() {
    final provider = Provider.of<SubscriptionProvider>(context, listen: false);
    return 'Plan: ${provider.subscriptionTier} - SMS: ${provider.smsUsed}/${provider.smsLimit}';
  }

  Future<bool> testSMSService() async {
    return true; // Intent-based SMS is always available
  }
}
