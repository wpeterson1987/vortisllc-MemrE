import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationSenderService {
  final String _username;
  final String _apiKey;
  final String _baseUrl = 'https://rest.clicksend.com/v3';

  NotificationSenderService({
    required String username,
    required String apiKey,
  })  : _username = username,
        _apiKey = apiKey;

  Map<String, String> get _headers {
    String basicAuth =
        'Basic ' + base64Encode(utf8.encode('$_username:$_apiKey'));
    return {
      'Authorization': basicAuth,
      'Content-Type': 'application/json',
    };
  }

  Future<bool> sendSMS({
    required String to,
    required String message,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/sms/send'),
        headers: _headers,
        body: jsonEncode({
          'messages': [
            {
              'source': 'php',
              'to': to,
              'body': message,
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('SMS sent successfully: $responseData');
        return true;
      } else {
        print('Failed to send SMS: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error sending SMS: $e');
      return false;
    }
  }

  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String body,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/email/send'),
        headers: _headers,
        body: jsonEncode({
          'to': [
            {
              'email': to,
            }
          ],
          'subject': subject,
          'body': body,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('Email sent successfully: $responseData');
        return true;
      } else {
        print('Failed to send email: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error sending email: $e');
      return false;
    }
  }

  Future<bool> sendReminderNotifications({
    required String description,
    required String memoContent,
    String? emailAddress,
    String? phoneNumber,
  }) async {
    bool success = true;

    // Prepare notification content
    final String subject = 'MemrE Reminder: $description';
    final String message = '''
Reminder for your MemrE: $description

$memoContent
''';

    // Send email if email address is provided
    if (emailAddress != null && emailAddress.isNotEmpty) {
      final emailSuccess = await sendEmail(
        to: emailAddress,
        subject: subject,
        body: message,
      );
      if (!emailSuccess) {
        print('Failed to send email notification to $emailAddress');
        success = false;
      }
    }

    // Send SMS if phone number is provided
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      final smsSuccess = await sendSMS(
        to: phoneNumber,
        message: 'Reminder: $description',
      );
      if (!smsSuccess) {
        print('Failed to send SMS notification to $phoneNumber');
        success = false;
      }
    }

    return success;
  }
}
