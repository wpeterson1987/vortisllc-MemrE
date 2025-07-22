<?php
/**
 * MemrE Simplified Subscription System
 * 
 * Simplified version that only handles:
 * - 14-day free trial
 * - $8.99/month subscription verification
 * No SMS counting or limits needed since SMS is handled locally
 */

/**
 * Get the current subscription status for a user
 * 
 * @param int $user_id The user ID to check
 * @return array The subscription status data
 */
function get_user_subscription_status($user_id) {
    global $wpdb;
    
    // Check if free trial is active
    $is_free_trial = get_user_meta($user_id, 'is_free_trial', true);
    $registration_date = get_user_meta($user_id, 'registration_date', true);
    
    $trial_active = false;
    $trial_days_remaining = 0;
    $trial_end_date = null;
    
    if ($is_free_trial && $registration_date) {
        $reg_date = new DateTime($registration_date);
        $now = new DateTime();
        $trial_end = clone $reg_date;
        $trial_end->add(new DateInterval('P14D'));
        
        $interval = $now->diff($trial_end);
        $trial_days_remaining = max(0, $interval->days);
        $trial_active = ($now <= $trial_end);
        $trial_end_date = $trial_end->format('Y-m-d\TH:i:s\Z');
        
        // If trial has expired, update the metadata
        if (!$trial_active && $is_free_trial) {
            update_user_meta($user_id, 'is_free_trial', false);
        }
    }
    
    // Check for active paid subscription
    $subscription_table = $wpdb->prefix . 'um_stripe_subscriptions';
    $active_subscription = $wpdb->get_row($wpdb->prepare(
        "SELECT * FROM $subscription_table 
         WHERE user_id = %d 
         AND (LOWER(status) = LOWER('active') OR LOWER(status) = LOWER('trialing')) 
         ORDER BY created_at DESC LIMIT 1",
        $user_id
    ));
    
    $has_valid_subscription = !empty($active_subscription);
    $subscription_end_date = null;
    $subscription_tier = 'Free Trial';
    
    if ($has_valid_subscription) {
        $subscription_tier = 'Premium';
        // Calculate next billing date (approximate - 30 days from creation)
        if ($active_subscription->created_at) {
            $created = new DateTime($active_subscription->created_at);
            $next_billing = clone $created;
            $next_billing->add(new DateInterval('P30D'));
            $subscription_end_date = $next_billing->format('Y-m-d\TH:i:s\Z');
        }
        
        // Turn off free trial if they have paid subscription
        if ($is_free_trial) {
            update_user_meta($user_id, 'is_free_trial', false);
        }
    }
    
    return array(
        'subscription_tier' => $subscription_tier,
        'trial_active' => $trial_active,
        'trial_days_remaining' => $trial_days_remaining,
        'has_valid_subscription' => $has_valid_subscription,
        'trial_end_date' => $trial_end_date,
        'subscription_end_date' => $subscription_end_date
    );
}

/**
 * Check if user has access to the app (trial or paid)
 * 
 * @param int $user_id The user ID to check
 * @return bool True if user has access, false otherwise
 */
function user_has_app_access($user_id) {
    $status = get_user_subscription_status($user_id);
    return $status['trial_active'] || $status['has_valid_subscription'];
}

/**
 * REST API endpoint for getting subscription status
 * 
 * @param WP_REST_Request $request The REST request
 * @return array The subscription status data
 */
function get_subscription_status($request) {
    $user_id = $request['user_id'];
    return get_user_subscription_status($user_id);
}

/**
 * Handle subscription creation/update from Stripe
 * 
 * @param int $user_id The user ID
 * @param string $subscription_id The subscription ID
 * @param string $plan_id The plan ID
 * @return void
 */
function handle_subscription_created($user_id, $subscription_id, $plan_id) {
    // Log the event
    $log_dir = WP_CONTENT_DIR . '/subscription-logs';
    if (!file_exists($log_dir)) {
        mkdir($log_dir, 0755, true);
    }
    
    $log_file = $log_dir . '/subscription-events.log';
    $log_data = date('[Y-m-d H:i:s]') . " Subscription created: User ID: $user_id, Sub ID: $subscription_id, Plan ID: $plan_id\n";
    file_put_contents($log_file, $log_data, FILE_APPEND);
    
    // Update user role to premium
    $user = new WP_User($user_id);
    $user->set_role('um_memre-app'); // or whatever your premium role is
    
    // Turn off free trial
    update_user_meta($user_id, 'is_free_trial', false);
    
    // Update subscription plan name
    update_user_meta($user_id, 'subscription_plan_name', 'Premium');
    
    file_put_contents($log_file, "Updated user $user_id to Premium subscription\n", FILE_APPEND);
}

/**
 * Handle subscription cancellation
 * 
 * @param int $user_id The user ID
 * @return bool Success or failure
 */
function handle_canceled_subscription($user_id) {
    global $wpdb;
    
    // Check if the user has a canceled subscription
    $subscription_table = $wpdb->prefix . 'um_stripe_subscriptions';
    $canceled_subscription = $wpdb->get_row($wpdb->prepare(
        "SELECT * FROM $subscription_table 
         WHERE user_id = %d 
         AND LOWER(status) = LOWER('canceled') 
         ORDER BY date_created DESC LIMIT 1",
        $user_id
    ));
    
    if ($canceled_subscription) {
        // Set user role back to free trial
        $user = new WP_User($user_id);
        $user->set_role('um_free-trial');
        
        // Update user meta
        update_user_meta($user_id, 'subscription_plan_name', 'Free Trial');
        update_user_meta($user_id, 'is_free_trial', true);
        
        // Set a flag to indicate the user needs redirection
        update_user_meta($user_id, 'redirect_after_cancellation', '1');
        
        return true;
    }
    
    return false;
}

/**
 * Initialize trial for new user
 * 
 * @param int $user_id The user ID to initialize
 * @return void
 */
function initialize_user_trial($user_id) {
    // Set free trial metadata
    update_user_meta($user_id, 'is_free_trial', true);
    update_user_meta($user_id, 'registration_date', current_time('mysql'));
    
    // Set user role
    $user = new WP_User($user_id);
    $user->set_role('um_free-trial');
    
    // Send welcome email
    send_trial_welcome_email($user_id);
}

/**
 * Send trial welcome email
 * 
 * @param int $user_id The user ID
 * @return void
 */
function send_trial_welcome_email($user_id) {
    $user = get_userdata($user_id);
    if (!$user) return;
    
    $to = $user->user_email;
    $subject = 'Welcome to Your MemrE 14-Day Free Trial!';
    $message = "Hi " . $user->display_name . ",\n\n";
    $message .= "Welcome to MemrE! Your 14-day free trial has begun.\n\n";
    $message .= "During your trial, you have full access to all MemrE features including:\n";
    $message .= "• Unlimited reminders and notifications\n";
    $message .= "• Email reminders with attachments\n";
    $message .= "• SMS reminders (sent through your device)\n";
    $message .= "• Photo and file attachments\n";
    $message .= "• Cloud backup and sync\n\n";
    $message .= "Your trial will expire on " . date('F j, Y', strtotime('+14 days')) . ".\n\n";
    $message .= "To continue using MemrE after your trial, subscribe for just \$8.99/month.\n\n";
    $message .= "Thank you,\nThe MemrE Team";
    
    wp_mail($to, $subject, $message);
}

/**
 * Check for and update expired free trials
 * 
 * @return void
 */
function check_and_update_free_trials() {
    // Get all users with free trial status
    $users = get_users(array(
        'meta_key' => 'is_free_trial',
        'meta_value' => true
    ));
    
    foreach ($users as $user) {
        $registration_date = get_user_meta($user->ID, 'registration_date', true);
        if (!$registration_date) continue;
        
        $reg_date = new DateTime($registration_date);
        $now = new DateTime();
        $interval = $reg_date->diff($now);
        
        // If more than 14 days have passed
        if ($interval->days > 14) {
            // Update user status - free trial expired
            update_user_meta($user->ID, 'is_free_trial', false);
            
            // Send notification email
            $to = $user->user_email;
            $subject = 'Your MemrE Free Trial Has Expired';
            $message = "Hi " . $user->display_name . ",\n\n";
            $message .= "Your 14-day free trial has ended.\n\n";
            $message .= "To continue using all MemrE features, please subscribe for \$8.99/month.\n\n";
            $message .= "Subscribe now: " . home_url('/subscription-upgrade/') . "\n\n";
            $message .= "Thank you,\nThe MemrE Team";
            
            wp_mail($to, $subject, $message);
        }
    }
}

/**
 * Simplified subscription options shortcode
 * 
 * @return string The HTML output of the subscription options
 */
function simple_subscription_shortcode() {
    if (!is_user_logged_in()) {
        return 'You must be logged in to view subscription options.';
    }
    
    $user_id = get_current_user_id();
    $status = get_user_subscription_status($user_id);
    
    // Check if user has an active subscription
    global $wpdb;
    $subscription_table = $wpdb->prefix . 'um_stripe_subscriptions';
    $has_subscription = $wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM $subscription_table 
         WHERE user_id = %d 
         AND (LOWER(status) = LOWER('active') OR LOWER(status) = LOWER('trialing'))",
        $user_id
    ));
    
    $output = '<div class="memre-subscription-container">';
    $output .= '<h2>MemrE Subscription</h2>';
    
    // Show current status
    if ($status['trial_active']) {
        $output .= '<div class="trial-status">';
        $output .= '<h3>🎉 Free Trial Active</h3>';
        $output .= '<p>You have <strong>' . $status['trial_days_remaining'] . ' days</strong> remaining in your free trial.</p>';
        $output .= '<p>After your trial ends, subscribe for <strong>$8.99/month</strong> to continue using MemrE.</p>';
        $output .= '</div>';
    } elseif ($status['has_valid_subscription']) {
        $output .= '<div class="active-subscription">';
        $output .= '<h3>✅ Active Subscription</h3>';
        $output .= '<p>Your subscription is active. You have full access to all MemrE features.</p>';
        $output .= '<p><strong>$8.99/month</strong></p>';
        $output .= '</div>';
    } else {
        $output .= '<div class="subscription-needed">';
        $output .= '<h3>⚠️ Subscription Required</h3>';
        $output .= '<p>Your free trial has ended. Subscribe to continue using MemrE.</p>';
        $output .= '</div>';
    }
    
    // Show features
    $output .= '<div class="features-section">';
    $output .= '<h3>What You Get:</h3>';
    $output .= '<ul class="features-list">';
    $output .= '<li>✓ Unlimited reminders and notifications</li>';
    $output .= '<li>✓ Email reminders with attachments</li>';
    $output .= '<li>✓ SMS reminders (via your device - no extra charges!)</li>';
    $output .= '<li>✓ Photo and file attachments</li>';
    $output .= '<li>✓ Share content from other apps</li>';
    $output .= '<li>✓ Recurring reminders</li>';
    $output .= '<li>✓ Cloud backup and sync</li>';
    $output .= '</ul>';
    $output .= '</div>';
    
    // Show action buttons
    $output .= '<div class="action-section">';
    
    if ($has_subscription) {
        $output .= '<p>To modify your subscription, please use the link below:</p>';
        $billing_url = 'https://memre.vortisllc.com/account/billings/';
        $output .= '<p><a href="' . esc_url($billing_url) . '" class="button button-primary">Manage Subscription</a></p>';
    } else {
        $output .= '<div class="subscribe-section">';
        $output .= '<h3>Subscribe Now - $8.99/month</h3>';
        $output .= '<p>Simple, affordable pricing with no hidden fees.</p>';
        $output .= '<a href="https://memre.vortisllc.com?um_stripe_plan_id=88" class="button button-primary button-large">Subscribe for $8.99/month</a>';
        $output .= '</div>';
    }
    
    $output .= '</div>'; // Close action-section
    $output .= '</div>'; // Close container
    
    // Add CSS
    $output .= '<style>
        .memre-subscription-container {
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        }
        .trial-status, .active-subscription, .subscription-needed {
            background: #f8f9fa;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
            border-left: 4px solid #007cba;
        }
        .subscription-needed {
            border-left-color: #d63638;
        }
        .features-section {
            background: #ffffff;
            border: 1px solid #e1e1e1;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .features-list {
            list-style: none;
            padding: 0;
        }
        .features-list li {
            padding: 8px 0;
            border-bottom: 1px solid #f0f0f0;
        }
        .features-list li:last-child {
            border-bottom: none;
        }
        .subscribe-section {
            background: #e7f3ff;
            border-radius: 8px;
            padding: 20px;
            text-align: center;
        }
        .button {
            display: inline-block;
            background: #007cba;
            color: white;
            padding: 12px 24px;
            border-radius: 4px;
            text-decoration: none;
            font-weight: 500;
            transition: background 0.3s ease;
        }
        .button:hover {
            background: #005a87;
            color: white;
        }
        .button-large {
            padding: 16px 32px;
            font-size: 18px;
        }
        .button-primary {
            background: #007cba;
        }
    </style>';
    
    return $output;
}

/**
 * Handle Stripe webhook events for subscription changes
 * 
 * @param string $event_type The event type
 * @param object $event_data The event data
 * @return void
 */
function handle_stripe_webhook_event($event_type, $event_data) {
    $log_dir = WP_CONTENT_DIR . '/subscription-logs';
    if (!file_exists($log_dir)) {
        mkdir($log_dir, 0755, true);
    }
    
    $log_file = $log_dir . '/stripe-events.log';
    file_put_contents($log_file, date('[Y-m-d H:i:s]') . " Event: $event_type\n", FILE_APPEND);
    
    // Handle subscription created or updated
    if ($event_type === 'customer.subscription.created' || $event_type === 'customer.subscription.updated') {
        if (isset($event_data->data->object)) {
            $subscription = $event_data->data->object;
            $customer_id = $subscription->customer;
            $status = $subscription->status;
            
            // Find WordPress user by Stripe customer ID
            global $wpdb;
            $user_id = $wpdb->get_var($wpdb->prepare(
                "SELECT user_id FROM {$wpdb->usermeta} 
                 WHERE meta_key = 'um_stripe_customer_id' 
                 AND meta_value = %s LIMIT 1",
                $customer_id
            ));
            
            if ($user_id && $status === 'active') {
                handle_subscription_created($user_id, $subscription->id, 'premium');
            }
        }
    } 
    // Handle subscription cancellation
    elseif ($event_type === 'customer.subscription.deleted') {
        if (isset($event_data->data->object)) {
            $subscription = $event_data->data->object;
            $customer_id = $subscription->customer;
            
            // Find WordPress user by Stripe customer ID
            global $wpdb;
            $user_id = $wpdb->get_var($wpdb->prepare(
                "SELECT user_id FROM {$wpdb->usermeta} 
                 WHERE meta_key = 'um_stripe_customer_id' 
                 AND meta_value = %s LIMIT 1",
                $customer_id
            ));
            
            if ($user_id) {
                handle_canceled_subscription($user_id);
            }
        }
    }
    
    file_put_contents($log_file, "---------------------\n", FILE_APPEND);
}

/**
 * Sync user subscription status (simplified version)
 * 
 * @param int $user_id The user ID to sync
 * @return bool True on success
 */
function sync_user_subscription($user_id) {
    global $wpdb;
    
    // Check for active subscriptions
    $subscription_table = $wpdb->prefix . 'um_stripe_subscriptions';
    $subscription = $wpdb->get_row($wpdb->prepare(
        "SELECT * FROM $subscription_table 
         WHERE user_id = %d 
         AND (LOWER(status) = LOWER('active') OR LOWER(status) = LOWER('trialing')) 
         ORDER BY date_created DESC LIMIT 1",
        $user_id
    ));
    
    if ($subscription) {
        // User has active subscription
        $user = new WP_User($user_id);
        $user->set_role('um_memre-app');
        
        update_user_meta($user_id, 'subscription_plan_name', 'Premium');
        update_user_meta($user_id, 'is_free_trial', false);
        
        return true;
    } else {
        // Check for canceled subscription
        return handle_canceled_subscription($user_id);
    }
}

/**
 * Register simplified subscription hooks and endpoints
 * 
 * @return void
 */
function register_simplified_subscription_hooks() {
    // Register shortcodes
    add_shortcode('memre_subscription', 'simple_subscription_shortcode');
    add_shortcode('subscription_status', 'simple_subscription_shortcode');
    
    // Hook into Ultimate Member events
    add_action('um_registration_complete', 'initialize_user_trial', 99, 1);
    add_action('um_after_user_is_approved', 'initialize_user_trial', 10, 1);
    
    // Hook into Stripe events
    add_action('um_stripe_webhook_event', 'handle_stripe_webhook_event', 10, 2);
    add_action('um_stripe_after_subscription_created', 'handle_subscription_created', 10, 3);
    
    // Schedule trial checks
    add_action('wp', 'schedule_trial_checks');
    add_action('check_trial_expiration', 'check_and_update_free_trials');
    
    // REST API endpoints
    add_action('rest_api_init', function() {
        register_rest_route('memre-app/v1', '/subscription-status/(?P<user_id>\d+)', array(
            'methods' => 'GET',
            'callback' => 'get_subscription_status',
            'permission_callback' => 'check_user_auth',
            'args' => array(
                'user_id' => array(
                    'validate_callback' => function($param) {
                        return is_numeric($param);
                    }
                )
            )
        ));
    });
}

/**
 * Schedule trial expiration checks
 * 
 * @return void
 */
function schedule_trial_checks() {
    if (!wp_next_scheduled('check_trial_expiration')) {
        wp_schedule_event(time(), 'daily', 'check_trial_expiration');
    }
}

/**
 * Check user authorization for API endpoints
 * 
 * @param WP_REST_Request $request The REST request
 * @return bool Whether the user is authorized
 */
function check_user_auth($request) {
    $user_id = $request['user_id'];
    $current_user_id = get_current_user_id();
    
    return ($current_user_id == $user_id) || current_user_can('administrator');
}

// Initialize the simplified subscription system
register_simplified_subscription_hooks();