import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class SubscriptionProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final String baseUrl = 'https://memre.vortisllc.com/wp-json/memre/v1';

  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  // Subscription status fields
  String _subscriptionTier = 'Trial';
  bool _trialActive = true;
  int _trialDaysRemaining = 14;
  bool _premiumActive = false;
  bool _trialExpired = false;
  DateTime? _trialEndDate;
  String? _registrationDate;
  String? _stripeCustomerId;
  Map<String, bool> _features = {};
  
  // NEW: Track subscription source
  String _subscriptionSource = 'none'; // 'stripe', 'apple_iap', 'none'
  bool _hasIAPSubscription = false;
  bool _hasStripeSubscription = false;

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
  
  // NEW: Subscription source getters
  String get subscriptionSource => _subscriptionSource;
  bool get hasIAPSubscription => _hasIAPSubscription;
  bool get hasStripeSubscription => _hasStripeSubscription;
  bool get hasActiveSubscription => _hasIAPSubscription || _hasStripeSubscription;

  // Updated: Check if user has access to the app
  bool get hasAppAccess => trialActive || premiumActive || hasActiveSubscription;

  // Updated: More specific status messages
  String get statusMessage {
    if (_hasIAPSubscription) {
      return 'MemrE Premium (App Store)';
    } else if (_hasStripeSubscription) {
      return 'MemrE Premium (Website)';
    } else if (premiumActive) {
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
    if (hasActiveSubscription || premiumActive) return Colors.green;
    if (trialActive && trialDaysRemaining > 3) return Colors.blue;
    if (trialActive && trialDaysRemaining <= 3) return Colors.orange;
    return Colors.red;
  }

  // NEW: Get trial urgency level for UI (FIXES THE ERROR)
  String get trialUrgency {
    if (!trialActive) return 'expired';
    if (trialDaysRemaining <= 1) return 'critical';
    if (trialDaysRemaining <= 3) return 'urgent';
    if (trialDaysRemaining <= 7) return 'warning';
    return 'normal';
  }

  // NEW: Determine what subscription options to show
  bool get shouldShowIAPOptions {
    // Show IAP options if:
    // 1. User has no active subscription, OR
    // 2. User was registered through the app (not website)
    return !hasActiveSubscription || _subscriptionSource == 'none';
  }

  bool get shouldShowWebsiteManagement {
    // Show website management if user has Stripe subscription
    return _hasStripeSubscription;
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

      // Call the WordPress API endpoint
      final subscriptionData = await getSubscriptionStatus(userId);
      print('📦 Received subscription data: $subscriptionData');

      // Update state based on API response
      _subscriptionTier = subscriptionData['subscription_tier'] ?? 'Trial';
      _trialActive = subscriptionData['trial_active'] ?? false;
      _trialDaysRemaining = subscriptionData['trial_days_remaining'] ?? 0;
      _premiumActive = subscriptionData['premium_active'] ?? false;
      _trialExpired = subscriptionData['trial_expired'] ?? false;
      _registrationDate = subscriptionData['registration_date'];
      _stripeCustomerId = subscriptionData['stripe_customer_id'];

      // NEW: Handle subscription source detection
      _hasStripeSubscription = subscriptionData['has_stripe_subscription'] ?? false;
      _hasIAPSubscription = subscriptionData['has_iap_subscription'] ?? false;
      
      if (_hasStripeSubscription) {
        _subscriptionSource = 'stripe';
      } else if (_hasIAPSubscription) {
        _subscriptionSource = 'apple_iap';
      } else {
        _subscriptionSource = 'none';
      }

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
      print('- Has Stripe subscription: $_hasStripeSubscription');
      print('- Has IAP subscription: $_hasIAPSubscription');
      print('- Subscription source: $_subscriptionSource');
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

  // API call to get subscription status
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

  // NEW: Update subscription after IAP purchase
  Future<void> updateIAPSubscription(String productId, String transactionId) async {
    try {
      final userId = await _authService.getLoggedInUserId();
      if (userId == null) return;

      final url = '$baseUrl/user/$userId/iap-subscription';
      final headers = await _getAuthHeaders();

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode({
          'product_id': productId,
          'transaction_id': transactionId,
          'platform': 'ios',
        }),
      );

      if (response.statusCode == 200) {
        // Refresh subscription data
        await refreshSubscriptionData();
      }
    } catch (e) {
      print('Error updating IAP subscription: $e');
    }
  }

  // Get authentication headers with JWT token
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

  // UPDATED: Get URL for subscription management (REVENUE OPTIMIZED)
  Future<String> getSubscriptionUpgradeUrl() async {
    try {
      final userId = await _authService.getLoggedInUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      // ALWAYS return the website URL for revenue optimization
      final baseWebsiteUrl = 'https://memre.vortisllc.com/account/';
      
      // Add parameters to help with user experience and tracking
      final websiteUrl = '$baseWebsiteUrl?source=ios_app&user_id=$userId&action=upgrade';
      
      return websiteUrl;
    } catch (e) {
      print('Error getting upgrade URL: $e');
      // Fallback to default URL
      return 'https://memre.vortisllc.com/account/?source=ios_app&action=upgrade';
    }
  }

  // NEW: Get website management URL (only for Stripe subscribers)
  Future<String> getWebsiteManagementUrl() async {
    try {
      final userId = await _authService.getLoggedInUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      return 'https://memre.vortisllc.com/account/?user_id=$userId&source=app&action=manage';
    } catch (e) {
      print('Error getting website management URL: $e');
      return 'https://memre.vortisllc.com/account/';
    }
  }

  // NEW: Clear all subscription state data
  Future<void> clearState() async {
    print('🧹 Clearing subscription state...');

    _isLoading = false;
    _hasError = false;
    _errorMessage = '';
    _subscriptionTier = 'Trial';
    _trialActive = true;
    _trialDaysRemaining = 14;
    _premiumActive = false;
    _trialExpired = false;
    _trialEndDate = null;
    _registrationDate = null;
    _stripeCustomerId = null;
    _features = {};
    _subscriptionSource = 'none';
    _hasIAPSubscription = false;
    _hasStripeSubscription = false;

    print('✅ Subscription state cleared');
    notifyListeners();
  }

  // Force refresh subscription status
  Future<void> forceRefresh() async {
    await refreshSubscriptionData();
  }

  // Check specific feature access
  bool hasFeatureAccess(String featureName) {
    return _features[featureName] ?? hasAppAccess;
  }

  // UPDATED: Get appropriate call-to-action text (Apple compliant)
  String get ctaText {
    if (hasActiveSubscription) {
      return _hasStripeSubscription ? 'Manage on Website' : 'Manage Subscription';
    } else if (trialActive) {
      return 'Subscribe Now';
    } else {
      return 'Subscribe Now';
    }
  }

  // NEW: Get compliance-friendly button text
  String get subscriptionButtonText {
    if (hasActiveSubscription) {
      return _hasStripeSubscription 
          ? 'Manage Subscription on Website'
          : 'Manage Subscription';
    } else if (trialActive) {
      return 'Subscribe for \$8.99/month';
    } else {
      return 'Subscribe for \$8.99/month';
    }
  }
}