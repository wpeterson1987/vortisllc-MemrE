import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class WordPressRegistrationService {
  final String baseUrl = 'https://memre.vortisllc.com/wp-json';

  /// Register user through WordPress Ultimate Member system
  /// This ensures database tables are created via your existing hooks
  Future<Map<String, dynamic>> registerUser({
    required String username,
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      print('=== WORDPRESS REGISTRATION SERVICE ===');
      print('Registering user: $username, $email');

      // Use WordPress user registration endpoint that triggers Ultimate Member hooks
      final registrationUrl = '$baseUrl/wp/v2/users';
      
      // You'll need to create a custom endpoint that handles Ultimate Member registration
      // For now, let's use a custom endpoint you'll need to add to functions.php
      final customRegistrationUrl = '$baseUrl/memre/v1/register-user';

      final response = await http.post(
        Uri.parse(customRegistrationUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'display_name': displayName,
          'create_tables': true, // Flag to trigger table creation
        }),
      );

      print('Registration response status: ${response.statusCode}');
      print('Registration response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        
        return {
          'success': true,
          'user_id': data['user_id'],
          'message': 'Account created successfully',
          'tables_created': data['tables_created'] ?? false,
        };
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'message': errorData['message'] ?? 'Registration failed',
        };
      }
    } catch (e) {
      print('Registration error: $e');
      return {
        'success': false,
        'message': 'Network error during registration',
      };
    }
  }

  /// Login user and verify database tables exist
  Future<Map<String, dynamic>> loginUser({
    required String username,
    required String password,
  }) async {
    try {
      print('=== WORDPRESS LOGIN SERVICE ===');
      print('Logging in user: $username');

      // First, authenticate with WordPress
      final authUrl = '$baseUrl/jwt-auth/v1/token';
      
      final authResponse = await http.post(
        Uri.parse(authUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      print('Auth response status: ${authResponse.statusCode}');
      print('Auth response body: ${authResponse.body}'); // ADD THIS LINE FOR DEBUGGING
      
      if (authResponse.statusCode == 200) {
        final authData = jsonDecode(authResponse.body);
        print('Auth data parsed: $authData'); // ADD THIS LINE FOR DEBUGGING
        
        // Extract user ID from JWT token since it's not in the main response
        int? userId;
        
        try {
          final token = authData['token'];
          if (token != null) {
            // Decode JWT to get user ID
            final parts = token.split('.');
            if (parts.length == 3) {
              String payload = parts[1];
              // Add padding if needed for base64 decoding
              while (payload.length % 4 != 0) {
                payload += '=';
              }
              
              final decoded = utf8.decode(base64Decode(payload));
              final jwtData = jsonDecode(decoded);
              
              print('JWT payload decoded: $jwtData');
              
              // Extract user ID from JWT payload
              final userIdString = jwtData['data']?['user']?['id'];
              if (userIdString != null) {
                userId = int.tryParse(userIdString.toString());
              }
            }
          }
        } catch (e) {
          print('Error decoding JWT: $e');
        }
        
        print('Extracted user ID: $userId'); // ADD THIS LINE FOR DEBUGGING
        
        if (userId != null) {
          // Verify/create database tables for this user
          print('Calling _ensureUserTablesExist for user: $userId');
          final tablesResult = await _ensureUserTablesExist(userId, authData['token']);
          print('Tables result: $tablesResult'); // ADD THIS LINE FOR DEBUGGING
          
          final result = {
            'success': true,
            'user_id': userId,
            'jwt_token': authData['token'],
            'user_email': authData['user_email'],
            'user_display_name': authData['user_display_name'],
            'tables_verified': tablesResult['success'],
            'tables_created': tablesResult['created'],
          };
          
          print('Returning success result: $result'); // ADD THIS LINE FOR DEBUGGING
          return result;
        } else {
          print('ERROR: Could not extract user ID from auth response');
          return {
            'success': false,
            'message': 'Could not extract user information from login response',
          };
        }
      } else {
        // Handle non-200 status codes
        print('Auth failed with status: ${authResponse.statusCode}');
        try {
          final errorData = jsonDecode(authResponse.body);
          return {
            'success': false,
            'message': errorData['message'] ?? 'Login failed',
          };
        } catch (e) {
          return {
            'success': false,
            'message': 'Login failed with status: ${authResponse.statusCode}',
          };
        }
      }
    } catch (e) {
      print('Login error: $e');
      return {
        'success': false,
        'message': 'Network error during login: $e',
      };
    }
  }

  /// Ensure user database tables exist (create if missing)
  Future<Map<String, dynamic>> _ensureUserTablesExist(int userId, String jwtToken) async {
    try {
      print('Verifying database tables for user: $userId');
      
      final tablesUrl = '$baseUrl/memre/v1/user/$userId/ensure-tables';
      
      final response = await http.post(
        Uri.parse(tablesUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      print('Tables verification response status: ${response.statusCode}');
      print('Tables verification response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'created': data['tables_created'] ?? false,
          'verified': data['tables_verified'] ?? false,
        };
      } else {
        print('Tables verification failed: ${response.statusCode}');
        // Don't fail the entire login just because tables verification failed
        return {
          'success': true, // Changed from false to true
          'created': false,
          'verified': false,
        };
      }
    } catch (e) {
      print('Tables verification error: $e');
      // Don't fail the entire login just because tables verification failed
      return {
        'success': true, // Changed from false to true
        'created': false,
        'verified': false,
      };
    }
  }
}