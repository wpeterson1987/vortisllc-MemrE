<?php
/**
 * Kadence functions and definitions
 *
 * This file must be parseable by PHP 5.2.
 *
 * @link https://developer.wordpress.org/themes/basics/theme-functions/
 *
 * @package kadence
 */

define( 'KADENCE_VERSION', '1.2.18' );
define( 'KADENCE_MINIMUM_WP_VERSION', '6.0' );
define( 'KADENCE_MINIMUM_PHP_VERSION', '7.4' );

// Bail if requirements are not met.
if ( version_compare( $GLOBALS['wp_version'], KADENCE_MINIMUM_WP_VERSION, '<' ) || version_compare( phpversion(), KADENCE_MINIMUM_PHP_VERSION, '<' ) ) {
    require get_template_directory() . '/inc/back-compat.php';
    return;
}
// Include WordPress shims.
require get_template_directory() . '/inc/wordpress-shims.php';

// Load the `kadence()` entry point function.
require get_template_directory() . '/inc/class-theme.php';

// Load the `kadence()` entry point function.
require get_template_directory() . '/inc/functions.php';

// Include SIMPLIFIED subscription functionality
require get_template_directory() . '/simplified-subscription-functions.php';

// Initialize the theme.
call_user_func( 'Kadence\kadence' );

/**
 * MemrE App Functions
 */

/**
 * Authentication Setup
 */
add_filter('rest_authentication_errors', function($result) {
    if (!empty($result)) {
        return $result;
    }
    
    if (!is_user_logged_in()) {
        if (isset($_SERVER['PHP_AUTH_USER']) && isset($_SERVER['PHP_AUTH_PW'])) {
            $username = $_SERVER['PHP_AUTH_USER'];
            $password = $_SERVER['PHP_AUTH_PW'];
            
            $user = wp_authenticate($username, $password);
            
            if (is_wp_error($user)) {
                return new WP_Error(
                    'rest_not_logged_in',
                    __('You are not currently logged in.'),
                    array('status' => 401)
                );
            }
        }
    }
    
    return $result;
});

// Add application passwords capability to subscribers
add_action('init', 'add_app_passwords_to_subscribers');
function add_app_passwords_to_subscribers() {
    $role = get_role('subscriber');
    if ($role) {
       $role->add_cap('create_application_passwords');
    }
}

/**
 * Custom REST API Endpoints
 */
add_action('rest_api_init', function () {
    // Auth endpoint
    register_rest_route('memre-app/v1', '/auth', array(
        'methods' => 'POST',
        'callback' => 'custom_auth_handler',
        'permission_callback' => '__return_true'
    ));
});

/**
 * Authentication handler for the API
 * 
 * @param WP_REST_Request $request The request object
 * @return array|WP_Error Authentication result
 */
function custom_auth_handler($request) {
    $params = $request->get_params();
    $username = isset($params['username']) ? $params['username'] : '';
    $password = isset($params['password']) ? $params['password'] : '';
    
    $user = wp_authenticate($username, $password);
    
    if (is_wp_error($user)) {
        return new WP_Error(
            'auth_failed',
            'Invalid credentials',
            array('status' => 401)
        );
    }
    
    return array(
        'user_id' => $user->ID,
        'user_display_name' => $user->display_name,
        'username' => $user->user_login
    );
}

/**
 * Simplified Table Creation on User Registration (NO SMS TABLES)
 */
add_action('um_registration_complete', 'create_user_tables_simplified', 10, 1);
function create_user_tables_simplified($user_id) {
    try {
        $custom_db = new mysqli(
            CUSTOM_DB_HOST,
            CUSTOM_DB_USER,
            CUSTOM_DB_PASSWORD,
            CUSTOM_DB_NAME
        );

        if ($custom_db->connect_error) {
            throw new Exception("Connection failed: " . $custom_db->connect_error);
        }

        $table_prefix = 'user_' . $user_id . '_';
        $memo_table = $table_prefix . 'memo';
        $reminder_table = $table_prefix . 'reminder';
        $memo_reminder_table = $table_prefix . 'memo_reminder';
        $attachment_table = $table_prefix . 'attachment';
        // REMOVED: SMS usage table - no longer needed

        $charset_collate = "DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci";

        // Create Memo Table
        $sql_memo = "
            CREATE TABLE IF NOT EXISTS $memo_table (
                memo_id INT AUTO_INCREMENT PRIMARY KEY,
                memo_desc VARCHAR(75),
                memo LONGTEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) $charset_collate;
        ";
        
        if (!$custom_db->query($sql_memo)) {
            throw new Exception("Error creating memo table: " . $custom_db->error);
        }

        // Create Attachment Table
        $sql_attachment = "
            CREATE TABLE IF NOT EXISTS $attachment_table (
                attachment_id INT AUTO_INCREMENT PRIMARY KEY,
                memo_id INT,
                file_data LONGBLOB,
                file_type VARCHAR(50),
                file_name VARCHAR(255),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (memo_id) REFERENCES {$memo_table}(memo_id) ON DELETE CASCADE
            ) $charset_collate;
        ";

        if (!$custom_db->query($sql_attachment)) {
            throw new Exception("Error creating attachment table: " . $custom_db->error);
        }

        // Create Reminder Table
        $sql_reminder = "
            CREATE TABLE IF NOT EXISTS $reminder_table (
                reminder_id INT AUTO_INCREMENT PRIMARY KEY,
                reminder_time DATETIME,
                repeat_type VARCHAR(20),
                repeat_until DATE,
                timezone_offset INT,
                use_screen_notification BOOLEAN DEFAULT TRUE,
                email_address VARCHAR(255),
                phone_number VARCHAR(20),
                email_addresses TEXT,
                phone_numbers TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) $charset_collate;
        ";
        
        if (!$custom_db->query($sql_reminder)) {
            throw new Exception("Error creating reminder table: " . $custom_db->error);
        }

        // Create Junction Table
        $sql_junction = "
            CREATE TABLE IF NOT EXISTS $memo_reminder_table (
                memo_id INT,
                reminder_id INT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (memo_id, reminder_id),
                FOREIGN KEY (memo_id) REFERENCES $memo_table(memo_id) ON DELETE CASCADE,
                FOREIGN KEY (reminder_id) REFERENCES $reminder_table(reminder_id) ON DELETE CASCADE
            ) $charset_collate;
        ";

        if (!$custom_db->query($sql_junction)) {
            throw new Exception("Error creating memo-reminder junction table: " . $custom_db->error);
        }

        // Store table names in user meta (removed SMS usage table)
        $tables = [
            'memo_table' => $memo_table,
            'reminder_table' => $reminder_table,
            'memo_reminder_table' => $memo_reminder_table,
            'attachment_table' => $attachment_table
        ];

        foreach ($tables as $key => $table) {
            update_user_meta($user_id, "user_$key", $table);
        }

    } catch (Exception $e) {
        error_log("Error creating user tables: " . $e->getMessage());
        wp_mail(
            get_option('admin_email'),
            'Database Error on User Registration',
            'Error creating tables for user ID ' . $user_id . ': ' . $e->getMessage()
        );
    } finally {
        if (isset($custom_db) && $custom_db instanceof mysqli) {
            $custom_db->close();
        }
    }
}

/**
 * Memo AJAX Handlers (UNCHANGED - these work fine)
 */

// Save Memo
add_action('wp_ajax_save_memo', 'handle_save_memo');
function handle_save_memo() {
   try {
       if (!isset($_POST['nonce']) || !wp_verify_nonce($_POST['nonce'], 'save_memo_action')) {
           wp_send_json_error(['message' => 'Security check failed']);
           return;
       }

       $current_user_id = get_current_user_id();
       if (!$current_user_id) {
           wp_send_json_error(['message' => 'User not logged in']);
           return;
       }

       $memo_id = isset($_POST['memo_id']) ? intval($_POST['memo_id']) : 0;
       $memo_desc = sanitize_text_field($_POST['memo_desc']);
       $memo_content = sanitize_textarea_field($_POST['memo']);
       $reminders = isset($_POST['reminders']) ? array_filter($_POST['reminders']) : [];
       $repeat_types = isset($_POST['repeat_type']) ? $_POST['repeat_type'] : array();
       $repeat_until = isset($_POST['repeat_until']) ? $_POST['repeat_until'] : array();
       $use_screen_notifications = isset($_POST['use_screen_notification']) ? $_POST['use_screen_notification'] : array();
       $email_addresses = isset($_POST['email_addresses']) ? $_POST['email_addresses'] : array();
       $phone_numbers = isset($_POST['phone_numbers']) ? $_POST['phone_numbers'] : array();
       $single_emails = isset($_POST['email_address']) ? $_POST['email_address'] : array();
       $single_phones = isset($_POST['phone_number']) ? $_POST['phone_number'] : array();

       $custom_db = new mysqli(CUSTOM_DB_HOST, CUSTOM_DB_USER, CUSTOM_DB_PASSWORD, CUSTOM_DB_NAME);
       if ($custom_db->connect_error) {
           throw new Exception("Database connection failed: " . $custom_db->connect_error);
       }

       $custom_db->begin_transaction();

       try {
           $memo_table = "user_{$current_user_id}_memo";
           
           if ($memo_id > 0) {
               $stmt = $custom_db->prepare("UPDATE {$memo_table} SET memo_desc = ?, memo = ? WHERE memo_id = ?");
               $stmt->bind_param('ssi', $memo_desc, $memo_content, $memo_id);
           } else {
               $stmt = $custom_db->prepare("INSERT INTO {$memo_table} (memo_desc, memo) VALUES (?, ?)");
               $stmt->bind_param('ss', $memo_desc, $memo_content);
           }
           
           if (!$stmt->execute()) {
               throw new Exception("Error saving memo: " . $stmt->error);
           }

           $memoId = $memo_id > 0 ? $memo_id : $custom_db->insert_id;

           // Handle file attachment
           if (isset($_FILES['attachment']) && $_FILES['attachment']['error'] === UPLOAD_ERR_OK) {
               $file = $_FILES['attachment'];
               $allowed_types = [
                   'image/jpeg' => 'image',
                   'image/png' => 'image',
                   'image/gif' => 'image',
                   'application/pdf' => 'document',
                   'application/msword' => 'document',
                   'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => 'document',
                   'video/mp4' => 'video',
                   'video/quicktime' => 'video'
               ];

               if (!isset($allowed_types[$file['type']])) {
                   throw new Exception('Invalid file type');
               }

               $file_type = $allowed_types[$file['type']];
               $file_data = file_get_contents($file['tmp_name']);
               
               $attachment_table = "user_{$current_user_id}_attachment";
               $custom_db->query("DELETE FROM {$attachment_table} WHERE memo_id = {$memoId}");
               
               $stmt = $custom_db->prepare(
                   "INSERT INTO {$attachment_table} (memo_id, file_data, file_type, file_name) VALUES (?, ?, ?, ?)"
               );
               $stmt->bind_param('isss', $memoId, $file_data, $file_type, $file['name']);
               
               if (!$stmt->execute()) {
                   throw new Exception("Error saving attachment: " . $stmt->error);
               }
           }

           // Clear existing relationships
           $custom_db->query("DELETE FROM user_{$current_user_id}_memo_reminder WHERE memo_id = {$memoId}");
           $reminder_ids = $custom_db->query("SELECT reminder_id FROM user_{$current_user_id}_memo_reminder WHERE memo_id = {$memoId}");
           if ($reminder_ids && $reminder_ids->num_rows > 0) {
               while ($row = $reminder_ids->fetch_assoc()) {
                   $custom_db->query("DELETE FROM user_{$current_user_id}_reminder WHERE reminder_id = {$row['reminder_id']}");
               }
           }

           // Save reminders
           if (!empty($reminders)) {
               $reminder_table = "user_{$current_user_id}_reminder";
               $memo_reminder_table = "user_{$current_user_id}_memo_reminder";
               
               for ($i = 0; $i < count($reminders); $i++) {
                   $reminder_time = $reminders[$i];
                   $repeat_type = isset($repeat_types[$i]) ? $repeat_types[$i] : null;
                   $until_date = isset($repeat_until[$i]) ? $repeat_until[$i] : null;
                   $use_screen = isset($use_screen_notifications[$i]) ? (int)$use_screen_notifications[$i] : 1;
                   
                   // Get single email/phone values for backward compatibility
                   $email = isset($single_emails[$i]) ? $single_emails[$i] : null;
                   $phone = isset($single_phones[$i]) ? $single_phones[$i] : null;
                   
                   // Process multiple recipients
                   $emails_list = [];
                   if (!empty($email)) {
                       $emails_list[] = $email;
                   }
                   if (isset($email_addresses[$i]) && is_array($email_addresses[$i])) {
                       foreach ($email_addresses[$i] as $addr) {
                           if (!empty($addr) && !in_array($addr, $emails_list)) {
                               $emails_list[] = $addr;
                           }
                       }
                   }

                   $phones_list = [];
                   if (!empty($phone)) {
                       $phones_list[] = $phone;
                   }
                   if (isset($phone_numbers[$i]) && is_array($phone_numbers[$i])) {
                       foreach ($phone_numbers[$i] as $num) {
                           if (!empty($num) && !in_array($num, $phones_list)) {
                               $phones_list[] = $num;
                           }
                       }
                   }
                   
                   // Convert to pipe-separated strings
                   $emails_string = implode('|', $emails_list);
                   $phones_string = implode('|', $phones_list);
                   
                   // Use the first item as the primary email/phone for backward compatibility
                   $primary_email = !empty($emails_list) ? $emails_list[0] : null;
                   $primary_phone = !empty($phones_list) ? $phones_list[0] : null;
                   
                   // Add columns for email_addresses and phone_numbers if they don't exist
                   $check_columns = $custom_db->query("SHOW COLUMNS FROM {$reminder_table} LIKE 'email_addresses'");
                   if ($check_columns->num_rows === 0) {
                       $custom_db->query("ALTER TABLE {$reminder_table} ADD COLUMN email_addresses TEXT");
                       $custom_db->query("ALTER TABLE {$reminder_table} ADD COLUMN phone_numbers TEXT");
                   }
                   
                   $stmt = $custom_db->prepare(
                       "INSERT INTO {$reminder_table} (reminder_time, repeat_type, repeat_until, use_screen_notification, email_address, phone_number, email_addresses, phone_numbers) 
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
                   );
                   $stmt->bind_param('ssiissss', $reminder_time, $repeat_type, $until_date, $use_screen, $primary_email, $primary_phone, $emails_string, $phones_string);
                   
                   if (!$stmt->execute()) {
                       throw new Exception("Error saving reminder: " . $stmt->error);
                   }
                   
                   $reminder_id = $custom_db->insert_id;
                   
                   $stmt = $custom_db->prepare(
                       "INSERT INTO {$memo_reminder_table} (memo_id, reminder_id) VALUES (?, ?)"
                   );
                   $stmt->bind_param('ii', $memoId, $reminder_id);
                   
                   if (!$stmt->execute()) {
                       throw new Exception("Error saving reminder relationship");
                   }
               }
           }

           $custom_db->commit();
           wp_send_json_success(['message' => 'Memo saved successfully', 'memo_id' => $memoId]);

       } catch (Exception $e) {
           $custom_db->rollback();
           throw $e;
       }
   } catch (Exception $e) {
       error_log("Error in handle_save_memo: " . $e->getMessage());
       wp_send_json_error(['message' => $e->getMessage()]);
   } finally {
       if (isset($custom_db) && $custom_db instanceof mysqli) {
           $custom_db->close();
       }
   }
}

/**
 * Delete Memo Handling (UNCHANGED)
 */
add_action('wp_ajax_delete_memo', 'handle_delete_memo');
function handle_delete_memo() {
    try {
        $current_user_id = get_current_user_id();
        if (!$current_user_id) {
            throw new Exception('User not logged in');
        }

        $memo_id = isset($_POST['memo_id']) ? intval($_POST['memo_id']) : 0;
        if (!$memo_id) {
            throw new Exception("Invalid memo ID");
        }

        $custom_db = new mysqli(
            CUSTOM_DB_HOST,
            CUSTOM_DB_USER,
            CUSTOM_DB_PASSWORD,
            CUSTOM_DB_NAME
        );

        if ($custom_db->connect_error) {
            throw new Exception("Connection failed: " . $custom_db->connect_error);
        }

        $custom_db->begin_transaction();

        try {
            // Delete from all related tables
            $tables = [
                "user_{$current_user_id}_memo_reminder",
                "user_{$current_user_id}_attachment"
            ];

            foreach ($tables as $table) {
                $stmt = $custom_db->prepare("DELETE FROM {$table} WHERE memo_id = ?");
                $stmt->bind_param('i', $memo_id);
                if (!$stmt->execute()) {
                    throw new Exception("Error deleting from {$table}");
                }
            }

            // Delete the memo itself
            $memo_table = "user_{$current_user_id}_memo";
            $stmt = $custom_db->prepare("DELETE FROM {$memo_table} WHERE memo_id = ?");
            $stmt->bind_param('i', $memo_id);
            
            if (!$stmt->execute()) {
                throw new Exception("Error deleting memo");
            }

            $custom_db->commit();
            wp_send_json_success(['message' => 'Memo deleted successfully']);

        } catch (Exception $e) {
            $custom_db->rollback();
            throw $e;
        }

    } catch (Exception $e) {
        wp_send_json_error(['message' => $e->getMessage()]);
    } finally {
        if (isset($custom_db) && $custom_db instanceof mysqli) {
            $custom_db->close();
        }
    }
}

/**
 * Attachment Download Handler (UNCHANGED)
 */
add_action('wp_ajax_download_attachment', 'handle_attachment_download');
function handle_attachment_download() {
    try {
        if (!isset($_GET['memo_id']) || !isset($_GET['nonce'])) {
            throw new Exception('Invalid request');
        }

        if (!wp_verify_nonce($_GET['nonce'], 'download_attachment')) {
            throw new Exception('Security check failed');
        }

        $current_user_id = get_current_user_id();
        if (!$current_user_id) {
            throw new Exception('User not logged in');
        }

        $memo_id = intval($_GET['memo_id']);

        $custom_db = new mysqli(
            CUSTOM_DB_HOST,
            CUSTOM_DB_USER,
            CUSTOM_DB_PASSWORD,
            CUSTOM_DB_NAME
        );

        if ($custom_db->connect_error) {
            throw new Exception("Database connection failed");
        }

        $query = "SELECT file_type, file_name, file_data FROM user_{$current_user_id}_attachment WHERE memo_id = ?";
        $stmt = $custom_db->prepare($query);
        $stmt->bind_param('i', $memo_id);
        $stmt->execute();
        $result = $stmt->get_result();
        $attachment = $result->fetch_assoc();

        if (!$attachment) {
            throw new Exception('File not found');
        }

        // Set appropriate headers based on file type
        $mime_types = [
            'image' => 'image/jpeg',
            'document' => 'application/pdf',
            'video' => 'video/mp4'
        ];

        $mime_type = $mime_types[$attachment['file_type']] ?? 'application/octet-stream';

        header('Content-Type: ' . $mime_type);
        header('Content-Disposition: attachment; filename="' . $attachment['file_name'] . '"');
        header('Content-Length: ' . strlen($attachment['file_data']));
        header('Cache-Control: private');

        echo $attachment['file_data'];
        exit;

    } catch (Exception $e) {
        wp_die('Error: ' . $e->getMessage());
    }
}

/**
 * SIMPLIFIED User deletion handler (NO SMS TABLES)
 */
add_action('um_delete_user', 'handle_user_deletion_simplified', 10, 1);
function handle_user_deletion_simplified($user_id) {
    try {
        $custom_db = new mysqli(
            CUSTOM_DB_HOST,
            CUSTOM_DB_USER,
            CUSTOM_DB_PASSWORD,
            CUSTOM_DB_NAME
        );

        if ($custom_db->connect_error) {
            throw new Exception("Connection failed: " . $custom_db->connect_error);
        }

        // Get table names (removed SMS usage table)
        $tables = [
            "user_{$user_id}_memo",
            "user_{$user_id}_reminder",
            "user_{$user_id}_memo_reminder",
            "user_{$user_id}_attachment"
            // REMOVED: "user_{$user_id}_sms_usage"
        ];

        // Create backup folder if it doesn't exist
        $backup_dir = WP_CONTENT_DIR . '/user-backups';
        if (!file_exists($backup_dir)) {
            mkdir($backup_dir, 0755, true);
        }

        // Create backup file
        $backup_file = fopen($backup_dir . "/user_{$user_id}_backup_" . date('Y-m-d_H-i-s') . '.sql', 'w');

        // Backup each table
        foreach ($tables as $table) {
            // Check if table exists
            $table_exists = $custom_db->query("SHOW TABLES LIKE '{$table}'");
            if ($table_exists && $table_exists->num_rows > 0) {
                // Get table structure
                $result = $custom_db->query("SHOW CREATE TABLE {$table}");
                if ($result) {
                    $row = $result->fetch_assoc();
                    if (isset($row['Create Table'])) {
                        fwrite($backup_file, "\n\n-- Table structure for {$table}\n");
                        fwrite($backup_file, $row['Create Table'] . ";\n\n");

                        // Get table data
                        fwrite($backup_file, "-- Data for {$table}\n");
                        $data = $custom_db->query("SELECT * FROM {$table}");
                        if ($data) {
                            while ($row = $data->fetch_assoc()) {
                                $columns = array_keys($row);
                                $values = array_map(function($value) use ($custom_db) {
                                    if ($value === null) return 'NULL';
                                    return "'" . $custom_db->real_escape_string($value) . "'";
                                }, $row);

                                $insert = "INSERT INTO {$table} (" . 
                                        implode(', ', $columns) . 
                                        ") VALUES (" . 
                                        implode(', ', $values) . 
                                        ");\n";
                                fwrite($backup_file, $insert);
                            }
                        }
                    }
                }
                
                // Drop the table
                $custom_db->query("DROP TABLE IF EXISTS {$table}");
            }
        }

        fclose($backup_file);

        // Log deletion
        error_log("User {$user_id} data backed up and tables deleted successfully");

    } catch (Exception $e) {
        error_log("Error in user deletion process: " . $e->getMessage());
        wp_mail(
            get_option('admin_email'),
            'Error in user deletion process',
            'Error processing deletion for user ID ' . $user_id . ': ' . $e->getMessage()
        );
    } finally {
        if (isset($custom_db) && $custom_db instanceof mysqli) {
            $custom_db->close();
        }
    }
}

/**
 * Debug Webhook Requests (UNCHANGED)
 */
function debug_webhook_requests() {
    if (strpos($_SERVER['REQUEST_URI'], '/um-api/stripe/webhook') !== false) {
        $log_dir = WP_CONTENT_DIR . '/webhook-logs';
        if (!file_exists($log_dir)) {
            mkdir($log_dir, 0755, true);
        }
        
        $raw_post = file_get_contents('php://input');
        $headers = getallheaders();
        
        file_put_contents(
            $log_dir . '/webhook-' . date('Y-m-d-H-i-s') . '.log',
            "URI: " . $_SERVER['REQUEST_URI'] . "\n" .
            "Headers: " . print_r($headers, true) . "\n" .
            "Raw payload: " . $raw_post . "\n"
        );
    }
}
add_action('init', 'debug_webhook_requests');

/**
 * Debug Stripe Webhook (UNCHANGED)
 */
function debug_stripe_webhook() {
    if (isset($_GET['umm-stripe-webhook']) && $_GET['umm-stripe-webhook'] === 'true') {
        $log_dir = WP_CONTENT_DIR . '/webhook-logs';
        if (!file_exists($log_dir)) {
            mkdir($log_dir, 0755, true);
        }
        
        $raw_post = file_get_contents('php://input');
        $headers = getallheaders();
        
        file_put_contents(
            $log_dir . '/webhook-' . date('Y-m-d-H-i-s') . '.log',
            "Headers: " . print_r($headers, true) . "\n" .
            "Raw payload: " . $raw_post . "\n"
        );
    }
}
add_action('init', 'debug_stripe_webhook');

/**
 * SIMPLIFIED subscription cancellation redirect
 */
add_action('wp_footer', 'add_simple_subscription_canceled_redirect');
function add_simple_subscription_canceled_redirect() {
    if (!is_user_logged_in() || 
        !function_exists('um_is_core_page') || 
        !um_is_core_page('account') || 
        empty($_GET['um_tab']) || 
        $_GET['um_tab'] !== 'billing') {
        return;
    }
    
    ?>
    <script type="text/javascript">
    document.addEventListener('DOMContentLoaded', function() {
        var cancelButtons = document.querySelectorAll('a[href*="cancel_subscription"], a[href*="cancel-subscription"], button[data-action="cancel_subscription"]');
        
        if (cancelButtons.length > 0) {
            cancelButtons.forEach(function(button) {
                button.addEventListener('click', function(e) {
                    localStorage.setItem('subscription_cancellation_initiated', 'true');
                });
            });
        }
        
        if (localStorage.getItem('subscription_cancellation_initiated') === 'true') {
            var subscriptionElements = document.querySelectorAll('.um-stripe-subscription-details, .um-stripe-subscription-id');
            
            if (subscriptionElements.length === 0) {
                localStorage.removeItem('subscription_cancellation_initiated');
                window.location.href = '<?php echo esc_url(home_url('/subscription-upgrade/')); ?>';
            }
        }
    });
    </script>
    <?php
}

/**
 * Redirect URL after cancellation
 */
add_filter('um_stripe_subscription_cancel_redirect', 'custom_cancel_redirect', 10, 2);
function custom_cancel_redirect($redirect_url, $user_id) {
    return home_url('/subscription-upgrade/'); // Update this to your subscription page
}

/**
 * Monitor subscription cancellation status
 */
add_action('wp_footer', 'monitor_subscription_cancellation_status');
function monitor_subscription_cancellation_status() {
    if (!is_user_logged_in() || 
        !function_exists('um_is_core_page') || 
        !um_is_core_page('account') || 
        empty($_GET['um_tab']) || 
        $_GET['um_tab'] !== 'billing') {
        return;
    }
    
    $user_id = get_current_user_id();
    
    global $wpdb;
    $subscription_table = $wpdb->prefix . 'um_stripe_subscriptions';
    $canceled_subscription = $wpdb->get_row($wpdb->prepare(
        "SELECT * FROM $subscription_table 
         WHERE user_id = %d 
         AND LOWER(status) = LOWER('canceled') 
         ORDER BY date_created DESC LIMIT 1",
        $user_id
    ));
    
    if ($canceled_subscription) {
        ?>
        <script type="text/javascript">
        document.addEventListener('DOMContentLoaded', function() {
            var message = document.createElement('div');
            message.style.padding = '15px';
            message.style.backgroundColor = '#f8f9fa';
            message.style.borderRadius = '5px';
            message.style.marginBottom = '20px';
            message.innerHTML = '<p>Your subscription has been canceled. Redirecting to subscription options...</p>';
            
            var billingContent = document.querySelector('.um-account-content');
            if (billingContent) {
                billingContent.insertBefore(message, billingContent.firstChild);
            }
            
            setTimeout(function() {
                window.location.href = '<?php echo esc_js(home_url("/subscription-upgrade/")); ?>';
            }, 2000);
        });
        </script>
        <?php
    }
}

/**
 * Clean up old SMS usage tables
 */
function cleanup_old_sms_tables() {
    if (!current_user_can('administrator')) {
        wp_die('Access denied');
    }
    
    try {
        $custom_db = new mysqli(
            CUSTOM_DB_HOST,
            CUSTOM_DB_USER,
            CUSTOM_DB_PASSWORD,
            CUSTOM_DB_NAME
        );

        if ($custom_db->connect_error) {
            throw new Exception("Connection failed: " . $custom_db->connect_error);
        }

        $result = $custom_db->query("SHOW TABLES LIKE 'user_%_sms_usage'");
        $tables_dropped = 0;
        
        if ($result) {
            while ($row = $result->fetch_row()) {
                $table_name = $row[0];
                $custom_db->query("DROP TABLE IF EXISTS {$table_name}");
                $tables_dropped++;
            }
        }
        
        $custom_db->close();
        
        echo "<div class='notice notice-success'><p>Cleanup complete. Dropped {$tables_dropped} SMS usage tables.</p></div>";
        
    } catch (Exception $e) {
        echo "<div class='notice notice-error'><p>Error during cleanup: " . $e->getMessage() . "</p></div>";
    }
}

// Add cleanup function to admin menu
add_action('admin_menu', function() {
    add_management_page(
        'SMS Table Cleanup',
        'SMS Table Cleanup',
        'manage_options',
        'sms-cleanup',
        function() {
            echo '<div class="wrap">';
            echo '<h1>SMS Table Cleanup</h1>';
            echo '<p>This will remove all old SMS usage tables since SMS is now handled locally.</p>';
            
            if (isset($_GET['run_cleanup'])) {
                cleanup_old_sms_tables();
            } else {
                echo '<a href="' . add_query_arg('run_cleanup', '1') . '" class="button button-primary" onclick="return confirm(\'Are you sure you want to remove all SMS usage tables?\')">Run Cleanup</a>';
            }
            
            echo '</div>';
        }
    );
});

/**
 * User authentication check for API endpoints
 */
function check_user_auth($request) {
    $user_id = $request['user_id'];
    $current_user_id = get_current_user_id();
    
    return ($current_user_id == $user_id) || current_user_can('administrator');
}

/**
 * Add custom meta boxes to admin pages
 */
function memre_add_meta_boxes() {
    add_meta_box(
        'memre_user_info',
        'MemrE User Information',
        'memre_user_info_callback_simplified', // FIXED: Now matches function name
        'user-edit',
        'normal',
        'high'
    );
}
add_action('add_meta_boxes', 'memre_add_meta_boxes');

/**
 * SIMPLIFIED callback for user info meta box (NO SMS DATA)
 */
function memre_user_info_callback_simplified($post) {
    $screen = get_current_screen();
    if ($screen->id !== 'user-edit') {
        return;
    }
    
    $user_id = isset($_GET['user_id']) ? intval($_GET['user_id']) : 0;
    if (!$user_id) {
        return;
    }
    
    // Get simplified subscription info
    $status = get_user_subscription_status($user_id);
    
    echo '<div class="memre-user-info">';
    echo '<p><strong>Subscription Tier:</strong> ' . esc_html($status['subscription_tier']) . '</p>';
    echo '<p><strong>Trial Active:</strong> ' . ($status['trial_active'] ? 'Yes (' . $status['trial_days_remaining'] . ' days left)' : 'No') . '</p>';
    echo '<p><strong>Valid Subscription:</strong> ' . ($status['has_valid_subscription'] ? 'Yes' : 'No') . '</p>';
    echo '<p><strong>App Access:</strong> ' . (user_has_app_access($user_id) ? 'Yes' : 'No') . '</p>';
    
    // REMOVED: All SMS usage display code
    
    echo '</div>';
}

/**
 * Set default role for new users
 */
function set_default_user_role($user_id) {
    $user = new WP_User($user_id);
    $user->set_role('subscriber');
}
add_action('user_register', 'set_default_user_role');

/**
 * Modify login redirect URL
 */
function custom_login_redirect($redirect_to, $request, $user) {
    if (isset($user->roles) && is_array($user->roles)) {
        if (in_array('administrator', $user->roles)) {
            return admin_url();
        } else {
            return home_url('/dashboard/');
        }
    }
    return $redirect_to;
}
add_filter('login_redirect', 'custom_login_redirect', 10, 3);

/**
 * Register custom endpoints and rewrite rules
 */
function memre_custom_rewrite_rules() {
    add_rewrite_rule(
        '^dashboard/([^/]+)/?
        ,
        'index.php?pagename=dashboard&section=$matches[1]',
        'top'
    );
}
add_action('init', 'memre_custom_rewrite_rules');

/**
 * Add custom query vars
 */
function memre_custom_query_vars($vars) {
    $vars[] = 'section';
    return $vars;
}
add_filter('query_vars', 'memre_custom_query_vars');

/**
 * Enqueue scripts and styles
 */
function memre_enqueue_scripts() {
    wp_enqueue_script('jquery');
}
add_action('wp_enqueue_scripts', 'memre_enqueue_scripts');

/**
 * REST API ENDPOINTS - SIMPLIFIED
 */
add_action('rest_api_init', function() {
    // Subscription status endpoint
    register_rest_route('memre-app/v1', '/subscription-status/(?P<user_id>\d+)', array(
        'methods' => 'GET',
        'callback' => 'get_subscription_status_api',
        'permission_callback' => 'check_user_auth',
        'args' => array(
            'user_id' => array(
                'validate_callback' => function($param) {
                    return is_numeric($param);
                }
            )
        )
    ));
    
    // Trial status endpoint
    register_rest_route('memre-app/v1', '/trial-status/(?P<user_id>\d+)', array(
        'methods' => 'GET',
        'callback' => 'get_trial_status_api',
        'permission_callback' => 'check_user_auth'
    ));
    
    // Debug endpoint for admins
    register_rest_route('memre-app/v1', '/debug-subscription/(?P<user_id>\d+)', array(
        'methods' => 'GET',
        'callback' => 'debug_user_subscription_simplified',
        'permission_callback' => function() { return current_user_can('manage_options'); }
    ));
    
    // Due reminders endpoint (unchanged)
    register_rest_route('memre-app/v1', '/due-reminders/(?P<user_id>\d+)', array(
        'methods' => 'GET',
        'callback' => 'get_due_reminders',
        'permission_callback' => 'check_user_auth',
    ));
});

/**
 * API ENDPOINT HANDLERS
 */

function get_subscription_status_api($request) {
    $user_id = $request['user_id'];
    return get_user_subscription_status($user_id);
}

function get_trial_status_api($request) {
    $user_id = $request['user_id'];
    $status = get_user_subscription_status($user_id);
    
    return array(
        'status' => $status['trial_active'] ? 'active' : 'expired',
        'days_remaining' => $status['trial_days_remaining'],
        'subscription_tier' => $status['subscription_tier'],
        'has_valid_subscription' => $status['has_valid_subscription'],
        'app_access' => user_has_app_access($user_id)
    );
}

function debug_user_subscription_simplified($request) {
    $user_id = $request['user_id'];
    
    global $wpdb;
    $subscription_table = $wpdb->prefix . 'um_stripe_subscriptions';
    
    $subscriptions = $wpdb->get_results($wpdb->prepare(
        "SELECT * FROM $subscription_table WHERE user_id = %d",
        $user_id
    ));
    
    $stripe_customer_id = get_user_meta($user_id, 'um_stripe_customer_id', true);
    $subscription_plan = get_user_meta($user_id, 'subscription_plan_name', true);
    $is_free_trial = get_user_meta($user_id, 'is_free_trial', true);
    $registration_date = get_user_meta($user_id, 'registration_date', true);
    
    $status = get_user_subscription_status($user_id);
    
    return array(
        'user_id' => $user_id,
        'subscriptions' => $subscriptions,
        'stripe_customer_id' => $stripe_customer_id,
        'subscription_plan' => $subscription_plan,
        'is_free_trial' => $is_free_trial,
        'registration_date' => $registration_date,
        'subscription_status' => $status,
        'app_access' => user_has_app_access($user_id)
        // REMOVED: SMS usage data - no longer relevant
    );
}

function get_due_reminders($request) {
    $user_id = $request['user_id'];
    
    try {
        $custom_db = new mysqli(
            CUSTOM_DB_HOST,
            CUSTOM_DB_USER,
            CUSTOM_DB_PASSWORD,
            CUSTOM_DB_NAME
        );
        
        if ($custom_db->connect_error) {
            throw new Exception("Database connection failed");
        }
        
        $now = date('Y-m-d H:i:s');
        
        $query = "
            SELECT 
                m.memo_id, 
                m.memo_desc, 
                m.memo, 
                r.reminder_id,
                r.reminder_time,
                r.repeat_type,
                r.repeat_until,
                r.timezone_offset,
                r.use_screen_notification,
                r.email_address,
                r.phone_number,
                r.email_addresses,
                r.phone_numbers
            FROM user_{$user_id}_reminder r
            JOIN user_{$user_id}_memo_reminder mr ON r.reminder_id = mr.reminder_id
            JOIN user_{$user_id}_memo m ON mr.memo_id = m.memo_id
            WHERE r.reminder_time <= ?
            AND NOT EXISTS (
                SELECT 1 FROM user_{$user_id}_reminder_sent WHERE reminder_id = r.reminder_id
            )
        ";
        
        $stmt = $custom_db->prepare($query);
        $stmt->bind_param('s', $now);
        $stmt->execute();
        $result = $stmt->get_result();
        
        $reminders = array();
        while ($row = $result->fetch_assoc()) {
            $reminder_id = $row['reminder_id'];
            
            $reminders[] = array(
                'id' => $reminder_id,
                'title' => $row['memo_desc'],
                'content' => $row['memo'],
                'reminder_time' => $row['reminder_time'],
                'email_address' => $row['email_address'],
                'phone_number' => $row['phone_number'],
                'email_addresses' => $row['email_addresses'],
                'phone_numbers' => $row['phone_numbers'],
                'use_screen_notification' => (bool)$row['use_screen_notification']
            );
            
            // Process email notifications
            if (!empty($row['email_addresses'])) {
                $emails = explode('|', $row['email_addresses']);
                foreach ($emails as $email) {
                    if (!empty($email)) {
                        wp_mail(
                            $email,
                            'MemrE Reminder: ' . $row['memo_desc'],
                            $row['memo']
                        );
                    }
                }
            }
            
            // SMS notifications are now handled locally on the device
            // No need to send SMS from server
        }
        
        $custom_db->close();
        
        return array(
            'reminders' => $reminders
        );
        
    } catch (Exception $e) {
        return new WP_Error('database_error', $e->getMessage(), array('status' => 500));
    }
}