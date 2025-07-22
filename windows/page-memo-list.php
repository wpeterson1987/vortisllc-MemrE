<?php
/*
Template Name: Memre List
*/

// Enable error reporting for debugging
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Enqueue required scripts and styles
wp_enqueue_script('jquery');
wp_enqueue_style('dashicons');

get_header();

try {
    // Get current user ID
    $current_user_id = get_current_user_id();
    if (!$current_user_id) {
        throw new Exception('User not logged in');
    }

    // Database connection
    $custom_db = new mysqli(
        CUSTOM_DB_HOST,
        CUSTOM_DB_USER,
        CUSTOM_DB_PASSWORD,
        CUSTOM_DB_NAME
    );

    if ($custom_db->connect_error) {
        throw new Exception("Database connection failed: " . $custom_db->connect_error);
    }

// Main query
$query = "
SELECT 
    m.memo_id,
    m.memo_desc,
    m.memo,
    a.file_type,
    a.file_name,
    a.file_data,
    GROUP_CONCAT(DISTINCT CONCAT(
        r.reminder_time, ':::',
        COALESCE(r.repeat_type, ''), ':::',
        COALESCE(r.repeat_until, ''), ':::',
        COALESCE(r.use_screen_notification, 1), ':::',
        COALESCE(r.email_address, ''), ':::',
        COALESCE(r.phone_number, ''), ':::',
        COALESCE(r.email_addresses, ''), ':::',
        COALESCE(r.phone_numbers, '')
    )) as reminders
FROM user_{$current_user_id}_memo m
LEFT JOIN user_{$current_user_id}_attachment a ON m.memo_id = a.memo_id
LEFT JOIN user_{$current_user_id}_memo_reminder mr ON m.memo_id = mr.memo_id
LEFT JOIN user_{$current_user_id}_reminder r ON mr.reminder_id = r.reminder_id
GROUP BY m.memo_id
ORDER BY m.memo_id DESC";

    $memos_result = $custom_db->query($query);
    if ($memos_result === false) {
        throw new Exception("Query failed: " . $custom_db->error);
    }
    ?>

    <div class="container">
        <div class="list-header">
            <h1>Your MemrEs</h1>
            <a href="<?php echo home_url('/memre-input/'); ?>" class="button add-new-button">
                <span class="dashicons dashicons-plus-alt2"></span> Add New MemrE
            </a>
        </div>
		<!-- Add search bar -->
			<div class="search-container">
    			<input type="text" id="memo-search" placeholder="Search memos..." 					class="search-input">
    			<button id="refresh-memos" class="refresh-button button">
        		<span class="dashicons dashicons-update"></span>
    			</button>
			</div>

        <div class="memo-list">
            <?php if ($memos_result->num_rows > 0): ?>
    <?php while($memo = $memos_result->fetch_assoc()): ?>
        <div class="memo-item">
            <h3><?php echo htmlspecialchars($memo['memo_desc'] ?? ''); ?></h3>
            
            <div class="memo-content">
                <?php echo nl2br(htmlspecialchars($memo['memo'] ?? '')); ?>
            </div>

            <?php if (!empty($memo['file_type']) && !empty($memo['file_data'])): ?>
                <div class="memo-attachment">
                    <div class="attachment-info">
                        <span class="dashicons dashicons-paperclip"></span>
                        <?php echo htmlspecialchars($memo['file_name'] ?? ''); ?>
                    </div>
                    <?php if ($memo['file_type'] === 'image'): ?>
                        <img src="data:image/jpeg;base64,<?php echo base64_encode($memo['file_data']); ?>" 
                             alt="<?php echo htmlspecialchars($memo['file_name'] ?? 'Attached Image'); ?>" 
                             class="attachment-preview">
                    <?php endif; ?>
                </div>
            <?php endif; ?>

            

            <?php if (!empty($memo['reminders'])): ?>
    <div class="memo-reminders">
        <?php 
        $reminders = explode(',', $memo['reminders']);
        foreach($reminders as $reminder): 
            $reminder_parts = explode(':::', $reminder);
            $time = isset($reminder_parts[0]) ? trim($reminder_parts[0]) : '';
            $repeat_type = isset($reminder_parts[1]) ? trim($reminder_parts[1]) : '';
            $repeat_until = isset($reminder_parts[2]) ? trim($reminder_parts[2]) : '';
            $use_screen = isset($reminder_parts[3]) ? (bool)trim($reminder_parts[3]) : true;
            $email = isset($reminder_parts[4]) ? trim($reminder_parts[4]) : '';
            $phone = isset($reminder_parts[5]) ? trim($reminder_parts[5]) : '';
            $emails = isset($reminder_parts[6]) ? explode('|', trim($reminder_parts[6])) : [];
            $phones = isset($reminder_parts[7]) ? explode('|', trim($reminder_parts[7])) : [];
            
            // Count recipients
            $email_count = !empty($emails) ? count($emails) : (!empty($email) ? 1 : 0);
            $phone_count = !empty($phones) ? count($phones) : (!empty($phone) ? 1 : 0);

            if (!empty($time)):
            ?>
                <span class="chip reminder-chip">
                    <div class="reminder-info">
                        <span class="dashicons dashicons-clock"></span>
                        <?php 
                        echo date('M d, Y h:i A', strtotime($time));
                        if (!empty($repeat_type)) {
                            echo " (Repeats $repeat_type";
                            if (!empty($repeat_until)) {
                                echo " until " . date('M d, Y', strtotime($repeat_until));
                            }
                            echo ")";
                        }
                        ?>
                    </div>
                    <div class="notification-types">
                        <?php if ($use_screen): ?>
                            <span class="notification-icon" title="Screen Notification">
                                <span class="dashicons dashicons-desktop"></span>
                            </span>
                        <?php endif; ?>
                        
                        <?php if ($email_count > 0): ?>
                            <span class="notification-icon" title="<?php echo $email_count; ?> Email Recipients">
                                <span class="dashicons dashicons-email"></span>
                                <?php if ($email_count > 1): ?>
                                <span class="count"><?php echo $email_count; ?></span>
                                <?php endif; ?>
                            </span>
                        <?php endif; ?>
                        
                        <?php if ($phone_count > 0): ?>
                            <span class="notification-icon" title="<?php echo $phone_count; ?> SMS Recipients">
                                <span class="dashicons dashicons-phone"></span>
                                <?php if ($phone_count > 1): ?>
                                <span class="count"><?php echo $phone_count; ?></span>
                                <?php endif; ?>
                            </span>
                        <?php endif; ?>
                    </div>
                </span>
            <?php endif; ?>
        <?php endforeach; ?>
    </div>
<?php endif; ?>

            <div class="memo-actions">
                <a href="<?php echo home_url('/memre-input/?memo_id=' . $memo['memo_id']); ?>" class="button edit-button">
                    <span class="dashicons dashicons-edit"></span> Edit
                </a>
                <button class="button delete-button delete-memo" data-memo-id="<?php echo $memo['memo_id']; ?>">
                    <span class="dashicons dashicons-trash"></span> Delete
                </button>
            </div>
        </div>
    <?php endwhile; ?>
<?php else: ?>
    <div class="no-memos">
        <p>No memos found. Click "Add New Memo" to create one.</p>
    </div>
<?php endif; ?>
        </div>
    </div>

    <style>
    .container {
        max-width: 800px;
        margin: 20px auto;
        padding: 0 20px;
    }

    .list-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 20px;
    }

    .add-new-button {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        background: #2196F3;
        color: white;
        padding: 8px 16px;
        border-radius: 4px;
        text-decoration: none;
    }

    .memo-item {
        background: white;
        border: 1px solid #ddd;
        border-radius: 8px;
        padding: 20px;
        margin-bottom: 20px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.05);
    }

    .memo-content {
        margin: 15px 0;
        padding: 10px;
        background: #f9f9f9;
        border-radius: 4px;
        white-space: pre-wrap;
    }

    .memo-attachment {
        margin: 15px 0;
    }

    .attachment-info {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 8px;
        background: #e3f2fd;
        border-radius: 4px;
        margin-bottom: 8px;
    }

    .attachment-preview {
        max-width: 100%;
        max-height: 300px;
        object-fit: contain;
        border-radius: 4px;
    }

    .chip {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 4px 8px;
        border-radius: 16px;
        margin: 2px;
        font-size: 0.85em;
    }

    .category-chip {
        background: #e3f2fd;
        color: #1976d2;
    }

    .label-chip {
        background: #f3e5f5;
        color: #7b1fa2;
    }

.reminder-chip {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    background: #e8f5e9;
    border-radius: 16px;
    margin: 4px;
}

.reminder-info {
    display: flex;
    align-items: center;
    gap: 6px;
    color: #2e7d32;
}

.notification-types {
    display: flex;
    align-items: center;
    gap: 8px;
    padding-left: 8px;
    border-left: 1px solid rgba(0, 0, 0, 0.1);
}

.notification-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: rgba(46, 125, 50, 0.1);
    cursor: help;
}

.notification-icon .dashicons {
    font-size: 14px;
    width: 14px;
    height: 14px;
    color: #2e7d32;
}

.notification-icon:hover {
    background: rgba(46, 125, 50, 0.2);
}

/* Make chips wrap on mobile */
.memo-reminders {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
}

/* Responsive adjustments */
@media (max-width: 768px) {
    .reminder-chip {
        flex-direction: column;
        align-items: flex-start;
    }

    .notification-types {
        border-left: none;
        padding-left: 24px; /* Align with text above */
        padding-top: 4px;
    }
}

    .memo-categories,
    .memo-labels,
    .memo-reminders {
        margin: 10px 0;
    }

    .memo-actions {
        display: flex;
        gap: 8px;
        margin-top: 15px;
        padding-top: 15px;
        border-top: 1px solid #eee;
    }

    .button {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 8px 16px;
        border: none;
        border-radius: 4px;
        cursor: pointer;
        font-size: 14px;
        text-decoration: none;
    }

    .edit-button {
        background: #2196F3;
        color: white;
    }

    .delete-button {
        background: #ff4444;
        color: white;
    }

    .no-memos {
        text-align: center;
        padding: 40px;
        background: #f9f9f9;
        border-radius: 8px;
    }

    @media (max-width: 768px) {
        .container {
            padding: 10px;
        }

        .memo-actions {
            flex-direction: column;
        }

        .button {
            width: 100%;
            justify-content: center;
        }
    }
.search-container {
    display: flex;
    gap: 10px;
    margin-bottom: 20px;
}

.search-input {
    flex: 1;
    padding: 8px 12px;
    border: 1px solid #ddd;
    border-radius: 4px;
    font-size: 16px;
}

.refresh-button {
    padding: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
}
    </style>

    <script>
jQuery(document).ready(function($) {
    var ajaxurl = '<?php echo admin_url('admin-ajax.php'); ?>';
    var deleteNonce = '<?php echo wp_create_nonce('delete_memo_nonce'); ?>';
    
    console.log('AJAX URL:', ajaxurl);
    console.log('Delete nonce:', deleteNonce);
    
    // Test AJAX first
    $.ajax({
        url: ajaxurl,
        type: 'POST',
        data: {
            action: 'test_ajax'
        },
        success: function(response) {
            console.log('AJAX test successful:', response);
        },
        error: function(xhr, status, error) {
            console.error('AJAX test failed:', status, error);
            console.error('Response:', xhr.responseText);
        }
    });
    
    // Search functionality
    let searchTimeout;
    
    $('#memo-search').on('input', function() {
        clearTimeout(searchTimeout);
        const searchTerm = $(this).val().toLowerCase();
        
        searchTimeout = setTimeout(function() {
            $('.memo-item').each(function() {
                const $memo = $(this);
                const content = $memo.text().toLowerCase();
                const isMatch = content.includes(searchTerm);
                $memo.toggle(isMatch);
            });
        }, 300);
    });

    $('#refresh-memos').on('click', function() {
        location.reload();
    });

    // Delete memo functionality
    $('.delete-memo').on('click', function(e) {
        e.preventDefault();
        
        if (!confirm('Are you sure you want to delete this memo? This action cannot be undone.')) {
            return;
        }
        
        var $button = $(this);
        var memoId = $button.data('memo-id');
        var $memoItem = $button.closest('.memo-item');
        
        console.log('Deleting memo ID:', memoId);
        
        $button.prop('disabled', true).text('Deleting...');
        
        $.ajax({
            url: ajaxurl,
            type: 'POST',
            data: {
                action: 'delete_memo',
                memo_id: memoId,
                security: deleteNonce
            },
            success: function(response) {
                console.log('Delete response:', response);
                
                if (response.success) {
                    $memoItem.fadeOut(300, function() {
                        $(this).remove();
                        
                        if ($('.memo-item').length === 0) {
                            $('.memo-list').html('<div class="no-memos"><p>No memos found. Click "Add New MemrE" to create one.</p></div>');
                        }
                    });
                } else {
                    alert('Error deleting memo: ' + (response.data ? response.data.message : 'Unknown error'));
                    $button.prop('disabled', false).html('<span class="dashicons dashicons-trash"></span> Delete');
                }
            },
            error: function(xhr, status, error) {
                console.error('AJAX Error:', status, error);
                console.error('Response:', xhr.responseText);
                
                alert('Network error occurred while deleting memo. Please try again.');
                $button.prop('disabled', false).html('<span class="dashicons dashicons-trash"></span> Delete');
            }
        });
    });
});
</script>

<?php
} catch (Exception $e) {
    echo '<div class="error-message">';
    echo '<p>Error: ' . htmlspecialchars($e->getMessage()) . '</p>';
    echo '</div>';
}

if (isset($custom_db) && $custom_db instanceof mysqli) {
    $custom_db->close();
}

get_footer();
?>