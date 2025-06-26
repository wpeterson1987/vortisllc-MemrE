class Config {
  // ClickSend API credentials (for SMS only)
  static const String clickSendUsername = 'troy.thurgood1@gmail.com';
  static const String clickSendApiKey = '2C365E22-8A7B-CD1A-2148-3D02975B6CB5';
  static const String clickSendSenderId = '18339454695';

  // SMTP Email configuration
  static const String smtpHost =
      'mail.valorwebs.com'; // Replace with your SMTP host
  static const int smtpPort = 587; // Common port for TLS
  static const String smtpUsername =
      'memos@valorwebs.com'; // Replace with your email
  static const String smtpPassword =
      r'S@f3ty123$'; // Replace with your password
  static const bool smtpUseSSL = false; // Use TLS instead for port 587
  static const String emailSenderName =
      'MemrE App'; // The display name for emails

  static const bool isProduction = false;
}
