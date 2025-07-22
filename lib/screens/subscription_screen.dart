import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:MemrE/services/subscription_provider.dart';
import 'package:MemrE/screens/widgets/subscription_info_widget.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({Key? key}) : super(key: key);

  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh data when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SubscriptionProvider>(context, listen: false)
          .refreshSubscriptionData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                Provider.of<SubscriptionProvider>(context, listen: false)
                    .refreshSubscriptionData(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Provider.of<SubscriptionProvider>(context, listen: false)
              .refreshSubscriptionData();
        },
        child: Consumer<SubscriptionProvider>(
          builder: (context, provider, child) {
            return ListView(
              children: [
                // Main subscription info widget
                const SubscriptionInfoWidget(),

                // Action buttons section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (provider.requiresUpgrade()) ...[
                        // Website subscription button
                        _buildSubscribeButton(context),
                        const SizedBox(height: 12),
                        Text(
                          'Subscription management is handled on our website for security and convenience.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ] else ...[
                        // Manage subscription button for existing subscribers
                        _buildManageSubscriptionButton(context),
                        const SizedBox(height: 12),
                        Text(
                          'Access your subscription settings and billing information.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Pricing info
                      _buildPricingCard(),

                      const SizedBox(height: 24),

                      // FAQ section
                      _buildFaqSection(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSubscribeButton(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.open_in_browser),
      label: const Text('Subscribe on Our Website - \$8.99/month'),
      onPressed: () => _openSubscriptionWebsite(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildManageSubscriptionButton(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.open_in_browser),
      label: const Text('Manage Subscription on Website'),
      onPressed: () => _openAccountManagement(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPricingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments, color: Theme.of(context).primaryColor),
                const SizedBox(width: 12),
                Text(
                  'Simple Pricing',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Free trial
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '14-Day Free Trial',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Full access to all features for 14 days',
                    style: TextStyle(color: Colors.blue.shade700),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Monthly subscription
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.star, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '\$8.99/month',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Unlimited access to all MemrE features',
                    style: TextStyle(color: Colors.green.shade700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Secure payment processing via our website',
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Frequently Asked Questions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildFaqItem(
              'Why do I need to subscribe on the website?',
              'For security and convenience, all subscription management is handled through our secure website. This ensures your payment information is protected and gives you access to detailed billing history.',
            ),
            _buildFaqItem(
              'What happens after my free trial?',
              'After your 14-day free trial ends, you\'ll need to subscribe for \$8.99/month on our website to continue using MemrE. Your data will be preserved.',
            ),
            _buildFaqItem(
              'Can I cancel anytime?',
              'Yes, you can cancel your subscription at any time through your account page on our website. You\'ll continue to have access until the end of your billing period.',
            ),
            _buildFaqItem(
              'Are SMS messages really free?',
              'Yes! SMS reminders are sent directly from your device using your carrier\'s messaging, so there are no additional SMS charges from MemrE.',
            ),
            _buildFaqItem(
              'What features are included?',
              'All features are included: unlimited reminders, email notifications, SMS via your device, photo attachments, sharing, and cloud backup.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            answer,
            style: TextStyle(
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _openSubscriptionWebsite(BuildContext context) async {
    try {
      final provider =
          Provider.of<SubscriptionProvider>(context, listen: false);
      final url = await provider.getSubscriptionUpgradeUrl();

      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication, // Changed to external browser
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open subscription page')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _openAccountManagement(BuildContext context) async {
    try {
      const url = 'https://memre.vortisllc.com/account/';

      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication, // Changed to external browser
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open account management page')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}