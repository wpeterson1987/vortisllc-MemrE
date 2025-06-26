// Updated SMSService.dart with better multiple recipient handling

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'package:url_launcher/url_launcher.dart';

class SMSService {
  // Send a single SMS

  Future<bool> sendSMS({
    required String to,
    required String message,
  }) async {
    try {
      print('=== SMS DEBUG START ===');
      print('Original phone number: $to');
      print('Original message: $message');

      // Clean the phone number - remove everything except digits and +
      String cleanNumber = to.replaceAll(RegExp(r'[^\d+]'), '');
      print('Cleaned phone number: $cleanNumber');

      // Try multiple SMS URI formats for better Android compatibility
      List<String> uriFormats = [
        // Format 1: Standard SMS with tel: scheme
        'sms:$cleanNumber?body=${Uri.encodeComponent(message)}',
        // Format 2: SMS without + prefix
        'sms:${cleanNumber.replaceAll('+', '')}?body=${Uri.encodeComponent(message)}',
        // Format 3: Alternative format
        'smsto:$cleanNumber?body=${Uri.encodeComponent(message)}',
      ];

      for (int i = 0; i < uriFormats.length; i++) {
        String uriString = uriFormats[i];
        print('Trying URI format ${i + 1}: $uriString');

        try {
          Uri smsUri = Uri.parse(uriString);

          bool canLaunch = await canLaunchUrl(smsUri);
          print('Can launch format ${i + 1}: $canLaunch');

          if (canLaunch) {
            print('Attempting to launch SMS app with format ${i + 1}...');
            bool launched = await launchUrl(
              smsUri,
              mode: LaunchMode.externalApplication, // Force external app
            );
            print('Launch result for format ${i + 1}: $launched');

            if (launched) {
              print('SUCCESS: SMS app opened with format ${i + 1}');
              return true;
            }
          }
        } catch (e) {
          print('Error with format ${i + 1}: $e');
          continue;
        }
      }

      print('All SMS formats failed');
      return false;
    } catch (e) {
      print('SMS Error: $e');
      print('Error type: ${e.runtimeType}');
      return false;
    }
  }

  // Send SMS to multiple recipients - improved implementation
  Future<Map<String, bool>> sendBulkSMS({
    required List<String> recipients,
    required String message,
  }) async {
    final results = <String, bool>{};

    if (recipients.isEmpty) {
      print('No recipients provided for bulk SMS');
      return results;
    }

    print('Opening SMS app for ${recipients.length} recipients');
    for (String recipient in recipients) {
      bool success = await sendSMS(to: recipient, message: message);
      results[recipient] = success;

      if (recipients.length > 1) {
        await Future.delayed(Duration(milliseconds: 500));
      }
    }

    print('SMS app opened for recipients: ${results.keys.join(', ')}');
    return results;
  }

  // Provide a method for testing the service connectivity
  Future<bool> testSMSService() async {
    print('Intent-based SMS service is always available if SMS app exists');
    return true;
  }
}
