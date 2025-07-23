import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:MemrE/services/subscription_provider.dart';
import 'dart:async';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({Key? key}) : super(key: key);

  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  // IAP variables
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  static const String kMonthlySubscriptionId = 'com.vortisllc.memre.monthly_subscription';
  List<ProductDetails> _products = [];
  bool _isIAPAvailable = false;
  bool _loading = true;
  String _debugInfo = '';
  
  // Purchase stream subscription
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  @override
  void initState() {
    super.initState();
    _initializeIAP();
    
    // Listen to purchase updates
    _subscription = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription.cancel(),
      onError: (error) => print('Purchase stream error: $error'),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> _initializeIAP() async {
    print('🔄 Initializing IAP...');
    
    final bool isAvailable = await _inAppPurchase.isAvailable();
    print('IAP available: $isAvailable');
    
    if (isAvailable) {
      print('Querying products for ID: $kMonthlySubscriptionId');
      
      final ProductDetailsResponse response = 
          await _inAppPurchase.queryProductDetails({kMonthlySubscriptionId});
      
      print('Product query response:');
      print('- Found products: ${response.productDetails.length}');
      print('- Not found IDs: ${response.notFoundIDs}');
      print('- Error: ${response.error}');
      
      String debugInfo = 'Product ID: $kMonthlySubscriptionId\n';
      debugInfo += 'IAP Available: $isAvailable\n';
      debugInfo += 'Products found: ${response.productDetails.length}\n';
      debugInfo += 'Not found: ${response.notFoundIDs}\n';
      if (response.error != null) {
        debugInfo += 'Error: ${response.error}\n';
      }
      
      if (response.error != null) {
        print('❌ Product query error: ${response.error}');
      }
      
      setState(() {
        _isIAPAvailable = true;
        _products = response.productDetails;
        _loading = false;
        _debugInfo = debugInfo;
      });
      
      print('IAP Products found: ${_products.length}');
      for (var product in _products) {
        print('✅ Product: ${product.id} - ${product.title} - ${product.price}');
        print('   Description: ${product.description}');
        print('   Currency: ${product.currencyCode}');
      }
      
      if (_products.isEmpty) {
        print('❌ No products found! Check:');
        print('1. Product ID matches App Store Connect: $kMonthlySubscriptionId');
        print('2. Product is approved and available');
        print('3. App bundle ID matches');
        print('4. Using correct Apple ID for testing');
      }
    } else {
      print('❌ IAP not available on this device');
      setState(() {
        _isIAPAvailable = false;
        _loading = false;
        _debugInfo = 'IAP not available on this device';
      });
    }
  }

  // Handle purchase updates
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (PurchaseDetails purchaseDetails in purchaseDetailsList) {
      print('Purchase update: ${purchaseDetails.status}');
      
      switch (purchaseDetails.status) {
        case PurchaseStatus.purchased:
          _handleSuccessfulPurchase(purchaseDetails);
          break;
        case PurchaseStatus.error:
          _handlePurchaseError(purchaseDetails);
          break;
        case PurchaseStatus.pending:
          _showPendingUI();
          break;
        case PurchaseStatus.canceled:
          _handlePurchaseCanceled();
          break;
        case PurchaseStatus.restored:
          _handleSuccessfulPurchase(purchaseDetails);
          break;
      }
      
      // Complete the purchase
      if (purchaseDetails.pendingCompletePurchase) {
        _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  void _handleSuccessfulPurchase(PurchaseDetails purchaseDetails) {
    print('✅ Purchase successful: ${purchaseDetails.productID}');
    
    // Update subscription status with your backend
    final subscriptionProvider = Provider.of<SubscriptionProvider>(context, listen: false);
    subscriptionProvider.updateIAPSubscription(
      purchaseDetails.productID, 
      purchaseDetails.purchaseID ?? ''
    );
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Subscription activated successfully!'),
        backgroundColor: Colors.green,
      ),
    );
    
    // Navigate back or refresh
    Navigator.of(context).pop();
  }

  void _handlePurchaseError(PurchaseDetails purchaseDetails) {
    print('❌ Purchase error: ${purchaseDetails.error}');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Purchase failed: ${purchaseDetails.error?.message ?? "Unknown error"}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showPendingUI() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⏳ Purchase pending...'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _handlePurchaseCanceled() {
    print('Purchase canceled by user');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Purchase canceled'),
        backgroundColor: Colors.grey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Options'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current status
            Consumer<SubscriptionProvider>(
              builder: (context, provider, child) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Status',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: provider.statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: provider.statusColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              provider.premiumActive ? Icons.check_circle : Icons.access_time,
                              color: provider.statusColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              provider.statusMessage,
                              style: TextStyle(
                                color: provider.statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // OPTION 1: Website (Primary - More Prominent)
            Card(
              elevation: 4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade50, Colors.blue.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.blue.shade300, width: 2),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'RECOMMENDED',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Spacer(),
                        Icon(Icons.web, color: Colors.blue.shade700, size: 28),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Complete Subscription on Website',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\$8.99/month',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Benefits of website option
                    _buildBenefitItem('✓ Multiple payment options (card, PayPal, etc.)'),
                    _buildBenefitItem('✓ Detailed billing history and receipts'),
                    _buildBenefitItem('✓ Easy subscription management'),
                    _buildBenefitItem('✓ Secure payment processing'),
                    _buildBenefitItem('✓ Instant activation'),
                    
                    const SizedBox(height: 16),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.open_in_browser, color: Colors.white),
                        label: const Text(
                          'Subscribe on Website',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _openWebsiteSubscription,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Divider with "OR"
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey[400])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey[400])),
              ],
            ),

            const SizedBox(height: 20),

            // OPTION 2: In-App Purchase (Secondary - Less Prominent)
            Card(
              elevation: 1,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.phone_iphone, color: Colors.grey[600], size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Subscribe in App',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (!_isIAPAvailable)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'In-app purchases not available',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          _buildDebugInfo(),
                        ],
                      )
                    else if (_products.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _products.first.price,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Charged through your App Store account',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.apple),
                              label: const Text('Subscribe via App Store'),
                              onPressed: () => _purchaseSubscription(_products.first),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(color: Colors.grey.shade400),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No subscription products available',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          _buildDebugInfo(),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _loading = true;
                              });
                              _initializeIAP();
                            },
                            child: Text('Retry Loading Products'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Features included (for both options)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What\'s Included',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    _buildFeatureItem('Unlimited reminders and notifications'),
                    _buildFeatureItem('Email notifications to multiple recipients'),
                    _buildFeatureItem('SMS reminders via your device'),
                    _buildFeatureItem('Photo and file attachments'),
                    _buildFeatureItem('Cloud backup and sync'),
                    _buildFeatureItem('Cancel anytime'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Small disclaimer
            Text(
              'Both subscription options provide identical features and access.',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugInfo() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Debug Info:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            _debugInfo,
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(String benefit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        benefit,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String feature) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(feature)),
        ],
      ),
    );
  }

  void _openWebsiteSubscription() async {
    const url = 'https://memre.vortisllc.com/account/?source=app&action=subscribe';
    
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open website')),
      );
    }
  }

  void _purchaseSubscription(ProductDetails product) async {
    print('🛒 Starting subscription purchase for: ${product.id}');
    
    try {
      // Show loading state
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Processing subscription...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 30),
        ),
      );

      final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
      
      // For subscriptions, use buyNonConsumable
      final bool result = await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      
      print('Purchase initiation result: $result');
      
      if (!result) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initiate purchase'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
    } catch (e) {
      print('❌ Purchase error: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Purchase failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}