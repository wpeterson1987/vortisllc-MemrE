import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // Add this line for Color class
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class SubscriptionProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  // Updated to use the new WordPress API endpoints we created
  final String baseUrl = 'https://memre.vortisllc.com/wp-json/memre/v1';

  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  // Updated fields to match WordPress API
  String _subscriptionTier = 'Trial';
  bool _trialActive = true;
  int _trialDaysRemaining = 14;
  bool _premiumActive = false;
  bool _trialExpired = false;
  DateTime? _trialEndDate;
  String? _registrationDate;
  String? _stripeCustomerId;
  Map<String, bool> _features = {};

  // Getters
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;

  String get subscriptionTier => _subscriptionTier;
  bool get trialActive => _trialActive;
  int get trialDaysRemaining => _trialDaysRemaining;
  bool get premiumActive => _premiumActive;
  bool get trialExpired => _trialExpired;
  DateTime? get trialEndDate => _trialEndDate;
  String? get registrationDate => _registrationDate;
  Map<String, bool> get features => _features;

  // Updated: Check if user has access to the app
  bool get hasAppAccess => trialActive || premiumActive;

  // Updated: More specific status messages
  String get statusMessage {
    if (premiumActive) {
      return 'MemrE Premium Active';
    } else if (trialActive) {
      return 'Free Trial - $trialDaysRemaining days remaining';
    } else if (trialExpired) {
      return 'Trial Expired - Upgrade Required';
    } else {
      return 'Subscription Required';
    }
  }

  // Get status color for UI
  Color get statusColor {
    if (premiumActive) return Colors.green;
    if (trialActive && trialDaysRemaining > 3) return Colors.blue;
    if (trialActive && trialDaysRemaining <= 3) return Colors.orange;
    return Colors.red;
  }

  // NEW: Clear all subscription state data
  Future<void> clearState() async {
    print('🧹 Clearing subscription state...');

    // Reset all state variables to their initial/default values
    _isLoading = false;
    _hasError = false;
    _errorMessage = '';

    // Reset subscription data to defaults (new user state)
    _subscriptionTier = 'Trial';
    _trialActive = true;
    _trialDaysRemaining = 14;
    _premiumActive = false;
    _trialExpired = false;
    _trialEndDate = null;
    _registrationDate = null;
    _stripeCustomerId = null;
    _features = {};

    print('✅ Subscription state cleared');
    notifyListeners();
  }

  // Initialize subscription data
  Future<void> init() async {
    try {
      final userId = await _authService.getLoggedInUserId();
      print('SubscriptionProvider init - User ID: $userId');

      if (userId != null) {
        await refreshSubscriptionData();
      } else {
        print('No user ID found, skipping subscription initialization');
      }
    } catch (e) {
      print('Error in SubscriptionProvider init: $e');
      _hasError = true;
      _errorMessage = 'Failed to initialize: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // Updated: Refresh subscription data using new WordPress API
  Future<void> refreshSubscriptionData() async {
    print('🔄 Refreshing subscription data...');
    _isLoading = true;
    _hasError = false;
    _errorMessage = '';
    notifyListeners();

    try {
      final userId = await _authService.getLoggedInUserId();
      print('Refreshing subscription data for user ID: $userId');

      if (userId == null) {
        throw Exception('User not logged in');
      }

      // Call the new WordPress API endpoint
      final subscriptionData = await getSubscriptionStatus(userId);

      print('📦 Received subscription data: $subscriptionData');

      // Update state based on new API response structure
      _subscriptionTier = subscriptionData['subscription_tier'] ?? 'Trial';
      _trialActive = subscriptionData['trial_active'] ?? false;
      _trialDaysRemaining = subscriptionData['trial_days_remaining'] ?? 0;
      _premiumActive = subscriptionData['premium_active'] ?? false;
      _trialExpired = subscriptionData['trial_expired'] ?? false;
      _registrationDate = subscriptionData['registration_date'];
      _stripeCustomerId = subscriptionData['stripe_customer_id'];

      // Parse trial end date if provided
      if (subscriptionData['trial_end_date'] != null) {
        try {
          _trialEndDate = DateTime.parse(subscriptionData['trial_end_date']);
        } catch (e) {
          print('Error parsing trial end date: $e');
        }
      }

      // Update features map
      if (subscriptionData['features'] != null) {
        _features = Map<String, bool>.from(subscriptionData['features']);
      }

      print('✅ Subscription status updated:');
      print('- Subscription tier: $_subscriptionTier');
      print('- Trial active: $_trialActive');
      print('- Trial days remaining: $_trialDaysRemaining');
      print('- Premium active: $_premiumActive');
      print('- Trial expired: $_trialExpired');
      print('- Has app access: $hasAppAccess');
    } catch (e) {
      _hasError = true;
      _errorMessage = 'Failed to load subscription data: $e';
      print('❌ Subscription refresh error: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Check if user requires subscription upgrade
  bool requiresUpgrade() {
    return !hasAppAccess;
  }

  // Updated: API call to get subscription status using new WordPress endpoint
  Future<Map<String, dynamic>> getSubscriptionStatus(int userId) async {
    try {
      final url = '$baseUrl/user/$userId/subscription';
      print('Making API call to: $url');

      final headers = await _getAuthHeaders();

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to get subscription status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error in getSubscriptionStatus: $e');
      rethrow;
    }
  }

  // Check app access using new API
  Future<Map<String, dynamic>> checkAppAccess(int userId) async {
    try {
      final url = '$baseUrl/user/$userId/access';
      print('Checking app access at: $url');

      final headers = await _getAuthHeaders();

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to check app access: ${response.statusCode}');
      }
    } catch (e) {
      print('Error checking app access: $e');
      rethrow;
    }
  }

  // Updated: Get authentication headers with JWT token
  Future<Map<String, String>> _getAuthHeaders() async {
    final userData = await _authService.getSavedUserData();

    if (userData == null || userData['jwt_token'] == null) {
      print('No JWT token found in user data');
      return {
        'Content-Type': 'application/json',
      };
    }

    return {
      'Authorization': 'Bearer ${userData['jwt_token']}',
      'Content-Type': 'application/json',
    };
  }

  // Updated: Get URL for subscription upgrade using new API
  Future<String> getSubscriptionUpgradeUrl() async {
    try {
      final userId = await _authService.getLoggedInUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      final url = '$baseUrl/user/$userId/upgrade-url';
      final headers = await _getAuthHeaders();

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['upgrade_url'] ?? 'https://memre.vortisllc.com/account/';
      } else {
        // Fallback to default URL
        return 'https://memre.vortisllc.com/account/';
      }
    } catch (e) {
      print('Error getting upgrade URL: $e');
      // Fallback to default URL
      return 'https://memre.vortisllc.com/account/';
    }
  }

  // New: Force refresh subscription status
  Future<void> forceRefresh() async {
    await refreshSubscriptionData();
  }

  // New: Check specific feature access
  bool hasFeatureAccess(String featureName) {
    return _features[featureName] ?? hasAppAccess;
  }

  // New: Get trial urgency level for UI
  String get trialUrgency {
    if (!trialActive) return 'expired';
    if (trialDaysRemaining <= 1) return 'critical';
    if (trialDaysRemaining <= 3) return 'urgent';
    if (trialDaysRemaining <= 7) return 'warning';
    return 'normal';
  }

  // New: Get appropriate call-to-action text
  String get ctaText {
    if (premiumActive) return 'Manage Subscription';
    if (trialActive) return 'Upgrade to Premium';
    return 'Subscribe Now';
  }
}
