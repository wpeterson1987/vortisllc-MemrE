import 'package:url_launcher/url_launcher.dart';

class IntentSMSService {
  /// Opens the default SMS app with pre-filled recipient and message
  static Future<bool> sendSMS({
    required String to,
    required String message,
  }) async {
    try {
      // Clean the phone number (remove any non-numeric characters except +)
      String cleanNumber = to.replaceAll(RegExp(r'[^\d+]'), '');

      // Create SMS URI
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: cleanNumber,
        queryParameters: {'body': message},
      );

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
        return true;
      } else {
        print('Could not launch SMS app');
        return false;
      }
    } catch (e) {
      print('Error launching SMS: $e');
      return false;
    }
  }

  /// Send SMS to multiple recipients (opens SMS app for each)
  static Future<Map<String, bool>> sendBulkSMS({
    required List<String> recipients,
    required String message,
  }) async {
    final results = <String, bool>{};

    for (String recipient in recipients) {
      bool success = await sendSMS(to: recipient, message: message);
      results[recipient] = success;

      // Add a small delay between opening SMS apps
      if (recipients.length > 1) {
        await Future.delayed(Duration(milliseconds: 500));
      }
    }

    return results;
  }

  /// Opens SMS app with just a message (user selects recipient)
  static Future<bool> sendSMSMessage(String message) async {
    try {
      final Uri smsUri = Uri(
        scheme: 'sms',
        queryParameters: {'body': message},
      );

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
        return true;
      } else {
        print('Could not launch SMS app');
        return false;
      }
    } catch (e) {
      print('Error launching SMS: $e');
      return false;
    }
  }
}
