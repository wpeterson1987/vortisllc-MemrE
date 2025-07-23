import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'wordpress_registration_service.dart';

class AuthService {
  final WordPressRegistrationService _registrationService = WordPressRegistrationService();
  
  static const String _userDataKey = 'user_data';

  /// Register new user through WordPress Ultimate Member system
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      print('=== AUTH SERVICE REGISTRATION ===');
      print('Registering user: $username');

      // Use WordPress registration service to ensure tables are created
      final result = await _registrationService.registerUser(
        username: username,
        email: email,
        password: password,
        displayName: displayName,
      );

      if (result['success']) {
        print('✅ WordPress registration successful');
        print('✅ Tables created: ${result['tables_created']}');
        
        // If registration successful, automatically log in to get JWT token
        final loginResult = await login(username, password);
        
        if (loginResult['success']) {
          return {
            'success': true,
            'user_id': result['user_id'],
            'message': 'Account created successfully',
            'tables_created': result['tables_created'],
            'auto_login_success': true,
          };
        } else {
          // Registration succeeded but login failed - still success
          return {
            'success': true,
            'user_id': result['user_id'],
            'message': 'Account created successfully. Please log in.',
            'tables_created': result['tables_created'],
            'auto_login_success': false,
          };
        }
      } else {
        return result;
      }
    } catch (e) {
      print('❌ Registration error: $e');
      return {
        'success': false,
        'message': 'Registration failed: $e',
      };
    }
  }

  /// Login user and verify database tables
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      print('=== AUTH SERVICE LOGIN ===');
      print('Logging in user: $username');

      // Use WordPress login service that also verifies tables
      final result = await _registrationService.loginUser(
        username: username,
        password: password,
      );

      print('WordPress login result: $result'); // ADD THIS DEBUG LINE

      if (result['success']) {
        print('✅ WordPress login successful');
        print('✅ Tables verified: ${result['tables_verified']}');
        
        // Save user data to local storage
        final userData = {
          'user_id': result['user_id'],
          'username': username,
          'jwt_token': result['jwt_token'],
          'user_email': result['user_email'],
          'user_display_name': result['user_display_name'],
          'tables_verified': result['tables_verified'],
          'tables_created': result['tables_created'],
        };

        print('Saving user data: $userData'); // ADD THIS DEBUG LINE
        await _saveUserData(userData);
        
        return {
          'success': true,
          'user_id': result['user_id'],
          'message': 'Login successful',
          'tables_verified': result['tables_verified'],
        };
      } else {
        print('❌ WordPress login failed: ${result['message']}');
        return result;
      }
    } catch (e) {
      print('❌ Login error: $e');
      return {
        'success': false,
        'message': 'Login failed: $e',
      };
    }
  }

  /// Check if user tables exist and create if missing
  Future<bool> ensureUserTablesExist() async {
    try {
      final userId = await getLoggedInUserId();
      if (userId == null) return false;

      print('=== ENSURING USER TABLES EXIST ===');
      print('User ID: $userId');

      // This will be called through the subscription provider
      // The WordPress endpoint will handle table creation
      return true;
    } catch (e) {
      print('❌ Error ensuring tables exist: $e');
      return false;
    }
  }

  /// Save user data to local storage
  Future<void> _saveUserData(Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataJson = jsonEncode(userData);
      await prefs.setString(_userDataKey, userDataJson);
      print('✅ User data saved to local storage');
      
      // Also save individual fields for easier access
      await prefs.setString('jwt_token', userData['jwt_token'] ?? '');
      await prefs.setString('user_id', userData['user_id']?.toString() ?? '');
      await prefs.setString('user_email', userData['user_email'] ?? '');
      
      print('✅ Individual fields saved to SharedPreferences');
    } catch (e) {
      print('❌ Error saving user data: $e');
    }
  }

  /// Get saved user data from local storage
  Future<Map<String, dynamic>?> getSavedUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString(_userDataKey);
      
      if (userDataString != null) {
        print('Retrieved user data string from SharedPreferences: $userDataString');
        final userData = Map<String, dynamic>.from(jsonDecode(userDataString));
        print('Parsed user data: $userData');
        return userData;
      } else {
        print('No user data found in SharedPreferences');
        return null;
      }
    } catch (e) {
      print('Error retrieving user data: $e');
      return null;
    }
  }

  /// Get logged in user ID
  Future<int?> getLoggedInUserId() async {
    try {
      final userData = await getSavedUserData();
      print('Getting logged in user ID, userData: $userData');
      
      if (userData != null && userData['user_id'] != null) {
        final userId = userData['user_id'];
        print('Returning user ID: $userId (type: ${userId.runtimeType})');
        
        if (userId is int) {
          return userId;
        } else if (userId is String) {
          return int.tryParse(userId);
        }
      }
      
      print('No valid user ID found');
      return null;
    } catch (e) {
      print('Error getting logged in user ID: $e');
      return null;
    }
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    final userId = await getLoggedInUserId();
    return userId != null;
  }

  /// Logout user
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userDataKey);
      await prefs.remove('jwt_token');
      await prefs.remove('user_id');
      await prefs.remove('user_email');
      print('✅ User logged out successfully');
    } catch (e) {
      print('❌ Error during logout: $e');
    }
  }

  /// Get JWT token for API calls
  Future<String?> getJwtToken() async {
    try {
      final userData = await getSavedUserData();
      return userData?['jwt_token'];
    } catch (e) {
      print('Error getting JWT token: $e');
      return null;
    }
  }

  /// Verify JWT token is still valid
  Future<bool> verifyToken() async {
    try {
      final token = await getJwtToken();
      if (token == null) return false;

      // You can add token validation logic here
      // For now, just check if token exists
      return true;
    } catch (e) {
      print('Error verifying token: $e');
      return false;
    }
  }
}