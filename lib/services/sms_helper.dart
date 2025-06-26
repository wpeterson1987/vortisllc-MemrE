import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'subscription_provider.dart';

class SmsHelper {
  final BuildContext context;

  SmsHelper(this.context);

  /// Check if a user can send SMS, and show upgrade dialog if not
  Future<bool> canSendSms() async {
    final provider = Provider.of<SubscriptionProvider>(context, listen: false);

    // First check if the user has SMS sends remaining
    final canSend = await provider.canSendSms();

    if (!canSend) {
      // Show upgrade dialog
      await _showSmsLimitReachedDialog();
      return false;
    }

    return true;
  }

  /// Increment SMS count after successful send
  Future<void> incrementSmsCount({int count = 1}) async {
    final provider = Provider.of<SubscriptionProvider>(context, listen: false);
    await provider.incrementSmsCount(count);
  }

  /// Show a dialog when SMS limit is reached
  Future<void> _showSmsLimitReachedDialog() async {
    final provider = Provider.of<SubscriptionProvider>(context, listen: false);

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('SMS Limit Reached'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You have used all your available SMS messages for this month.',
                ),
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                    style: TextStyle(color: Colors.black87),
                    children: [
                      const TextSpan(text: 'Current plan: '),
                      TextSpan(
                        text: provider.subscriptionTier,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('SMS limit: ${provider.smsLimit} per month'),
                Text('Next reset: in ${provider.daysUntilReset} days'),
                const SizedBox(height: 16),
                const Text(
                  'Would you like to upgrade your subscription to get more SMS messages?',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not Now'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();

                // Get the upgrade URL and launch it
                final url = await provider.getSubscriptionUpgradeUrl();
                if (await canLaunchUrl(Uri.parse(url))) {
                  await launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.inAppWebView,
                    webViewConfiguration: const WebViewConfiguration(
                      enableJavaScript: true,
                    ),
                  );
                }
              },
              child: const Text('Upgrade Now'),
            ),
          ],
        );
      },
    );
  }
}

// Simplified usage example:
// 
// void sendSmsReminder() async {
//   final smsHelper = SmsHelper(context);
//   
//   // Check if user can send SMS
//   if (await smsHelper.canSendSms()) {
//     // Your SMS sending logic here
//     bool sent = await sendActualSms(phone, message);
//     
//     // If sent successfully, increment the count
//     if (sent) {
//       await smsHelper.incrementSmsCount();
//     }
//   }
// }