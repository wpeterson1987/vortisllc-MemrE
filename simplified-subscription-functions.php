/**
 * Simple Subscription Options Shortcode
 */
add_shortcode('simple_subscription_options', 'simple_subscription_options_shortcode');
function simple_subscription_options_shortcode($atts) {
    // Set default attributes
    $atts = shortcode_atts(array(
        'show_trial' => 'true',
        'show_pricing' => 'true',
        'redirect_url' => '',
        'class' => 'simple-subscription-options'
    ), $atts);
    
    // Start output buffering
    ob_start();
    
    // Check if user is logged in
    $current_user_id = get_current_user_id();
    $is_logged_in = $current_user_id > 0;
    
    if ($is_logged_in) {
        // Get user subscription status
        $subscription_status = get_user_subscription_status($current_user_id);
        $has_active_subscription = $subscription_status['has_valid_subscription'];
        $trial_active = $subscription_status['trial_active'];
        $trial_days_remaining = $subscription_status['trial_days_remaining'];
    }
    
    ?>
    <div class="<?php echo esc_attr($atts['class']); ?>">
        <?php if ($is_logged_in): ?>
            <?php if ($has_active_subscription): ?>
                <div class="subscription-active">
                    <h3>Active Subscription</h3>
                    <p>You currently have an active subscription.</p>
                    <p><strong>Plan:</strong> <?php echo esc_html($subscription_status['subscription_tier']); ?></p>
                    <?php if (function_exists('um_is_core_page') && !um_is_core_page('account')): ?>
                        <a href="<?php echo esc_url(um_get_core_page('account')); ?>?um_tab=billing" class="button">Manage Subscription</a>
                    <?php endif; ?>
                </div>
            <?php elseif ($trial_active && $atts['show_trial'] === 'true'): ?>
                <div class="trial-active">
                    <h3>Free Trial Active</h3>
                    <p>You have <?php echo esc_html($trial_days_remaining); ?> days remaining in your free trial.</p>
                    <a href="<?php echo esc_url(home_url('/subscription-upgrade/')); ?>" class="button button-primary">Upgrade to Premium</a>
                </div>
            <?php else: ?>
                <div class="subscription-options">
                    <h3>Choose Your Plan</h3>
                    <?php if ($atts['show_pricing'] === 'true'): ?>
                        <div class="pricing-plans">
                            <div class="plan basic-plan">
                                <h4>Basic Plan</h4>
                                <div class="price">$9.99/month</div>
                                <ul class="features">
                                    <li>Unlimited Memos</li>
                                    <li>Email Reminders</li>
                                    <li>File Attachments</li>
                                </ul>
                                <a href="<?php echo esc_url(home_url('/subscription-upgrade/?plan=basic')); ?>" class="button">Choose Basic</a>
                            </div>
                            
                            <div class="plan premium-plan featured">
                                <h4>Premium Plan</h4>
                                <div class="price">$19.99/month</div>
                                <ul class="features">
                                    <li>Everything in Basic</li>
                                    <li>SMS Reminders</li>
                                    <li>Advanced Scheduling</li>
                                    <li>Priority Support</li>
                                </ul>
                                <a href="<?php echo esc_url(home_url('/subscription-upgrade/?plan=premium')); ?>" class="button button-primary">Choose Premium</a>
                            </div>
                        </div>
                    <?php else: ?>
                        <p>Select a subscription plan to access premium features.</p>
                        <a href="<?php echo esc_url(home_url('/subscription-upgrade/')); ?>" class="button button-primary">View Plans</a>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
        <?php else: ?>
            <div class="login-required">
                <h3>Login Required</h3>
                <p>Please log in to view subscription options.</p>
                <a href="<?php echo esc_url(wp_login_url(get_permalink())); ?>" class="button">Login</a>
                <a href="<?php echo esc_url(wp_registration_url()); ?>" class="button">Register</a>
            </div>
        <?php endif; ?>
    </div>
    
    <style>
    .simple-subscription-options {
        max-width: 800px;
        margin: 20px auto;
        padding: 20px;
    }
    
    .pricing-plans {
        display: flex;
        gap: 20px;
        margin-top: 20px;
        flex-wrap: wrap;
    }
    
    .plan {
        flex: 1;
        min-width: 250px;
        padding: 30px 20px;
        border: 2px solid #e1e1e1;
        border-radius: 8px;
        text-align: center;
        background: #fff;
    }
    
    .plan.featured {
        border-color: #0073aa;
        position: relative;
    }
    
    .plan.featured::before {
        content: "Most Popular";
        position: absolute;
        top: -10px;
        left: 50%;
        transform: translateX(-50%);
        background: #0073aa;
        color: white;
        padding: 5px 15px;
        border-radius: 4px;
        font-size: 12px;
    }
    
    .plan h4 {
        margin: 0 0 10px 0;
        font-size: 24px;
    }
    
    .price {
        font-size: 32px;
        font-weight: bold;
        color: #0073aa;
        margin-bottom: 20px;
    }
    
    .features {
        list-style: none;
        padding: 0;
        margin: 20px 0;
    }
    
    .features li {
        padding: 8px 0;
        border-bottom: 1px solid #f1f1f1;
    }
    
    .features li:last-child {
        border-bottom: none;
    }
    
    .button {
        display: inline-block;
        padding: 12px 24px;
        background: #f1f1f1;
        color: #333;
        text-decoration: none;
        border-radius: 4px;
        margin: 5px;
        transition: background 0.3s;
    }
    
    .button-primary {
        background: #0073aa;
        color: white;
    }
    
    .button:hover {
        background: #e1e1e1;
    }
    
    .button-primary:hover {
        background: #005177;
    }
    
    .subscription-active,
    .trial-active,
    .login-required {
        text-align: center;
        padding: 30px;
        background: #f9f9f9;
        border-radius: 8px;
    }
    
    @media (max-width: 600px) {
        .pricing-plans {
            flex-direction: column;
        }
        
        .plan {
            min-width: auto;
        }
    }
    </style>
    <?php
    
    return ob_get_clean();
}