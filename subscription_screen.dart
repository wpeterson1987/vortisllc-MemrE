import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'subscription_provider.dart';
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
    // Refresh subscription data when screen loads
    WidgetsBinding.instance?.addPostFrameCallback((_) {
      Provider.of<SubscriptionProvider>(context, listen: false)
          .refreshSubscriptionData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Your Subscription'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              Provider.of<SubscriptionProvider>(context, listen: false)
                  .refreshSubscriptionData();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Provider.of<SubscriptionProvider>(context, listen: false)
              .refreshSubscriptionData();
        },
        child: ListView(
          children: [
            SubscriptionInfoWidget(compact: false),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan Information',
                    style: Theme.of(context).textTheme.headline6,
                  ),
                  _buildPlanFeatures(context),
                  SizedBox(height: 24),
                  Text(
                    'Manage Your Subscription',
                    style: Theme.of(context).textTheme.headline6,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'You can upgrade your plan anytime to increase your SMS limit.',
                    style: Theme.of(context).textTheme.bodyText2,
                  ),
                  SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.open_in_browser),
                      label: Text('Manage Plan on Website'),
                      style: ElevatedButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: _openSubscriptionPage,
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

  Widget _buildPlanFeatures(BuildContext context) {
    final provider = Provider.of<SubscriptionProvider>(context);

    // Define plan features based on subscription tier
    Map<String, List<String>> planFeatures = {
      'Free Trial': [
        'Up to 100 SMS messages per month',
        'Unlimited in-app notifications',
        'Basic reminder functionality',
        'Basic memo storage',
      ],
      'MemrE App': [
        'Up to 100 SMS messages per month',
        'Unlimited in-app notifications',
        'Advanced reminder functionality',
        'Full memo storage and search',
        'Email support',
      ],
      'Premium + 100': [
        'Up to 200 SMS messages per month',
        'All MemrE App features',
        'Priority email support',
      ],
      'Premium + 200': [
        'Up to 300 SMS messages per month',
        'All MemrE App features',
        'Priority email support',
      ],
      'Premium + 300': [
        'Up to 400 SMS messages per month',
        'All MemrE App features',
        'Priority email support',
      ],
      'Premium + 400': [
        'Up to 500 SMS messages per month',
        'All MemrE App features',
        'Priority email support',
      ],
      'Premium + 500': [
        'Up to 600 SMS messages per month',
        'All MemrE App features',
        'Priority email support',
      ],
    };

    // Get features for current plan or default to Free Trial
    List<String> features =
        planFeatures[provider.subscriptionTier] ?? planFeatures['Free Trial']!;

    return Card(
      margin: EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.subscriptionTier + ' Features',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            SizedBox(height: 16),
            ...features
                .map((feature) => Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check, color: Colors.green, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text(feature)),
                        ],
                      ),
                    ))
                .toList(),
          ],
        ),
      ),
    );
  }

  void _openSubscriptionPage() async {
    final provider = Provider.of<SubscriptionProvider>(context, listen: false);
    final url = provider.getSubscriptionUpgradeUrl();

    if (await canLaunch(url)) {
      await launch(
        url,
        forceWebView: true,
        enableJavaScript: true,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open upgrade page')),
      );
    }
  }
}
