import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/subscription_provider.dart';

class SubscriptionInfoWidget extends StatelessWidget {
  final bool compact;

  const SubscriptionInfoWidget({Key? key, this.compact = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading subscription status...'),
                ],
              ),
            ),
          );
        }

        if (provider.hasError && !compact) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'Subscription Status Error',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(provider.errorMessage),
                  SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => provider.refreshSubscriptionData(),
                    child: Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        // Don't show anything in compact mode if there's an error
        if (provider.hasError && compact) {
          return SizedBox.shrink();
        }

        return Card(
          margin: EdgeInsets.all(compact ? 8.0 : 16.0),
          color: _getBackgroundColor(provider),
          child: Padding(
            padding: EdgeInsets.all(compact ? 12.0 : 16.0),
            child: compact
                ? _buildCompactView(provider, context)
                : _buildFullView(provider, context),
          ),
        );
      },
    );
  }

  Color _getBackgroundColor(SubscriptionProvider provider) {
    if (provider.premiumActive) {
      return Colors.green.shade50;
    } else if (provider.trialActive) {
      switch (provider.trialUrgency) {
        case 'critical':
          return Colors.red.shade50;
        case 'urgent':
          return Colors.orange.shade50;
        case 'warning':
          return Colors.yellow.shade50;
        default:
          return Colors.blue.shade50;
      }
    } else {
      return Colors.red.shade50;
    }
  }

  Widget _buildCompactView(
      SubscriptionProvider provider, BuildContext context) {
    return Row(
      children: [
        Icon(
          _getStatusIcon(provider),
          color: provider.statusColor,
          size: 20,
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            provider.statusMessage,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: provider.statusColor,
            ),
          ),
        ),
        if (provider.requiresUpgrade() ||
            (provider.trialActive && provider.trialDaysRemaining <= 3))
          TextButton(
            onPressed: () => _openSubscriptionPage(context),
            child: Text('Upgrade'),
          ),
      ],
    );
  }

  Widget _buildFullView(SubscriptionProvider provider, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _getStatusIcon(provider),
              color: provider.statusColor,
              size: 24,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                provider.statusMessage,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: provider.statusColor,
                ),
              ),
            ),
          ],
        ),

        SizedBox(height: 16),

        // Status-specific content
        if (provider.premiumActive) ...[
          _buildPremiumContent(provider),
        ] else if (provider.trialActive) ...[
          _buildTrialContent(provider, context),
        ] else ...[
          _buildExpiredContent(provider, context),
        ],

        SizedBox(height: 16),

        // Action button - now opens subscription page directly
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _openSubscriptionPage(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: provider.statusColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(provider.ctaText),
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumContent(SubscriptionProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Thank you for being a MemrE Premium member!',
          style: TextStyle(
            fontSize: 16,
            color: Colors.green.shade700,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'You have unlimited access to all MemrE features.',
          style: TextStyle(color: Colors.green.shade600),
        ),
      ],
    );
  }

  Widget _buildTrialContent(
      SubscriptionProvider provider, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider.trialEndDate != null)
          Text(
            'Your trial expires on ${_formatDate(provider.trialEndDate!)}',
            style: TextStyle(
              fontSize: 16,
              color: provider.statusColor,
            ),
          ),
        SizedBox(height: 8),
        Text(
          'Upgrade to MemrE Premium to continue enjoying unlimited access after your trial ends.',
          style: TextStyle(color: Colors.grey[700]),
        ),
        if (provider.trialDaysRemaining <= 3) ...[
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your trial expires soon! Upgrade now to avoid losing access.',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExpiredContent(
      SubscriptionProvider provider, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your trial has expired.',
          style: TextStyle(
            fontSize: 16,
            color: Colors.red.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Subscribe to MemrE Premium to restore full access to your memos and features.',
          style: TextStyle(color: Colors.grey[700]),
        ),
        SizedBox(height: 12),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.backup, color: Colors.blue.shade700, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your data is safely stored and will be restored when you upgrade!',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getStatusIcon(SubscriptionProvider provider) {
    if (provider.premiumActive) return Icons.check_circle;
    if (provider.trialActive) return Icons.schedule;
    return Icons.lock;
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  // Updated method to open subscription page directly instead of navigating to subscription screen
  void _openSubscriptionPage(BuildContext context) async {
    try {
      final provider =
          Provider.of<SubscriptionProvider>(context, listen: false);
      final url = await provider.getSubscriptionUpgradeUrl();

      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.inAppWebView,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
          ),
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
}

// 3. UPDATED APP ACCESS CHECK HELPER
class AppAccessHelper {
  static Future<bool> checkFeatureAccess(
      BuildContext context, String featureName) async {
    final provider = Provider.of<SubscriptionProvider>(context, listen: false);

    // Refresh subscription status to get latest info
    await provider.refreshSubscriptionData();

    if (!provider.hasAppAccess) {
      _showUpgradeDialog(context, provider);
      return false;
    }

    return true;
  }

  static void _showUpgradeDialog(
      BuildContext context, SubscriptionProvider provider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
              provider.trialExpired ? 'Trial Expired' : 'Upgrade Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                provider.trialExpired ? Icons.lock : Icons.star,
                size: 48,
                color: provider.trialExpired ? Colors.red : Colors.blue,
              ),
              SizedBox(height: 16),
              Text(
                provider.trialExpired
                    ? 'Your trial has expired. Upgrade to MemrE Premium to restore access.'
                    : 'Upgrade to MemrE Premium for unlimited access to all features.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Maybe Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushNamed(context, '/subscription');
              },
              child: Text('Upgrade Now'),
            ),
          ],
        );
      },
    );
  }
}
