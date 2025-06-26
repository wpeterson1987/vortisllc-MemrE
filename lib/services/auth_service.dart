import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final String baseUrl = 'https://memre.vortisllc.com/wp-json';
  static const String _userIdKey = 'userId';
  static const String _usernameKey = 'username';
  String? _jwtToken;

  String? get jwtToken => _jwtToken;

  Future<int?> getLoggedInUserId() async {
    try {
      final userData = await getSavedUserData();
      print('Getting logged in user ID, userData: $userData');

      if (userData != null && userData.containsKey('user_id')) {
        final userId = userData['user_id'];
        print('Returning user ID: $userId (type: ${userId.runtimeType})');
        return userId is int ? userId : int.tryParse(userId.toString());
      }

      print('No user ID found in saved user data');
      return null;
    } catch (e) {
      print('Error getting logged in user ID: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> login(
      String username, String password, bool rememberMe) async {
    try {
      print('Attempting login with JWT for user: $username');

      // Authenticate with WordPress JWT endpoint
      final tokenResponse = await http.post(
        Uri.parse('https://memre.vortisllc.com/wp-json/jwt-auth/v1/token'),
        body: {
          'username': username,
          'password': password,
        },
      );

      print('JWT response status: ${tokenResponse.statusCode}');

      if (tokenResponse.statusCode != 200) {
        print('JWT auth failed: ${tokenResponse.body}');
        throw Exception('Authentication failed');
      }

      // Parse the token response
      final tokenData = json.decode(tokenResponse.body);
      print('JWT response data: $tokenData'); // Log the full response

      // Log each key-value pair in the response to find the user ID
      tokenData.forEach((key, value) {
        print('JWT data - $key: $value');
        if (value is Map) {
          value.forEach((subKey, subValue) {
            print('  - $subKey: $subValue');
          });
        }
      });

      final String jwtToken = tokenData['token'];

      // Look for the user ID in the token data
      int? userId;

      // Check if user ID is in the response
      if (tokenData.containsKey('data') && tokenData['data'] is Map) {
        print('Checking data field for user info');
        final data = tokenData['data'];

        if (data.containsKey('user') && data['user'] is Map) {
          final user = data['user'];
          if (user.containsKey('id')) {
            userId = int.tryParse(user['id'].toString());
            print('Found user ID in data.user.id: $userId');
          }
        }
      }

      // Try other common locations
      if (userId == null && tokenData.containsKey('user_id')) {
        userId = int.tryParse(tokenData['user_id'].toString());
        print('Found user ID in user_id field: $userId');
      }

      if (userId == null && tokenData.containsKey('id')) {
        userId = int.tryParse(tokenData['id'].toString());
        print('Found user ID in id field: $userId');
      }

      // If we still don't have a user ID, we need to figure out another way
      if (userId == null) {
        print('WARNING: Could not extract user ID from JWT response');

        // Try to get the user ID from a direct API call
        final userResponse = await http.get(
          Uri.parse('https://memre.vortisllc.com/wp-json/wp/v2/users/me'),
          headers: {
            'Authorization': 'Bearer $jwtToken',
            'Content-Type': 'application/json',
          },
        );

        print('User data response status: ${userResponse.statusCode}');

        if (userResponse.statusCode == 200) {
          final userData = json.decode(userResponse.body);
          print('User data response: $userData');

          if (userData.containsKey('id')) {
            userId = int.tryParse(userData['id'].toString());
            print('Found user ID from /users/me endpoint: $userId');
          }
        }
      }

      // If we still don't have a user ID after all attempts
      if (userId == null) {
        print(
            'ERROR: Failed to determine user ID after multiple attempts. Using placeholder ID.');
        throw Exception('Could not determine user ID');
      }

      // Create user data object with the JWT token
      final userData = {
        'user_id': userId,
        'username': username,
        'email': tokenData['user_email'] ?? '',
        'display_name': tokenData['user_display_name'] ?? username,
        'jwt_token': jwtToken,
      };

      print('Login successful for user: $username (ID: $userId)');

      // Save user data if remember me is checked
      if (rememberMe) {
        await _saveUserData(userData);
      }

      return userData;
    } catch (e) {
      print('Login error: $e');
      rethrow;
    }
  }

  Future<void> _saveUserData(Map<String, dynamic> userData) async {
    try {
      print('Saving user data to SharedPreferences: $userData');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', json.encode(userData));
      print('User data saved successfully');
    } catch (e) {
      print('Error saving user data: $e');
      throw Exception('Failed to save user data: $e');
    }
  }

  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      // Any other cleanup needed
    } catch (e) {
      print('Error during logout: $e');
    }
  }

  Future<Map<String, dynamic>?> getSavedUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      print(
          'Retrieved user data string from SharedPreferences: $userDataString');

      if (userDataString != null) {
        final userData = json.decode(userDataString);
        print('Parsed user data: $userData');
        return userData;
      }
      print('No user data found in SharedPreferences');
      return null;
    } catch (e) {
      print('Error getting saved user data: $e');
      return null;
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/memre-app/v1/reset-password'),
        body: {
          'email': email,
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Password reset request error: $e');
      throw Exception('Failed to request password reset');
    }
  }
}
