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

// Initialize the theme.
call_user_func( 'Kadence\kadence' );

/**
 * ===================================
 * MEMRE APP CORE FUNCTIONS
 * ===================================
 */

/**
 * Database connection function for the old system (keeping for memo functionality)
 */
function get_custom_db_connection() {
    // Define constants if they don't exist
    if (!defined('CUSTOM_DB_HOST')) {
        define('CUSTOM_DB_HOST', DB_HOST);
    }
    if (!defined('CUSTOM_DB_USER')) {
        define('CUSTOM_DB_USER', DB_USER);
    }
    if (!defined('CUSTOM_DB_PASSWORD')) {
        define('CUSTOM_DB_PASSWORD', DB_PASSWORD);
    }
    if (!defined('CUSTOM_DB_NAME')) {
        define('CUSTOM_DB_NAME', DB_NAME);
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
        
        return $custom_db;
    } catch (Exception $e) {
        error_log("Database connection error: " . $e->getMessage());
        return false;
    }
}

/**
 * ===================================
 * SUBSCRIPTION MANAGEMENT SYSTEM
 * ===================================
 */

/**
 * Get user subscription status
 */
function get_user_subscription_status($user_id) {
    global $wpdb;
    
    $subscription_table = $wpdb->prefix . 'um_stripe_subscriptions';
    
    // Check for active paid subscription
    $subscription = $wpdb->get_row($wpdb->prepare(
        "SELECT * FROM $subscription_table 
         WHERE user_id = %d 
         AND (LOWER(status) = LOWER('active') OR LOWER(status) = LOWER('trialing'))
         LIMIT 1",
        $user_id
    ));
    
    if ($subscription) {
        return array(
            'subscription_tier' => 'MemrE App',
            'trial_active' => ($subscription->status === 'trialing'),
            'trial_days_remaining' => 0,
            'has_valid_subscription' => true,
            'premium_active' => true,
            'trial_expired' => false
        );
    }
    
    // Check if user is in free trial
    $is_trial = get_user_meta($user_id, 'is_free_trial', true);
    $registration_date = get_user_meta($user_id, 'registration_date', true);
    
    if ($is_trial && $registration_date) {
        $trial_end = strtotime($registration_date . ' +14 days');
        $days_remaining = max(0, ceil(($trial_end - time()) / (24 * 60 * 60)));
        
        return array(
            'subscription_tier' => 'Trial',
            'trial_active' => ($days_remaining > 0),
            'trial_days_remaining' => $days_remaining,
            'has_valid_subscription' => false,
            'premium_active' => false,  // ← FIXED: Trial users should NOT have premium_active = true
            'trial_expired' => ($days_remaining <= 0)
        );
    }
    
    return array(
        'subscription_tier' => 'Free',
        'trial_active' => false,
        'trial_days_remaining' => 0,
        'has_valid_subscription' => false,
        'premium_active' => false,
        'trial_expired' => true
    );
}

/**
 * Check if user has app access
 */
function user_has_app_access($user_id) {
    $status = get_user_subscription_status($user_id);
    return $status['has_valid_subscription'] || $status['trial_active'];
}

/**
 * Fixed versions for API consistency
 */
function memre_get_user_subscription_status($user_id) {
    return get_user_subscription_status($user_id);
}

function memre_user_has_access($user_id) {
    return user_has_app_access($user_id);
}

/**
 * ===================================
 * REST API AND AUTHENTICATION
 * ===================================
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
            $username = sanitize_text_field($_SERVER['PHP_AUTH_USER']);
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

/**
 * Add application passwords capability to subscribers
 */
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
    
    // Subscription status endpoint
    register_rest_route('memre/v1', '/user/(?P<user_id>\d+)/subscription', array(
        'methods' => 'GET',
        'callback' => 'memre_subscription_status_api',
        'permission_callback' => '__return_true',
        'args' => array(
            'user_id' => array(
                'validate_callback' => function($param) {
                    return is_numeric($param);
                }
            ),
        ),
    ));
});

/**
 * Authentication handler for the API
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
 * Subscription status API endpoint
 */
function memre_subscription_status_api($request) {
    $user_id = (int) $request['user_id'];
    
    $status = get_user_subscription_status($user_id);
    
    return array(
        'user_id' => $user_id,
        'subscription_tier' => $status['subscription_tier'],
        'trial_active' => $status['trial_active'],
        'trial_days_remaining' => $status['trial_days_remaining'],
        'premium_active' => $status['premium_active'],
        'trial_expired' => $status['trial_expired'],
        'timestamp' => time()
    );
}

/**
 * ===================================
 * USER TABLE MANAGEMENT (NEW SYSTEM)
 * ===================================
 */

/**
 * Database connection function for new MemrE database
 */
function memre_get_memre_database_connection() {
    $memre_host = DB_HOST;
    $memre_database = 'vortis5_memredata';
    $memre_username = 'vortis5_vortismemre';
    $memre_password = 'Wd$)!rU.v2pE';
    
    try {
        $memre_db = new mysqli($memre_host, $memre_username, $memre_password, $memre_database);
        
        if ($memre_db->connect_error) {
            error_log("Failed to connect to MemrE database: " . $memre_db->connect_error);
            return false;
        }
        
        $memre_db->set_charset("utf8mb4");
        return $memre_db;
        
    } catch (Exception $e) {
        error_log("Exception connecting to MemrE database: " . $e->getMessage());
        return false;
    }
}

/**
 * Create user tables in MemrE database
 */
function memre_create_user_tables($memre_db, $user_id) {
    $tables = [
        "user_{$user_id}_memo" => "
            CREATE TABLE `user_{$user_id}_memo` (
                `id` int(11) NOT NULL AUTO_INCREMENT,
                `title` varchar(255) NOT NULL,
                `content` text,
                `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
                `updated_at` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ",
        "user_{$user_id}_reminder" => "
            CREATE TABLE `user_{$user_id}_reminder` (
                `id` int(11) NOT NULL AUTO_INCREMENT,
                `memo_id` int(11),
                `reminder_date` datetime NOT NULL,
                `message` text,
                `is_sent` tinyint(1) DEFAULT 0,
                `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ",
        "user_{$user_id}_attachment" => "
            CREATE TABLE `user_{$user_id}_attachment` (
                `id` int(11) NOT NULL AUTO_INCREMENT,
                `memo_id` int(11),
                `file_name` varchar(255) NOT NULL,
                `file_path` varchar(500) NOT NULL,
                `file_size` int(11),
                `mime_type` varchar(100),
                `uploaded_at` timestamp DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ",
        "user_{$user_id}_memo_reminder" => "
            CREATE TABLE `user_{$user_id}_memo_reminder` (
                `id` int(11) NOT NULL AUTO_INCREMENT,
                `memo_id` int(11) NOT NULL,
                `reminder_id` int(11) NOT NULL,
                `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        "
    ];
    
    $success = true;
    
    foreach ($tables as $table_name => $sql) {
        if (!$memre_db->query($sql)) {
            error_log("Failed to create table $table_name: " . $memre_db->error);
            $success = false;
        } else {
            error_log("Successfully created table: $table_name");
        }
    }
    
    return $success;
}

/**
 * Get user tables from MemrE database
 */
function memre_get_user_tables($user_id) {
    $memre_db = memre_get_memre_database_connection();
    if (!$memre_db) {
        return [];
    }
    
    $result = $memre_db->query("SHOW TABLES");
    if (!$result) {
        $memre_db->close();
        return [];
    }
    
    $all_tables = [];
    while ($row = $result->fetch_array()) {
        $all_tables[] = $row[0];
    }
    
    $user_pattern = "user_{$user_id}_";
    $user_tables = [];
    
    foreach ($all_tables as $table) {
        if (strpos($table, $user_pattern) === 0) {
            $user_tables[] = $table;
        }
    }
    
    $memre_db->close();
    return $user_tables;
}

/**
 * Create backup of user tables
 */
function memre_backup_user_tables($user_id) {
    error_log("Creating backup for user $user_id");
    
    $user_tables = memre_get_user_tables($user_id);
    if (empty($user_tables)) {
        return false;
    }
    
    $memre_db = memre_get_memre_database_connection();
    if (!$memre_db) {
        return false;
    }
    
    // Create backup directory
    $backup_dir = ABSPATH . 'user-backups/';
    if (!file_exists($backup_dir)) {
        wp_mkdir_p($backup_dir);
        file_put_contents($backup_dir . '.htaccess', "Order deny,allow\nDeny from all\n");
    }
    
    $user = get_user_by('id', $user_id);
    $username = $user ? $user->user_login : 'unknown';
    
    $timestamp = date('Y-m-d_H-i-s');
    $backup_filename = "user_{$user_id}_{$username}_backup_{$timestamp}.sql";
    $backup_file = $backup_dir . $backup_filename;
    
    $sql_content = "-- MemrE User Tables Backup\n";
    $sql_content .= "-- User ID: {$user_id}\n";
    $sql_content .= "-- Username: {$username}\n";
    $sql_content .= "-- Database: vortis5_memredata\n";
    $sql_content .= "-- Backup Date: " . current_time('mysql') . "\n\n";
    
    foreach ($user_tables as $table) {
        $sql_content .= "-- Table: $table\n";
        
        // Get table structure
        $create_result = $memre_db->query("SHOW CREATE TABLE `$table`");
        if ($create_result) {
            $create_row = $create_result->fetch_array();
            $sql_content .= "DROP TABLE IF EXISTS `$table`;\n";
            $sql_content .= $create_row[1] . ";\n\n";
        }
        
        // Get table data
        $data_result = $memre_db->query("SELECT * FROM `$table`");
        if ($data_result && $data_result->num_rows > 0) {
            while ($row = $data_result->fetch_assoc()) {
                $sql_content .= "INSERT INTO `$table` (";
                $sql_content .= "`" . implode('`, `', array_keys($row)) . "`";
                $sql_content .= ") VALUES (";
                
                $values = [];
                foreach ($row as $value) {
                    if ($value === null) {
                        $values[] = 'NULL';
                    } else {
                        $values[] = "'" . $memre_db->real_escape_string($value) . "'";
                    }
                }
                
                $sql_content .= implode(', ', $values) . ");\n";
            }
        }
        $sql_content .= "\n";
    }
    
    $memre_db->close();
    
    if (file_put_contents($backup_file, $sql_content) === false) {
        error_log("Failed to write backup file: $backup_file");
        return false;
    }
    
    error_log("Backup created: $backup_file (" . filesize($backup_file) . " bytes)");
    return $backup_file;
}

/**
 * Delete user tables
 */
function memre_delete_user_tables($user_id) {
    error_log("Deleting user $user_id tables from MemrE database");
    
    $user_tables = memre_get_user_tables($user_id);
    if (empty($user_tables)) {
        return ['success' => true, 'tables_deleted' => 0];
    }
    
    $memre_db = memre_get_memre_database_connection();
    if (!$memre_db) {
        return ['success' => false, 'error' => 'Database connection failed'];
    }
    
    // Disable foreign key checks
    $memre_db->query("SET FOREIGN_KEY_CHECKS = 0");
    
    $deleted_count = 0;
    $errors = [];
    
    foreach ($user_tables as $table) {
        if ($memre_db->query("DROP TABLE IF EXISTS `$table`")) {
            $deleted_count++;
            error_log("Dropped table: $table");
        } else {
            $error = "Failed to drop table $table: " . $memre_db->error;
            $errors[] = $error;
            error_log($error);
        }
    }
    
    // Re-enable foreign key checks
    $memre_db->query("SET FOREIGN_KEY_CHECKS = 1");
    $memre_db->close();
    
    $success = ($deleted_count == count($user_tables));
    error_log("Deleted $deleted_count/" . count($user_tables) . " tables");
    
    return [
        'success' => $success,
        'tables_deleted' => $deleted_count,
        'errors' => $errors
    ];
}

/**
 * User registration handler (creates tables in BOTH systems)
 */
function memre_handle_complete_user_registration($user_id) {
    error_log("=== MEMRE COMPLETE USER REGISTRATION for User ID: $user_id ===");
    
    $user = get_user_by('id', $user_id);
    if (!$user) {
        error_log("User not found for ID: $user_id");
        return;
    }
    
    error_log("Creating tables for user: " . $user->user_login . " (ID: $user_id)");
    
    // 1. Create tables in new MemrE database
    $memre_db = memre_get_memre_database_connection();
    if ($memre_db) {
        $tables_created = memre_create_user_tables($memre_db, $user_id);
        error_log("New MemrE tables created for user $user_id: " . ($tables_created ? "SUCCESS" : "FAILED"));
        $memre_db->close();
    }
    
    // 2. Set up free trial
    update_user_meta($user_id, 'is_free_trial', true);
    update_user_meta($user_id, 'registration_date', current_time('Y-m-d H:i:s'));
}

/**
 * User deletion handler
 */
function memre_handle_user_deletion($user_id) {
    error_log("=== MEMRE USER DELETION for User ID: $user_id ===");
    
    $user = get_user_by('id', $user_id);
    $username = $user ? $user->user_login : 'deleted_user';
    
    error_log("Processing deletion for user: $username (ID: $user_id)");
    
    // 1. Create backup
    $backup_file = memre_backup_user_tables($user_id);
    
    // 2. Delete user tables
    $deletion_result = memre_delete_user_tables($user_id);
    
    // 3. Clean up WordPress user meta
    global $wpdb;
    $meta_deleted = $wpdb->delete($wpdb->usermeta, ['user_id' => $user_id], ['%d']);
    
    error_log("=== DELETION SUMMARY ===");
    error_log("User: $username (ID: $user_id)");
    error_log("Backup: " . ($backup_file ? "Created" : "Failed"));
    error_log("Tables deleted: " . $deletion_result['tables_deleted']);
    error_log("Meta deleted: $meta_deleted");
    error_log("Success: " . ($deletion_result['success'] ? "YES" : "NO"));
    
    return $deletion_result['success'];
}

/**
 * ===================================
 * OLD SYSTEM TABLE CREATION (KEEPING FOR MEMO FUNCTIONALITY)
 * ===================================
 */

/**
 * Table Creation on User Registration for old system
 */
add_action('um_registration_complete', 'create_user_tables_simplified', 10, 1);
function create_user_tables_simplified($user_id) {
    try {
        $custom_db = get_custom_db_connection();

        $table_prefix = 'user_' . $user_id . '_';
        $memo_table = $table_prefix . 'memo';
        $reminder_table = $table_prefix . 'reminder';
        $memo_reminder_table = $table_prefix . 'memo_reminder';
        $attachment_table = $table_prefix . 'attachment';

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

        // Store table names in user meta
        $tables = [
            'memo_table' => $memo_table,
            'reminder_table' => $reminder_table,
            'memo_reminder_table' => $memo_reminder_table,
            'attachment_table' => $attachment_table
        ];

        foreach ($tables as $key => $table) {
            update_user_meta($user_id, "user_$key", $table);
        }

        // Also call the new system
        memre_handle_complete_user_registration($user_id);

    } catch (Exception $e) {
        error_log("Error creating user tables: " . $e->getMessage());
        if (function_exists('wp_mail')) {
            wp_mail(
                get_option('admin_email'),
                'Database Error on User Registration',
                'Error creating tables for user ID ' . $user_id . ': ' . $e->getMessage()
            );
        }
    } finally {
        if (isset($custom_db) && $custom_db instanceof mysqli) {
            $custom_db->close();
        }
    }
}

/**
 * ===================================
 * MEMO AJAX HANDLERS (KEEPING FOR EXISTING FUNCTIONALITY)
 * ===================================
 */

/**
 * Save memo handler
 */
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

       $custom_db = get_custom_db_connection();
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
 * ===================================
 * SUBSCRIPTION SHORTCODE AND FRONTEND
 * ===================================
 */

/**
 * Enhanced subscription options shortcode
 */
function enhanced_subscription_options_shortcode($atts) {
    $atts = shortcode_atts(array(
        'stripe_plan_id' => '88',
        'show_trial_info' => 'true',
        'show_features' => 'true'
    ), $atts);
    
    $current_user_id = get_current_user_id();
    
    if (!$current_user_id) {
        return '<p>Please log in to view your subscription status.</p>';
    }
    
    $subscription_status = get_user_subscription_status($current_user_id);
    
    ob_start();
    ?>
    
    <div class="memre-subscription-container" style="max-width: 600px; margin: 20px auto; padding: 20px; border: 1px solid #ddd; border-radius: 8px; background: #f9f9f9;">
        
        <?php if ($subscription_status['subscription_tier'] === 'Trial' && $subscription_status['trial_active']): ?>
            <!-- ACTIVE TRIAL -->
            <div class="trial-status" style="background: #e7f3ff; padding: 20px; border-radius: 6px; border-left: 4px solid #0073aa; margin-bottom: 20px;">
                <h3 style="margin-top: 0; color: #0073aa;">🎉 Free Trial Active</h3>
                <p style="font-size: 18px; margin: 10px 0;">
                    <strong><?php echo $subscription_status['trial_days_remaining']; ?> days remaining</strong>
                </p>
            </div>
            
            <div class="upgrade-section" style="text-align: center; background: white; padding: 25px; border-radius: 6px;">
                <h3 style="margin-top: 0; color: #333;">Upgrade to MemrE Premium</h3>
                <div style="font-size: 32px; font-weight: bold; color: #0073aa; margin: 15px 0;">
                    $8.99 <span style="font-size: 18px; font-weight: normal; color: #666;">/month</span>
                </div>
                
                <div class="stripe-checkout-container">
                    <?php echo do_shortcode('[ultimatemember_stripe_checkout id="' . esc_attr($atts['stripe_plan_id']) . '"]'); ?>
                </div>
            </div>
            
        <?php elseif ($subscription_status['subscription_tier'] === 'Free' || $subscription_status['trial_expired']): ?>
            <!-- TRIAL EXPIRED -->
            <div class="trial-expired" style="background: #fff3cd; padding: 20px; border-radius: 6px; border-left: 4px solid #ffc107; margin-bottom: 20px;">
                <h3 style="margin-top: 0; color: #856404;">⏰ Trial Has Expired</h3>
                <p style="margin-bottom: 0;">Your 14-day free trial has ended.</p>
            </div>
            
            <div class="restore-access" style="text-align: center; background: white; padding: 25px; border-radius: 6px;">
                <h3 style="margin-top: 0; color: #333;">Restore Full Access</h3>
                <div style="font-size: 32px; font-weight: bold; color: #0073aa; margin: 15px 0;">
                    $8.99 <span style="font-size: 18px; font-weight: normal; color: #666;">/month</span>
                </div>
                
                <div class="stripe-checkout-container" style="margin: 25px 0;">
                    <?php echo do_shortcode('[ultimatemember_stripe_checkout id="' . esc_attr($atts['stripe_plan_id']) . '"]'); ?>
                </div>
            </div>
            
        <?php else: ?>
            <!-- ACTIVE SUBSCRIPTION -->
            <div class="subscription-active" style="background: #d4edda; padding: 20px; border-radius: 6px; border-left: 4px solid #28a745; margin-bottom: 20px;">
                <h3 style="margin-top: 0; color: #155724;">✅ MemrE Premium Active</h3>
                <p style="margin-bottom: 0;">
                    <strong>Status:</strong> <?php echo $subscription_status['subscription_tier']; ?><br>
                    Thank you for being a MemrE Premium member!
                </p>
            </div>
            
        <?php endif; ?>
        
    </div>
    
    <?php
    return ob_get_clean();
}

add_shortcode('memre_subscription_options', 'enhanced_subscription_options_shortcode');

/**
 * Simple subscription options shortcode (RESTORED)
 */
function simple_subscription_options_shortcode($atts) {
    $atts = shortcode_atts(array(
        'stripe_plan_id' => '88',
    ), $atts);
    
    $current_user_id = get_current_user_id();
    
    if (!$current_user_id) {
        return '<p>Please log in to view your subscription status.</p>';
    }
    
    $subscription_status = get_user_subscription_status($current_user_id);
    
    ob_start();
    ?>
    
    <div class="simple-subscription-container" style="max-width: 500px; margin: 20px auto; padding: 20px; border: 1px solid #ddd; border-radius: 8px; background: white;">
        
        <?php if ($subscription_status['trial_active']): ?>
            <!-- ACTIVE TRIAL -->
            <div style="background: #e7f3ff; padding: 15px; border-radius: 5px; margin-bottom: 20px; text-align: center;">
                <h3 style="margin: 0 0 10px 0; color: #0073aa;">🎉 Free Trial Active</h3>
                <p style="margin: 0; font-size: 16px;">
                    <strong><?php echo $subscription_status['trial_days_remaining']; ?> days remaining</strong>
                </p>
            </div>
            
            <div style="text-align: center;">
                <h4 style="margin-bottom: 15px;">Upgrade to Premium</h4>
                <div style="font-size: 24px; font-weight: bold; color: #0073aa; margin-bottom: 15px;">
                    $8.99/month
                </div>
                
                <?php echo do_shortcode('[ultimatemember_stripe_checkout id="' . esc_attr($atts['stripe_plan_id']) . '"]'); ?>
            </div>
            
        <?php elseif ($subscription_status['trial_expired']): ?>
            <!-- TRIAL EXPIRED -->
            <div style="background: #fff3cd; padding: 15px; border-radius: 5px; margin-bottom: 20px; text-align: center;">
                <h3 style="margin: 0 0 10px 0; color: #856404;">⏰ Trial Expired</h3>
                <p style="margin: 0;">Your free trial has ended. Upgrade to continue.</p>
            </div>
            
            <div style="text-align: center;">
                <h4 style="margin-bottom: 15px;">Restore Access</h4>
                <div style="font-size: 24px; font-weight: bold; color: #0073aa; margin-bottom: 15px;">
                    $8.99/month
                </div>
                
                <?php echo do_shortcode('[ultimatemember_stripe_checkout id="' . esc_attr($atts['stripe_plan_id']) . '"]'); ?>
            </div>
            
        <?php else: ?>
            <!-- ACTIVE SUBSCRIPTION -->
            <div style="background: #d4edda; padding: 15px; border-radius: 5px; text-align: center;">
                <h3 style="margin: 0 0 10px 0; color: #155724;">✅ Premium Active</h3>
                <p style="margin: 0;">
                    Status: <?php echo $subscription_status['subscription_tier']; ?>
                </p>
            </div>
            
        <?php endif; ?>
        
    </div>
    
    <?php
    return ob_get_clean();
}

add_shortcode('simple_subscription_options', 'simple_subscription_options_shortcode');

/**
 * Auto-replace old shortcode with new one (optional)
 */
function replace_old_subscription_shortcode($content) {
    // You can uncomment this if you want to automatically replace
    // $content = str_replace('[simple_subscription_options]', '[memre_subscription_options]', $content);
    return $content;
}
add_filter('the_content', 'replace_old_subscription_shortcode');

/**
 * ===================================
 * USER MANAGEMENT AND UTILITIES
 * ===================================
 */

/**
 * Set default role for new users
 */
function set_default_user_role($user_id) {
    $user = new WP_User($user_id);
    $user->set_role('subscriber');
}
add_action('user_register', 'set_default_user_role');

/**
 * Custom login redirect
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
 * Clean username registration
 */
function ensure_clean_username_registration($user_data) {
    if (isset($user_data['user_login']) && preg_match('/^(.+)-\d+$/', $user_data['user_login'], $matches)) {
        $clean_username = $matches[1];
        
        if (!username_exists($clean_username) && validate_username($clean_username)) {
            $user_data['user_login'] = $clean_username;
        }
    }
    
    return $user_data;
}
add_filter('um_add_user_frontend', 'ensure_clean_username_registration', 5);

/**
 * ===================================
 * HOOK SETUP AND INITIALIZATION
 * ===================================
 */

/**
 * Hook into WordPress user deletion for both systems
 */
add_action('delete_user', 'memre_handle_user_deletion');
add_action('deleted_user', 'memre_handle_user_deletion');
add_action('um_delete_user', 'memre_handle_user_deletion');
add_action('um_after_user_delete', 'memre_handle_user_deletion');

/**
 * Optional: Admin notice for successful setup
 */
function memre_show_setup_success_notice() {
    if (current_user_can('manage_options') && get_transient('memre_setup_complete')) {
        echo '<div class="notice notice-success is-dismissible">';
        echo '<p><strong>MemrE System:</strong> User table management is active and working correctly.</p>';
        echo '</div>';
        delete_transient('memre_setup_complete');
    }
}
add_action('admin_notices', 'memre_show_setup_success_notice');

// Set the success transient on first load
if (!get_transient('memre_setup_complete')) {
    set_transient('memre_setup_complete', true, 60);
}

add_action('wp_ajax_test_ajax', 'test_ajax_handler');
function test_ajax_handler() {
    error_log("Test AJAX called successfully");
    wp_send_json_success(['message' => 'AJAX is working']);
}

// Add REST API endpoint for account deletion
add_action('rest_api_init', function () {
    // Account deletion endpoint
    register_rest_route('memre-app/v1', '/delete-account', array(
        'methods' => 'DELETE',
        'callback' => 'handle_account_deletion_request',
        'permission_callback' => 'check_account_deletion_permission'
    ));
    
    // Account deletion status endpoint
    register_rest_route('memre-app/v1', '/deletion-status/(?P<request_id>[a-zA-Z0-9]+)', array(
        'methods' => 'GET',
        'callback' => 'get_deletion_status',
        'permission_callback' => '__return_true'
    ));
});

/**
 * Check if user can delete their account
 */
function check_account_deletion_permission($request) {
    $user_id = get_current_user_id();
    
    if (!$user_id) {
        return new WP_Error(
            'not_logged_in',
            'You must be logged in to delete your account.',
            array('status' => 401)
        );
    }
    
    return true;
}

/**
 * Handle account deletion request
 */
function handle_account_deletion_request($request) {
    $user_id = get_current_user_id();
    $user = get_user_by('id', $user_id);
    
    if (!$user) {
        return new WP_Error(
            'user_not_found',
            'User not found.',
            array('status' => 404)
        );
    }
    
    // Generate deletion request ID
    $request_id = wp_generate_uuid4();
    
    // Store deletion request
    update_user_meta($user_id, 'deletion_request_id', $request_id);
    update_user_meta($user_id, 'deletion_request_date', current_time('mysql'));
    update_user_meta($user_id, 'deletion_status', 'pending');
    
    // Log deletion request
    error_log("Account deletion requested for user {$user_id} ({$user->user_login})");
    
    // Send confirmation email
    $deletion_url = home_url("/confirm-deletion/?request_id={$request_id}");
    
    $subject = 'Account Deletion Request - MemrE';
    $message = "Hi {$user->display_name},\n\n";
    $message .= "You have requested to delete your MemrE account. This action is permanent and cannot be undone.\n\n";
    $message .= "What will be deleted:\n";
    $message .= "• Your account and profile information\n";
    $message .= "• All your memos and reminders\n";
    $message .= "• All attachments and files\n";
    $message .= "• Your subscription (if active)\n\n";
    $message .= "To confirm deletion, click this link:\n";
    $message .= $deletion_url . "\n\n";
    $message .= "If you did not request this deletion, please contact our support team immediately.\n\n";
    $message .= "This request will expire in 7 days.\n\n";
    $message .= "Thank you,\nThe MemrE Team";
    
    wp_mail($user->user_email, $subject, $message);
    
    return array(
        'success' => true,
        'message' => 'Account deletion request submitted. Check your email for confirmation.',
        'request_id' => $request_id,
        'expires_in' => '7 days'
    );
}

/**
 * Get deletion status
 */
function get_deletion_status($request) {
    $request_id = $request['request_id'];
    
    // Find user with this deletion request ID
    $users = get_users(array(
        'meta_key' => 'deletion_request_id',
        'meta_value' => $request_id,
        'number' => 1
    ));
    
    if (empty($users)) {
        return new WP_Error(
            'request_not_found',
            'Deletion request not found.',
            array('status' => 404)
        );
    }
    
    $user = $users[0];
    $status = get_user_meta($user->ID, 'deletion_status', true);
    $request_date = get_user_meta($user->ID, 'deletion_request_date', true);
    
    return array(
        'request_id' => $request_id,
        'status' => $status,
        'requested_date' => $request_date,
        'user_id' => $user->ID
    );
}

/**
 * Create account deletion confirmation page
 */
function create_account_deletion_page() {
    // Check if deletion page exists
    $page = get_page_by_path('confirm-deletion');
    
    if (!$page) {
        // Create the page
        $page_data = array(
            'post_title' => 'Confirm Account Deletion',
            'post_content' => '[account_deletion_form]',
            'post_status' => 'publish',
            'post_type' => 'page',
            'post_name' => 'confirm-deletion'
        );
        
        wp_insert_post($page_data);
    }
}

// Create deletion page on theme activation
add_action('after_switch_theme', 'create_account_deletion_page');

/**
 * Account deletion confirmation shortcode
 */
function account_deletion_form_shortcode($atts) {
    $request_id = isset($_GET['request_id']) ? sanitize_text_field($_GET['request_id']) : '';
    
    if (empty($request_id)) {
        return '<div class="error">Invalid deletion request.</div>';
    }
    
    // Find user with this request ID
    $users = get_users(array(
        'meta_key' => 'deletion_request_id',
        'meta_value' => $request_id,
        'number' => 1
    ));
    
    if (empty($users)) {
        return '<div class="error">Deletion request not found or expired.</div>';
    }
    
    $user = $users[0];
    $request_date = get_user_meta($user->ID, 'deletion_request_date', true);
    
    // Check if request is expired (7 days)
    if (strtotime($request_date) < strtotime('-7 days')) {
        return '<div class="error">This deletion request has expired. Please submit a new request.</div>';
    }
    
    // Handle form submission
    if (isset($_POST['confirm_deletion']) && wp_verify_nonce($_POST['deletion_nonce'], 'confirm_deletion')) {
        
        // Final confirmation checkbox
        if (!isset($_POST['final_confirmation'])) {
            return '<div class="error">Please check the confirmation box to proceed.</div>';
        }
        
        // Process deletion
        $deletion_result = process_account_deletion($user->ID);
        
        if ($deletion_result['success']) {
            return '<div class="success">
                <h3>Account Deleted Successfully</h3>
                <p>Your account and all associated data have been permanently deleted.</p>
                <p>Thank you for using MemrE.</p>
            </div>';
        } else {
            return '<div class="error">Error deleting account: ' . $deletion_result['message'] . '</div>';
        }
    }
    
    ob_start();
    ?>
    <div class="account-deletion-form">
        <h2>Confirm Account Deletion</h2>
        
        <div class="warning-box">
            <h3>⚠️ Warning: This action is permanent</h3>
            <p>You are about to permanently delete your MemrE account for: <strong><?php echo esc_html($user->user_email); ?></strong></p>
        </div>
        
        <div class="deletion-details">
            <h4>The following will be permanently deleted:</h4>
            <ul>
                <li>Your account and profile information</li>
                <li>All your memos and reminders</li>
                <li>All attachments and files</li>
                <li>Your subscription (if active)</li>
                <li>All usage history and data</li>
            </ul>
        </div>
        
        <form method="post" class="deletion-form">
            <?php wp_nonce_field('confirm_deletion', 'deletion_nonce'); ?>
            
            <label class="confirmation-checkbox">
                <input type="checkbox" name="final_confirmation" required>
                I understand that this action is permanent and cannot be undone. I want to delete my account and all associated data.
            </label>
            
            <div class="form-actions">
                <button type="submit" name="confirm_deletion" class="delete-button">
                    Delete My Account Permanently
                </button>
                
                <a href="<?php echo home_url('/dashboard/'); ?>" class="cancel-button">
                    Cancel - Keep My Account
                </a>
            </div>
        </form>
    </div>
    
    <style>
    .account-deletion-form {
        max-width: 600px;
        margin: 20px auto;
        padding: 20px;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
    
    .warning-box {
        background: #fff3cd;
        border: 1px solid #ffeaa7;
        border-radius: 8px;
        padding: 20px;
        margin: 20px 0;
    }
    
    .deletion-details {
        background: #f8f9fa;
        border-radius: 8px;
        padding: 20px;
        margin: 20px 0;
    }
    
    .deletion-details ul {
        margin: 10px 0;
        padding-left: 20px;
    }
    
    .deletion-details li {
        margin: 5px 0;
    }
    
    .confirmation-checkbox {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        margin: 20px 0;
        padding: 15px;
        background: #e9ecef;
        border-radius: 8px;
    }
    
    .confirmation-checkbox input[type="checkbox"] {
        margin-top: 3px;
        transform: scale(1.2);
    }
    
    .form-actions {
        display: flex;
        gap: 15px;
        justify-content: center;
        margin-top: 30px;
    }
    
    .delete-button {
        background: #dc3545;
        color: white;
        padding: 12px 30px;
        border: none;
        border-radius: 8px;
        font-size: 16px;
        cursor: pointer;
        transition: background 0.3s;
    }
    
    .delete-button:hover {
        background: #c82333;
    }
    
    .cancel-button {
        background: #6c757d;
        color: white;
        padding: 12px 30px;
        border-radius: 8px;
        text-decoration: none;
        font-size: 16px;
        transition: background 0.3s;
    }
    
    .cancel-button:hover {
        background: #5a6268;
    }
    
    .success {
        background: #d4edda;
        color: #155724;
        border: 1px solid #c3e6cb;
        border-radius: 8px;
        padding: 20px;
        text-align: center;
    }
    
    .error {
        background: #f8d7da;
        color: #721c24;
        border: 1px solid #f5c6cb;
        border-radius: 8px;
        padding: 20px;
        text-align: center;
    }
    </style>
    <?php
    
    return ob_get_clean();
}

add_shortcode('account_deletion_form', 'account_deletion_form_shortcode');

/**
 * Process actual account deletion
 */
function process_account_deletion($user_id) {
    try {
        // Get user info for logging
        $user = get_user_by('id', $user_id);
        $user_email = $user->user_email;
        $username = $user->user_login;
        
        // Cancel any active subscriptions first
        cancel_user_subscriptions($user_id);
        
        // Delete user data using existing function
        $deletion_result = memre_handle_user_deletion($user_id);
        
        // Delete the WordPress user
        if (function_exists('wp_delete_user')) {
            $deleted = wp_delete_user($user_id);
            
            if ($deleted) {
                // Log successful deletion
                error_log("Account successfully deleted: User ID {$user_id}, Email: {$user_email}");
                
                // Send confirmation email
                $subject = 'Account Deletion Completed - MemrE';
                $message = "This confirms that your MemrE account ({$user_email}) has been permanently deleted.\n\n";
                $message .= "All your data has been removed from our systems.\n\n";
                $message .= "Thank you for using MemrE.\n\n";
                $message .= "The MemrE Team";
                
                wp_mail($user_email, $subject, $message);
                
                return array(
                    'success' => true,
                    'message' => 'Account deleted successfully'
                );
            } else {
                throw new Exception('Failed to delete WordPress user');
            }
        } else {
            throw new Exception('wp_delete_user function not available');
        }
        
    } catch (Exception $e) {
        error_log("Account deletion error for user {$user_id}: " . $e->getMessage());
        
        return array(
            'success' => false,
            'message' => 'An error occurred during account deletion. Please contact support.'
        );
    }
}

/**
 * Cancel user subscriptions before deletion
 */
function cancel_user_subscriptions($user_id) {
    global $wpdb;
    
    // Update any active subscriptions to canceled
    $subscription_table = $wpdb->prefix . 'um_stripe_subscriptions';
    
    $wpdb->update(
        $subscription_table,
        array('status' => 'canceled'),
        array('user_id' => $user_id),
        array('%s'),
        array('%d')
    );
    
    error_log("Canceled subscriptions for user {$user_id}");
}

/**
 * Add account deletion link to Ultimate Member account page
 */
function add_account_deletion_link_to_um_account() {
    if (is_user_logged_in()) {
        $deletion_url = home_url('/confirm-deletion/?request_id=new');
        echo '<div class="um-account-deletion-section">';
        echo '<h3>Account Deletion</h3>';
        echo '<p>If you wish to permanently delete your account and all associated data, you can do so here.</p>';
        echo '<a href="' . esc_url($deletion_url) . '" class="button delete-account-button" onclick="return confirm(\'Are you sure you want to delete your account? This action cannot be undone.\');">Delete My Account</a>';
        echo '</div>';
        
        echo '<style>
        .um-account-deletion-section {
            margin-top: 30px;
            padding: 20px;
            border: 1px solid #e1e1e1;
            border-radius: 8px;
            background: #f9f9f9;
        }
        .delete-account-button {
            background: #dc3545;
            color: white;
            padding: 10px 20px;
            border: none;
            border-radius: 4px;
            text-decoration: none;
            display: inline-block;
            margin-top: 10px;
        }
        .delete-account-button:hover {
            background: #c82333;
            color: white;
        }
        </style>';
    }
}

// Add deletion link to Ultimate Member account page
add_action('um_account_tab_general', 'add_account_deletion_link_to_um_account');

// Handle new deletion requests
add_action('init', function() {
    if (isset($_GET['request_id']) && $_GET['request_id'] === 'new' && is_user_logged_in()) {
        $user_id = get_current_user_id();
        
        // Create new deletion request
        $request_id = wp_generate_uuid4();
        update_user_meta($user_id, 'deletion_request_id', $request_id);
        update_user_meta($user_id, 'deletion_request_date', current_time('mysql'));
        update_user_meta($user_id, 'deletion_status', 'pending');
        
        // Redirect to confirmation page
        wp_redirect(home_url("/confirm-deletion/?request_id={$request_id}"));
        exit;
    }
});
// Add REST API endpoints for app registration
add_action('rest_api_init', function () {
    // User registration endpoint that triggers Ultimate Member hooks
    register_rest_route('memre/v1', '/register-user', array(
        'methods' => 'POST',
        'callback' => 'memre_register_user_with_tables',
        'permission_callback' => '__return_true',
    ));
    
    // Ensure user tables exist endpoint
    register_rest_route('memre/v1', '/user/(?P<user_id>\d+)/ensure-tables', array(
        'methods' => 'POST',
        'callback' => 'memre_ensure_user_tables',
        'permission_callback' => 'memre_check_user_permission',
        'args' => array(
            'user_id' => array(
                'validate_callback' => function($param) {
                    return is_numeric($param);
                }
            ),
        ),
    ));
});

/**
 * Register user through Ultimate Member system to ensure table creation
 */
function memre_register_user_with_tables($request) {
    try {
        $params = $request->get_json_params();
        
        $username = sanitize_text_field($params['username'] ?? '');
        $email = sanitize_email($params['email'] ?? '');
        $password = $params['password'] ?? '';
        $display_name = sanitize_text_field($params['display_name'] ?? $username);
        
        error_log("=== MEMRE APP REGISTRATION ===");
        error_log("Username: $username");
        error_log("Email: $email");
        error_log("Display Name: $display_name");
        
        // Validate required fields
        if (empty($username) || empty($email) || empty($password)) {
            return new WP_Error(
                'missing_fields',
                'Username, email, and password are required',
                array('status' => 400)
            );
        }
        
        // Check if user already exists
        if (username_exists($username) || email_exists($email)) {
            return new WP_Error(
                'user_exists',
                'Username or email already exists',
                array('status' => 409)
            );
        }
        
        // Create WordPress user
        $user_data = array(
            'user_login' => $username,
            'user_email' => $email,
            'user_pass' => $password,
            'display_name' => $display_name,
            'role' => 'subscriber',
        );
        
        $user_id = wp_insert_user($user_data);
        
        if (is_wp_error($user_id)) {
            error_log("WordPress user creation failed: " . $user_id->get_error_message());
            return new WP_Error(
                'registration_failed',
                $user_id->get_error_message(),
                array('status' => 400)
            );
        }
        
        error_log("WordPress user created successfully: ID $user_id");
        
        // IMPORTANT: Trigger Ultimate Member registration completion
        // This ensures your database tables get created
        $tables_created = false;
        
        try {
            // Method 1: Direct function call if UM is loaded
            if (function_exists('um_fetch_user')) {
                error_log("Triggering Ultimate Member registration completion...");
                
                // Set up UM user data
                um_fetch_user($user_id);
                
                // Trigger the UM registration complete action
                do_action('um_registration_complete', $user_id, array());
                
                // Also trigger your custom table creation
                memre_handle_complete_user_registration($user_id);
                
                $tables_created = true;
                error_log("Ultimate Member registration completion triggered successfully");
            } else {
                // Method 2: Direct table creation if UM not available
                error_log("Ultimate Member not available, creating tables directly...");
                memre_handle_complete_user_registration($user_id);
                $tables_created = true;
            }
            
            // Set up free trial
            update_user_meta($user_id, 'is_free_trial', true);
            update_user_meta($user_id, 'registration_date', current_time('Y-m-d H:i:s'));
            update_user_meta($user_id, 'registration_source', 'mobile_app');
            
            // Verify tables were created
            $table_verification = memre_verify_user_tables($user_id);
            
            error_log("Table creation result: " . ($tables_created ? 'SUCCESS' : 'FAILED'));
            error_log("Table verification: " . print_r($table_verification, true));
            
        } catch (Exception $e) {
            error_log("Error during table creation: " . $e->getMessage());
            // Don't fail registration if table creation fails - we can retry later
        }
        
        return array(
            'success' => true,
            'user_id' => $user_id,
            'message' => 'User registered successfully',
            'tables_created' => $tables_created,
            'table_verification' => $table_verification ?? array(),
        );
        
    } catch (Exception $e) {
        error_log("Registration exception: " . $e->getMessage());
        return new WP_Error(
            'registration_error',
            'Registration failed: ' . $e->getMessage(),
            array('status' => 500)
        );
    }
}

/**
 * Ensure user tables exist (create if missing)
 */
function memre_ensure_user_tables($request) {
    $user_id = (int) $request['user_id'];
    
    try {
        error_log("=== ENSURING TABLES FOR USER $user_id ===");
        
        // First, verify if tables already exist
        $existing_tables = memre_verify_user_tables($user_id);
        
        if ($existing_tables['all_exist']) {
            error_log("All tables already exist for user $user_id");
            return array(
                'success' => true,
                'tables_created' => false,
                'tables_verified' => true,
                'existing_tables' => $existing_tables,
            );
        }
        
        error_log("Some tables missing for user $user_id, creating...");
        
        // Create missing tables
        $creation_result = memre_handle_complete_user_registration($user_id);
        
        // Verify creation
        $verification_result = memre_verify_user_tables($user_id);
        
        // Set up trial if not already set
        $is_trial = get_user_meta($user_id, 'is_free_trial', true);
        if (!$is_trial) {
            update_user_meta($user_id, 'is_free_trial', true);
            update_user_meta($user_id, 'registration_date', current_time('Y-m-d H:i:s'));
        }
        
        error_log("Tables creation completed for user $user_id");
        
        return array(
            'success' => true,
            'tables_created' => true,
            'tables_verified' => $verification_result['all_exist'],
            'verification_details' => $verification_result,
        );
        
    } catch (Exception $e) {
        error_log("Error ensuring tables for user $user_id: " . $e->getMessage());
        return new WP_Error(
            'table_creation_error',
            'Failed to create user tables: ' . $e->getMessage(),
            array('status' => 500)
        );
    }
}

/**
 * Verify user tables exist in both database systems
 */
function memre_verify_user_tables($user_id) {
    $result = array(
        'all_exist' => false,
        'old_system_tables' => array(),
        'new_system_tables' => array(),
        'old_system_count' => 0,
        'new_system_count' => 0,
    );
    
    try {
        // Check old system tables (WordPress database)
        $old_system_tables = array(
            "user_{$user_id}_memo",
            "user_{$user_id}_reminder", 
            "user_{$user_id}_memo_reminder",
            "user_{$user_id}_attachment"
        );
        
        global $wpdb;
        foreach ($old_system_tables as $table) {
            $table_exists = $wpdb->get_var("SHOW TABLES LIKE '$table'") == $table;
            $result['old_system_tables'][$table] = $table_exists;
            if ($table_exists) $result['old_system_count']++;
        }
        
        // Check new system tables (MemrE database)
        $new_system_tables = memre_get_user_tables($user_id);
        $result['new_system_tables'] = $new_system_tables;
        $result['new_system_count'] = count($new_system_tables);
        
        // Consider tables complete if we have at least the memo table in old system
        $has_memo_table = $result['old_system_tables']["user_{$user_id}_memo"] ?? false;
        $result['all_exist'] = $has_memo_table;
        
        error_log("Table verification for user $user_id: " . print_r($result, true));
        
    } catch (Exception $e) {
        error_log("Error verifying tables for user $user_id: " . $e->getMessage());
    }
    
    return $result;
}

/**
 * Check permission for user-specific endpoints
 */
function memre_check_user_permission($request) {
    $user_id = (int) $request['user_id'];
    $current_user_id = get_current_user_id();
    
    // Allow if current user is the same user or an admin
    if ($current_user_id == $user_id || current_user_can('manage_options')) {
        return true;
    }
    
    return new WP_Error(
        'forbidden',
        'You do not have permission to access this user\'s data',
        array('status' => 403)
    );
}

/**
 * Enhanced subscription status endpoint that includes table verification
 */
function memre_subscription_status_with_tables_api($request) {
    $user_id = (int) $request['user_id'];
    
    // Get standard subscription status
    $status = get_user_subscription_status($user_id);
    
    // Add table verification
    $table_status = memre_verify_user_tables($user_id);
    
    return array(
        'user_id' => $user_id,
        'subscription_tier' => $status['subscription_tier'],
        'trial_active' => $status['trial_active'],
        'trial_days_remaining' => $status['trial_days_remaining'],
        'premium_active' => $status['premium_active'],
        'trial_expired' => $status['trial_expired'],
        'tables_verified' => $table_status['all_exist'],
        'table_details' => $table_status,
        'timestamp' => time()
    );
}

// Update the existing subscription endpoint to include table verification
add_action('rest_api_init', function () {
    register_rest_route('memre/v1', '/user/(?P<user_id>\d+)/subscription-with-tables', array(
        'methods' => 'GET',
        'callback' => 'memre_subscription_status_with_tables_api',
        'permission_callback' => 'memre_check_user_permission',
        'args' => array(
            'user_id' => array(
                'validate_callback' => function($param) {
                    return is_numeric($param);
                }
            ),
        ),
    ));
});
?>