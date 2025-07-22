<?php
/*
Template Name: Memre Input
*/

// Enable error reporting
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Basic setup
wp_enqueue_script('jquery');
wp_enqueue_style('dashicons');

// Start output buffering to catch any errors
ob_start();

get_header();

try {
    // Get current user ID first
    $current_user_id = get_current_user_id();
    error_log('Current user ID: ' . $current_user_id);

    if (!$current_user_id) {
        throw new Exception('User not logged in');
    }

    // Create nonce
    $nonce = wp_create_nonce('save_memo_action');
    
    // Get memo_id from URL
    $memo_id = isset($_GET['memo_id']) ? intval($_GET['memo_id']) : 0;
    error_log('Memo ID: ' . $memo_id);

    // Test database connection
    $custom_db = new mysqli(
        CUSTOM_DB_HOST,
        CUSTOM_DB_USER,
        CUSTOM_DB_PASSWORD,
        CUSTOM_DB_NAME
    );

    if ($custom_db->connect_error) {
        throw new Exception("Database connection failed: " . $custom_db->connect_error);
    }

    error_log('Database connection successful');

 // Initialize memo data and attachment data
    $memo_data = null;
    $attachment_data = null;

    // Get existing memo data if editing
    if ($memo_id > 0) {
		error_log('Fetching memo data for ID: ' . $memo_id);
		
        $memo_table = "user_{$current_user_id}_memo";
        $stmt = $custom_db->prepare("SELECT * FROM {$memo_table} WHERE memo_id = ?");
        if (!$stmt) {
            throw new Exception("Prepare failed: " . $custom_db->error);
        }
        
        $stmt->bind_param('i', $memo_id);
		if (!$stmt->execute()) {
            throw new Exception("Execute failed: " . $stmt->error);
        }
		
//        $stmt->execute();
        $result = $stmt->get_result();
        $memo_data = $result->fetch_assoc();
        
        if (!$memo_data) {
            throw new Exception("Memo not found");
        }
    }
    ?>
    <div class="container">
        <h1><?php echo $memo_id ? 'Edit MemrE' : 'New MemrE'; ?></h1>
        
        <form id="memo-form" method="post" enctype="multipart/form-data">
            <input type="hidden" name="action" value="save_memo">
            <input type="hidden" name="nonce" value="<?php echo $nonce; ?>">
            
            <?php if ($memo_id): ?>
                <input type="hidden" name="memo_id" value="<?php echo $memo_id; ?>">
            <?php endif; ?>
            
            <div class="form-group">
                <label for="memo-desc">Description</label>
                <input type="text" id="memo-desc" name="memo_desc" required 
                       value="<?php echo $memo_data ? htmlspecialchars($memo_data['memo_desc']) : ''; ?>">
            </div>

            <div class="form-group">
                <label for="memo-content">Content</label>
                <textarea id="memo-content" name="memo" required><?php 
                    echo $memo_data ? htmlspecialchars($memo_data['memo']) : ''; 
                ?></textarea>
            </div>

<!-- File Attachment Section -->
<div class="form-group">
    <label>Add/Edit Attachment</label>
    <div class="attachment-section">
        <div class="content-type-buttons">
            <button type="button" class="content-type-btn" data-type="image">
                <span class="dashicons dashicons-format-image"></span> Image
            </button>
            <button type="button" class="content-type-btn" data-type="document">
                <span class="dashicons dashicons-media-document"></span> Document
            </button>
            <button type="button" class="content-type-btn" data-type="video">
                <span class="dashicons dashicons-video-alt3"></span> Video
            </button>
        </div>
        
        <div id="file-input" class="content-area" style="display: none;">
            <input type="file" id="file-upload" name="attachment">
			
            <div id="file-preview" class="preview-area">
    			<?php
    			if ($memo_id > 0) {
        			$attachment_query = "SELECT file_type, file_name, file_data FROM user_{$current_user_id}_attachment WHERE memo_id = ?";
        			$stmt = $custom_db->prepare($attachment_query);
        			if ($stmt) {
           			 $stmt->bind_param('i', $memo_id);
            		 $stmt->execute();
            		 $result = $stmt->get_result();
            		 $attachment = $result->fetch_assoc();
            
            	if ($attachment) {
                	echo '<div class="current-file-info">';
                	echo '<strong>Current file:</strong> ';
                	echo '<a href="' . admin_url('admin-ajax.php') . '?action=download_attachment&memo_id=' . $memo_id . '&nonce=' . wp_create_nonce('download_attachment') . '" ';
                	echo 'class="file-download-link">';
                	echo htmlspecialchars($attachment['file_name']);
                	echo '</a>';
                	echo '</div>';
                
                if ($attachment['file_type'] === 'image') {
                    	$img_src = 'data:image/jpeg;base64,' . base64_encode($attachment['file_data']);
                    echo "<img src='{$img_src}' alt='Current Image' class='preview-image'>";
                	} elseif ($attachment['file_type'] === 'document') {
                    	echo '<div class="document-preview">';
                    	echo '<span class="dashicons dashicons-media-document"></span>';
                    	echo 'Click filename above to download';
                    	echo '</div>';
                	} elseif ($attachment['file_type'] === 'video') {
                    	echo '<div class="video-preview">';
                    	echo '<span class="dashicons dashicons-video-alt3"></span>';
                    	echo 'Click filename above to download';
                    	echo '</div>';
                	}
            	}
        	}
    	}
    	?>
	</div>
        </div>
    </div>
</div>
			
	
<!-- Reminders Section -->
<div class="form-group">
    <label>Reminders</label>
    <div class="reminder-container">
        <div class="reminders">
            <?php
            // Get existing reminders if editing
            if ($memo_id > 0) {
               $reminder_query = "SELECT r.reminder_time, r.repeat_type, r.repeat_until,
              r.use_screen_notification, r.email_address, r.phone_number,
              r.email_addresses, r.phone_numbers
       FROM user_{$current_user_id}_reminder r
       JOIN user_{$current_user_id}_memo_reminder mr 
       ON r.reminder_id = mr.reminder_id
       WHERE mr.memo_id = ?";
                $stmt = $custom_db->prepare($reminder_query);
                $stmt->bind_param('i', $memo_id);
                $stmt->execute();
                $reminder_result = $stmt->get_result();
                
                while ($row = $reminder_result->fetch_assoc()) {
    // Keep track of reminder index
    $reminder_index = isset($reminder_index) ? $reminder_index + 1 : 0;
                    // Display each existing reminder without using <template> tags
                    ?>
                    <div class="reminder-input-group">
                        <input type="datetime-local" name="reminders[]" 
                               value="<?php echo date('Y-m-d\TH:i', strtotime($row['reminder_time'])); ?>" required>
                        <select name="repeat_type[]">
                            <option value="">No Repeat</option>
                            <option value="daily" <?php echo $row['repeat_type'] === 'daily' ? 'selected' : ''; ?>>Daily</option>
                            <option value="weekly" <?php echo $row['repeat_type'] === 'weekly' ? 'selected' : ''; ?>>Weekly</option>
                            <option value="monthly" <?php echo $row['repeat_type'] === 'monthly' ? 'selected' : ''; ?>>Monthly</option>
                            <option value="yearly" <?php echo $row['repeat_type'] === 'yearly' ? 'selected' : ''; ?>>Yearly</option>
                        </select>
                        <input type="date" name="repeat_until[]" 
       value="<?php 
          // Only output a date if it's valid
          echo ($row['repeat_until'] && $row['repeat_until'] != '0000-00-00' && strtotime($row['repeat_until']) > 0) 
              ? date('Y-m-d', strtotime($row['repeat_until'])) 
              : ''; 
       ?>"
       <?php echo $row['repeat_type'] ? '' : 'style="display:none;"'; ?>>
                        
                        <div class="notification-options">
    <label class="checkbox-label notification-checkbox">
        <input type="checkbox" name="use_screen_notification[]" value="1"
               <?php echo $row['use_screen_notification'] ? 'checked' : ''; ?>>
        <span class="dashicons dashicons-desktop"></span> Screen
    </label>
    
    <!-- Email recipients -->
    <div class="multi-recipient-section">
        <h4>Email Recipients</h4>
        <div class="email-recipients">
            <?php
            // Get all email addresses
            $allEmails = [];
            if (!empty($row['email_address'])) {
                $allEmails[] = $row['email_address'];
            }
            if (!empty($row['email_addresses'])) {
                $additionalEmails = explode('|', $row['email_addresses']);
                foreach ($additionalEmails as $email) {
                    if (!empty($email) && !in_array($email, $allEmails)) {
                        $allEmails[] = $email;
                    }
                }
            }
            
            // Display each email
            foreach ($allEmails as $index => $email): 
            ?>
            <div class="recipient-input-group">
                <span class="dashicons dashicons-email"></span>
                <input type="email" name="email_addresses[<?php echo $reminder_index; ?>][]" 
                       value="<?php echo htmlspecialchars($email); ?>"
                       placeholder="Email for notification" class="notification-input">
                <?php if ($index === 0): ?>
                    <button type="button" class="add-recipient" data-type="email">
                        <span class="dashicons dashicons-plus-alt2"></span>
                    </button>
                <?php else: ?>
                    <button type="button" class="remove-recipient">
                        <span class="dashicons dashicons-minus"></span>
                    </button>
                <?php endif; ?>
            </div>
            <?php endforeach; ?>
            
            <?php if (empty($allEmails)): ?>
            <div class="recipient-input-group">
                <span class="dashicons dashicons-email"></span>
                <input type="email" name="email_addresses[<?php echo $reminder_index; ?>][]" 
                       placeholder="Email for notification" class="notification-input">
                <button type="button" class="add-recipient" data-type="email">
                    <span class="dashicons dashicons-plus-alt2"></span>
                </button>
            </div>
            <?php endif; ?>
        </div>
    </div>
    
    <!-- SMS recipients -->
    <div class="multi-recipient-section">
        <h4>SMS Recipients</h4>
        <div class="sms-recipients">
            <?php
            // Get all phone numbers
            $allPhones = [];
            if (!empty($row['phone_number'])) {
                $allPhones[] = $row['phone_number'];
            }
            if (!empty($row['phone_numbers'])) {
                $additionalPhones = explode('|', $row['phone_numbers']);
                foreach ($additionalPhones as $phone) {
                    if (!empty($phone) && !in_array($phone, $allPhones)) {
                        $allPhones[] = $phone;
                    }
                }
            }
            
            // Display each phone
            foreach ($allPhones as $index => $phone): 
            ?>
            <div class="recipient-input-group">
                <span class="dashicons dashicons-phone"></span>
                <input type="tel" name="phone_numbers[<?php echo $reminder_index; ?>][]" 
                       value="<?php echo htmlspecialchars($phone); ?>"
                       placeholder="Phone for SMS" class="notification-input">
                <?php if ($index === 0): ?>
                    <button type="button" class="add-recipient" data-type="sms">
                        <span class="dashicons dashicons-plus-alt2"></span>
                    </button>
                <?php else: ?>
                    <button type="button" class="remove-recipient">
                        <span class="dashicons dashicons-minus"></span>
                    </button>
                <?php endif; ?>
            </div>
            <?php endforeach; ?>
            
            <?php if (empty($allPhones)): ?>
            <div class="recipient-input-group">
                <span class="dashicons dashicons-phone"></span>
                <input type="tel" name="phone_numbers[<?php echo $reminder_index; ?>][]" 
                       placeholder="Phone for SMS" class="notification-input">
                <button type="button" class="add-recipient" data-type="sms">
                    <span class="dashicons dashicons-plus-alt2"></span>
                </button>
            </div>
            <?php endif; ?>
        </div>
    </div>
</div>
                        
                        <button type="button" class="remove-reminder">
                            <span class="dashicons dashicons-trash"></span>
                        </button>
                    </div>
                    <?php
                }
            }
            ?>
        </div>

<!-- Template for new reminders -->
<template id="reminder-template">
    <div class="reminder-input-group">
        <input type="datetime-local" name="reminders[]" required />
        <select name="repeat_type[]">
            <option value="">No Repeat</option>
            <option value="daily">Daily</option>
            <option value="weekly">Weekly</option>
            <option value="monthly">Monthly</option>
            <option value="yearly">Yearly</option>
        </select>
        <input type="date" name="repeat_until[]" style="display:none;">
        
        <div class="notification-options">
            <label class="checkbox-label notification-checkbox">
                <input type="checkbox" name="use_screen_notification[]" value="1" checked>
                <span class="dashicons dashicons-desktop"></span> Screen
            </label>
            
            <!-- Email recipients -->
            <div class="email-recipients">
                <div class="recipient-input-group">
                    <span class="dashicons dashicons-email"></span>
                    <input type="email" name="email_address[]" placeholder="Email for notification" class="notification-input">
                    <button type="button" class="add-email-recipient">
                        <span class="dashicons dashicons-plus-alt2"></span>
                    </button>
                </div>
            </div>
            
            <!-- SMS recipients -->
            <div class="sms-recipients">
                <div class="recipient-input-group">
                    <span class="dashicons dashicons-phone"></span>
                    <input type="tel" name="phone_number[]" placeholder="Phone for SMS" class="notification-input">
                    <button type="button" class="add-sms-recipient">
                        <span class="dashicons dashicons-plus-alt2"></span>
                    </button>
                </div>
            </div>
        </div>
        
        <button type="button" class="remove-reminder">
            <span class="dashicons dashicons-trash"></span>
        </button>
    </div>
</template>

        <button type="button" class="button" id="add-reminder">
            <span class="dashicons dashicons-plus-alt2"></span> Add/Edit Reminder
        </button>
    </div>
</div>
			
            <button type="submit">Save MemrE</button>
        </form>
    </div>

<style>
.form-group {
    margin-bottom: 20px;
}

.form-group label {
    display: block;
    margin-bottom: 8px;
    font-weight: bold;
}

.form-input {
    width: 100%;
    padding: 8px;
    border: 1px solid #ddd;
    border-radius: 4px;
}

.categories-container,
.labels-container {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 8px;
}

.multi-recipient-section {
    margin-top: 10px;
    border-top: 1px solid #eee;
    padding-top: 10px;
}

.multi-recipient-section h4 {
    font-size: 14px;
    margin: 0 0 8px 0;
    color: #555;
}

.recipient-input-group {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 5px;
}

.remove-recipient, .add-email-recipient, .add-sms-recipient {
    background: none;
    border: none;
    cursor: pointer;
    padding: 2px;
    display: flex;
    align-items: center;
    justify-content: center;
}

.add-email-recipient, .add-sms-recipient {
    color: #2196F3;
}

.remove-recipient {
    color: #ff4444;
}

.email-recipients, .sms-recipients {
    margin-top: 8px;
}

.count {
    font-size: 10px;
    background: rgba(255, 255, 255, 0.8);
    border-radius: 50%;
    width: 16px;
    height: 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    position: absolute;
    top: -5px;
    right: -5px;
    color: #2e7d32;
}

.notification-icon {
    position: relative;
}
	
.checkbox-label {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 4px 8px;
    background: #f5f5f5;
    border: 1px solid #ddd;
    border-radius: 16px;
    cursor: pointer;
	background: #2196F3;
        color: white;
}

.checkbox-label:hover {
    background: #e0e0e0;
}

.add-button {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 8px 16px;
    background: #f0f0f0;
    border: 1px solid #ddd;
    border-radius: 4px;
    cursor: pointer;
}

.add-button:hover {
    background: #e0e0e0;
}
.reminder-container {
    margin: 20px 0;
}
.reminder-inputs {
    display: flex;
    gap: 8px;
    align-items: center;
}
.reminder-input-group {
    margin-bottom: 10px;
    display: flex;
    gap: 10px;
    align-items: center;
}

input[name="repeat_until[]"] {
    display: none;
}

.remove-reminder {
    padding: 5px 10px;
    color: white;
    background-color: #dc3545;
    border: none;
    border-radius: 4px;
    cursor: pointer;
}

.remove-reminder:hover {
    background-color: #c82333;
}

.reminder-inputs input[type="datetime-local"] {
    flex: 1;
    padding: 8px;
    border: 1px solid #ddd;
    border-radius: 4px;
}
	#add-reminder {
    margin-top: 10px;
}
.notification-options {
    display: flex;
    gap: 12px;
    align-items: center;
    margin-top: 8px;
    padding: 8px;
    background: #f5f5f5;
    border-radius: 4px;
}

.notification-options label {
    display: flex;
    align-items: center;
    gap: 4px;
    white-space: nowrap;
}

.notification-input {
    width: 180px;
    padding: 6px 12px;
    border: 1px solid #ddd;
    border-radius: 4px;
    font-size: 14px;
}

.notification-input:focus {
    border-color: #2196F3;
    outline: none;
    box-shadow: 0 0 0 2px rgba(33, 150, 243, 0.25);
}

.notification-options .dashicons {
    color: #6c757d;
    width: 20px;
    height: 20px;
    font-size: 20px;
}
	@media (max-width: 768px) {
    .reminder-input-group {
        padding: 10px;
    }
    
    .notification-options {
        flex-direction: column;
    }
    
    .notification-input-group {
        width: 100%;
    }
}

@media (max-width: 768px) {
    .notification-options {
        flex-direction: column;
        align-items: stretch;
    }
    
    .notification-input {
        width: 100%;
    }
}
.attachment-section {
    border: 1px solid #ddd;
    padding: 15px;
    border-radius: 4px;
    margin-top: 10px;
}

.content-type-buttons {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    margin-bottom: 16px;
}

.content-type-btn {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 8px 16px;
    border: 1px solid #ddd;
    border-radius: 4px;
    background: white;
    cursor: pointer;
    transition: all 0.2s ease;
}

.content-type-btn:hover {
    background: #f0f0f0;
}

.content-type-btn.active {
    background: #e6f3ff;
    border-color: #2196F3;
    color: #2196F3;
}

.content-area {
    margin-top: 15px;
}

.preview-area {
    margin-top: 15px;
    padding: 15px;
    border: 1px dashed #ddd;
    border-radius: 4px;
    background: #f9f9f9;
}

.preview-image {
    display: block;
    max-width: 100%;
    max-height: 300px;
    object-fit: contain;
    margin: 10px auto;
    border-radius: 4px;
    border: 1px solid #ddd;
    background: white;
}
.file-download-link {
    color: #2196F3;
    text-decoration: none;
    padding: 2px 4px;
    border-radius: 3px;
    transition: background-color 0.2s;
}

.file-download-link:hover {
    background-color: #e3f2fd;
    text-decoration: underline;
}

.document-preview,
.video-preview {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px;
    background: #f5f5f5;
    border-radius: 4px;
    margin-top: 10px;
    color: #666;
}

.current-file-info {
    background: #e3f2fd;
    padding: 8px;
    border-radius: 4px;
    margin-bottom: 10px;
}

.file-requirements {
    font-size: 0.9em;
    color: #666;
    margin: 8px 0;
}	
/* Button Styles */
.button,
.add-button,
.content-type-btn,
button[type="submit"] {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 8px 16px;
    background: #2196F3;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    text-decoration: none;
    font-size: 14px;
}

.button:hover,
.add-button:hover,
.content-type-btn:hover,
button[type="submit"]:hover {
    background: #1976D2;
}

/* Active state for content type buttons */
.content-type-btn.active {
	background: #ebeced;
    color: white;
}

/* Remove reminder button specific style */
.remove-reminder {
    background: #ff4444;
    color: white;
    border: none;
    border-radius: 4px;
    padding: 8px;
    cursor: pointer;
}

.remove-reminder:hover {
    background: #cc0000;
}

/* Save button specific style - make it more prominent */
button[type="submit"] {
    width: 100%;
    padding: 12px;
    font-size: 16px;
    margin-top: 20px;
}

/* Add icons to buttons styling */
.button .dashicons,
.add-button .dashicons,
.content-type-btn .dashicons,
.remove-reminder .dashicons {
    width: 20px;
    height: 20px;
    font-size: 20px;
}
</style>



<script type="text/javascript">
jQuery(document).ready(function($) {
    console.log('Form initialized');
    var submitting = false;

    // Content type buttons
    $('.content-type-btn').on('click', function(e) {
        e.preventDefault();
        console.log('Content type button clicked');
        
        $('.content-type-btn').removeClass('active');
        $(this).addClass('active');
        
        const type = $(this).data('type');
        const acceptTypes = {
            'image': 'image/*',
            'document': '.pdf,.doc,.docx',
            'video': 'video/*'
        };
        
        $('#file-input').show();
        $('#file-upload').attr('accept', acceptTypes[type]).click();
    });

    // File upload preview
    $('#file-upload').on('change', function(e) {
        const file = this.files[0];
        if (!file) return;
        
        const reader = new FileReader();
        reader.onload = function(e) {
            let previewHtml = '<div class="current-file-info">' +
                             '<strong>Selected file:</strong> ' + file.name +
                             '</div>';
            
            if (file.type.startsWith('image/')) {
                previewHtml += '<img src="' + e.target.result + '" class="preview-image">';
            }
            
            $('#file-preview').html(previewHtml);
        };
        reader.readAsDataURL(file);
    });

    // Functions for validation
    function isValidEmail(email) {
        return email === '' || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
    }
    
    function isValidPhone(phone) {
        return phone === '' || /^\+?[\d\s-]{10,}$/.test(phone);
    }
    
    // Update all recipient field names with correct reminder index
    function updateRecipientIndices() {
        $('.reminders .reminder-input-group').each(function(reminderIndex) {
            // Update email_addresses indices
            $(this).find('.email-recipients input[type="email"]').each(function() {
                const newName = 'email_addresses[' + reminderIndex + '][]';
                $(this).attr('name', newName);
            });
            
            // Update phone_numbers indices
            $(this).find('.sms-recipients input[type="tel"]').each(function() {
                const newName = 'phone_numbers[' + reminderIndex + '][]';
                $(this).attr('name', newName);
            });
        });
    }

    // Handle repeat type changes
    function handleRepeatTypeChange($select) {
        const $repeatUntil = $select.closest('.reminder-input-group').find('input[name="repeat_until[]"]');
        if ($select.val()) {
            $repeatUntil.show();
        } else {
            $repeatUntil.hide().val('');
        }
    }

    // Add Reminder functionality - FIXED SINGLE VERSION
    $('#add-reminder').on('click', function() {
        console.log('Add reminder clicked');
        const template = document.getElementById('reminder-template');
        const clone = template.content.cloneNode(true);
        $('.reminders').append(clone);
        
        // Initialize the repeat type handler for the new reminder
        const newReminder = $('.reminders .reminder-input-group:last');
        const newRepeatSelect = newReminder.find('select[name="repeat_type[]"]');
        handleRepeatTypeChange(newRepeatSelect);
        
        // Update indices
        updateRecipientIndices();
    });

    // Event handlers for repeat type changes
    $(document).on('change', 'select[name="repeat_type[]"]', function() {
        handleRepeatTypeChange($(this));
    });

    // Remove Reminder functionality
    $(document).on('click', '.remove-reminder', function() {
        console.log('Remove reminder clicked');
        $(this).closest('.reminder-input-group').remove();
        
        // Update indices after removing
        updateRecipientIndices();
    });

    // Add email recipient
    $(document).on('click', '.add-email-recipient', function() {
        const container = $(this).closest('.email-recipients');
        const index = $(this).closest('.reminder-input-group').index();
        
        const newInput = $('<div class="recipient-input-group">' +
            '<span class="dashicons dashicons-email"></span>' +
            '<input type="email" name="email_addresses[' + index + '][]" placeholder="Email for notification" class="notification-input">' +
            '<button type="button" class="remove-recipient"><span class="dashicons dashicons-minus"></span></button>' +
            '</div>');
        
        container.append(newInput);
    });

    // Add SMS recipient
    $(document).on('click', '.add-sms-recipient', function() {
        const container = $(this).closest('.sms-recipients');
        const index = $(this).closest('.reminder-input-group').index();
        
        const newInput = $('<div class="recipient-input-group">' +
            '<span class="dashicons dashicons-phone"></span>' +
            '<input type="tel" name="phone_numbers[' + index + '][]" placeholder="Phone for SMS" class="notification-input">' +
            '<button type="button" class="remove-recipient"><span class="dashicons dashicons-minus"></span></button>' +
            '</div>');
        
        container.append(newInput);
    });

    // Add recipient (old style)
    $(document).on('click', '.add-recipient', function() {
        const type = $(this).data('type');
        const container = type === 'email' ? $(this).closest('.email-recipients') : $(this).closest('.sms-recipients');
        const reminderIndex = $(this).closest('.reminder-input-group').index();
        
        const newField = `
            <div class="recipient-input-group">
                <span class="dashicons dashicons-${type === 'email' ? 'email' : 'phone'}"></span>
                <input type="${type === 'email' ? 'email' : 'tel'}" 
                       name="${type === 'email' ? 'email_addresses' : 'phone_numbers'}[${reminderIndex}][]" 
                       placeholder="${type === 'email' ? 'Email' : 'Phone'} for notification" 
                       class="notification-input">
                <button type="button" class="remove-recipient">
                    <span class="dashicons dashicons-minus"></span>
                </button>
            </div>
        `;
        container.append(newField);
    });

    // Remove recipient
    $(document).on('click', '.remove-recipient', function() {
        $(this).closest('.recipient-input-group').remove();
    });

    // Handle email validation
    $(document).on('change', 'input[type="email"]', function() {
        const email = $(this).val() || '';
        if (email && !isValidEmail(email)) {
            alert('Please enter a valid email address');
            $(this).val('').focus();
        }
    });

    // Handle phone validation
    $(document).on('change', 'input[type="tel"]', function() {
        const phone = $(this).val() || '';
        if (phone && !isValidPhone(phone)) {
            alert('Please enter a valid phone number');
            $(this).val('').focus();
        }
    });

    // Form submission
    $('#memo-form').on('submit', function(e) {
        e.preventDefault();
        console.log('Form submit triggered');
        
        if (submitting) return;
        
        // Basic validation
        if ($('#memo-desc').val().trim() === '') {
            alert('Please enter a description');
            $('#memo-desc').focus();
            return;
        }
        
        console.log('Form validation passed, submitting...');
        submitting = true;
        
        var formData = new FormData(this);
        formData.append('action', 'save_memo');
        
        // Log form data for debugging
        for (var pair of formData.entries()) {
            console.log(pair[0] + ': ' + pair[1]);
        }
        
        $.ajax({
            url: ajaxurl,
            type: 'POST',
            data: formData,
            processData: false,
            contentType: false,
            success: function(response) {
                console.log('Form submission response:', response);
                if (response.success) {
                    alert('MemrE saved successfully!');
                    window.location.href = memoListUrl;
                } else {
                    alert('Error: ' + (response.data ? response.data.message : 'Unknown error'));
                    submitting = false;
                }
            },
            error: function(xhr, status, error) {
                console.error('Form submission error:', error);
                console.error('Response text:', xhr.responseText);
                alert('Error saving memre: ' + error);
                submitting = false;
            }
        });
    });

    // Initialize existing reminders
    $('select[name="repeat_type[]"]').each(function() {
        handleRepeatTypeChange($(this));
    });
    
    // Initialize recipient indices
    updateRecipientIndices();
});

var ajaxurl = '<?php echo admin_url('admin-ajax.php'); ?>';
var memoListUrl = '<?php echo home_url("/memre-list/"); ?>';
</script>

    <?php
} catch (Exception $e) {
    error_log('Error in memo form: ' . $e->getMessage());
    echo '<div class="error">';
    echo 'Error: ' . htmlspecialchars($e->getMessage());
    echo '</div>';
}

// Get any output from the buffer
$output = ob_get_clean();
if (error_get_last()) {
    error_log('PHP Error: ' . print_r(error_get_last(), true));
}

// Output the page content
echo $output;

if (isset($custom_db) && $custom_db instanceof mysqli) {
    $custom_db->close();
}

get_footer();
?>