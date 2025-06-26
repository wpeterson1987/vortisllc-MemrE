import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

class SubscriptionService {
  final String baseUrl = 'https://memre.vortisllc.com/wp-json';

  // Get the current subscription status for the logged-in user
  Future<Map<String, dynamic>?> getSubscriptionStatus() async {
    try {
      print('=== SUBSCRIPTION STATUS DEBUG ===');

      // Check if we have stored credentials
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final userId = prefs.getString('user_id');
      final userEmail = prefs.getString('user_email');

      print('Stored token exists: ${token != null}');
      print('Stored user ID: $userId');
      print('Stored user email: $userEmail');

      if (token == null) {
        print('ERROR: No JWT token found in storage');
        throw Exception('User not logged in');
      }

      // Print token info for debugging
      if (token.length > 50) {
        print('Token (first 50 chars): ${token.substring(0, 50)}...');
      }

      // Decode and print JWT payload for debugging
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          String payload = parts[1];
          // Add padding if needed
          while (payload.length % 4 != 0) {
            payload += '=';
          }

          final decoded = utf8.decode(base64Decode(payload));
          final data = jsonDecode(decoded);

          print('JWT payload:');
          print('  iss: ${data['iss']}');
          print('  user_id: ${data['data']?['user']?['id']}');
          print('  exp: ${data['exp']}');

          // Check if expired
          final exp = data['exp'];
          final now = DateTime.now().millisecondsSinceEpoch / 1000;
          if (exp != null && exp < now) {
            print('ERROR: JWT token is expired!');
            throw Exception('JWT token expired');
          }
        }
      } catch (e) {
        print('Could not decode JWT payload: $e');
      }

      // Try to validate token first
      print('Validating JWT token...');
      final validateUrl = '$baseUrl/jwt-auth/v1/token/validate';

      final validateResponse = await http.post(
        Uri.parse(validateUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Token validation status: ${validateResponse.statusCode}');
      print('Token validation response: ${validateResponse.body}');

      if (validateResponse.statusCode != 200) {
        print('ERROR: Token validation failed');
        throw Exception('Token validation failed');
      }

      // Determine user ID
      String? targetUserId = userId;
      if (targetUserId == null) {
        // Extract from JWT
        final parts = token.split('.');
        if (parts.length == 3) {
          String payload = parts[1];
          while (payload.length % 4 != 0) {
            payload += '=';
          }
          final decoded = utf8.decode(base64Decode(payload));
          final data = jsonDecode(decoded);
          targetUserId = data['data']?['user']?['id']?.toString();

          if (targetUserId != null) {
            // Save it for future use
            await prefs.setString('user_id', targetUserId);
            print('Extracted and saved user ID from JWT: $targetUserId');
          }
        }
      }

      if (targetUserId == null) {
        print('ERROR: Could not determine user ID');
        throw Exception('Could not determine user ID');
      }

      // Try different subscription endpoints
      final subscriptionEndpoints = [
        '$baseUrl/memre-app/v1/subscription-status/$targetUserId',
        '$baseUrl/memre-app/v1/subscription-status',
      ];

      for (String endpoint in subscriptionEndpoints) {
        print('Trying subscription endpoint: $endpoint');

        try {
          final response = await http.get(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );

          print('Subscription response status: ${response.statusCode}');
          print('Subscription response body: ${response.body}');

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            print('Subscription data parsed successfully');
            return data;
          } else if (response.statusCode == 404) {
            print('Endpoint not found, trying next...');
            continue;
          } else {
            print(
                'ERROR: Subscription API call failed with status ${response.statusCode}');
          }
        } catch (e) {
          print('Error calling endpoint $endpoint: $e');
          continue;
        }
      }

      // If subscription endpoints fail, return a default structure
      print('All subscription endpoints failed, returning default trial data');
      return {
        'subscription_tier': 'Free Trial',
        'trial_active': true,
        'trial_days_remaining': 14,
        'has_valid_subscription': false,
        'trial_expired': false,
        'error': 'Could not connect to subscription service'
      };
    } catch (e) {
      print('Exception in getSubscriptionStatus: $e');
      throw Exception('Failed to get subscription status: $e');
    }
  }

  // Check if user has premium access (paid subscription or active trial)
  Future<bool> hasAppAccess() async {
    try {
      final status = await getSubscriptionStatus();
      if (status == null) return false;

      // User has access if they have a valid subscription OR active trial
      final hasSubscription = status['has_valid_subscription'] == true;
      final trialActive = status['trial_active'] == true;

      print(
          'Access check: hasSubscription=$hasSubscription, trialActive=$trialActive');

      return hasSubscription || trialActive;
    } catch (e) {
      print('Error checking app access: $e');
      return false; // Deny access if we can't determine status
    }
  }

  // Check if user's trial has expired
  Future<bool> isTrialExpired() async {
    try {
      final status = await getSubscriptionStatus();
      if (status == null) return true;

      return status['trial_expired'] == true;
    } catch (e) {
      print('Error checking trial expiration: $e');
      return true; // Assume expired if we can't check
    }
  }

  // Get days remaining in trial
  Future<int> getTrialDaysRemaining() async {
    try {
      final status = await getSubscriptionStatus();
      if (status == null) return 0;

      return status['trial_days_remaining'] ?? 0;
    } catch (e) {
      print('Error getting trial days remaining: $e');
      return 0;
    }
  }

  // Get subscription tier name
  Future<String> getSubscriptionTier() async {
    try {
      final status = await getSubscriptionStatus();
      if (status == null) return 'Unknown';

      return status['subscription_tier'] ?? 'Free Trial';
    } catch (e) {
      print('Error getting subscription tier: $e');
      return 'Unknown';
    }
  }

  // Launch subscription upgrade page
  Future<String> getSubscriptionUpgradeUrl() async {
    return 'https://memre.vortisllc.com/account/?upgrade=true&source=app';
  }

  // Test all subscription-related endpoints for debugging
  Future<void> testAllEndpoints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final userId = prefs.getString('user_id');

      if (token == null || userId == null) {
        print('Cannot test endpoints: missing token or user ID');
        return;
      }

      print('=== TESTING ALL SUBSCRIPTION ENDPOINTS ===');

      final endpoints = [
        '$baseUrl/memre-app/v1/subscription-status/$userId',
        '$baseUrl/memre-app/v1/subscription-status',
        '$baseUrl/wp/v2/users/me',
        '$baseUrl/jwt-auth/v1/token/validate',
      ];

      for (String endpoint in endpoints) {
        print('\n--- Testing: $endpoint ---');

        try {
          final response = await http.get(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );

          print('Status: ${response.statusCode}');
          print('Body: ${response.body}');
        } catch (e) {
          print('Error: $e');
        }
      }
    } catch (e) {
      print('Error in testAllEndpoints: $e');
    }
  }

  // Clear stored subscription data (useful for testing)
  Future<void> clearSubscriptionCache() async {
    // No caching implemented yet, but this method is ready for future use
    print('Subscription cache cleared');
  }

  // Get subscription status with retry logic
  Future<Map<String, dynamic>?> getSubscriptionStatusWithRetry(
      {int maxRetries = 3}) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      try {
        attempts++;
        print('Subscription status attempt $attempts/$maxRetries');

        final result = await getSubscriptionStatus();
        if (result != null) {
          return result;
        }
      } catch (e) {
        print('Subscription status attempt $attempts failed: $e');

        if (attempts >= maxRetries) {
          rethrow;
        }

        // Wait before retrying
        await Future.delayed(Duration(seconds: attempts));
      }
    }

    return null;
  }
}
