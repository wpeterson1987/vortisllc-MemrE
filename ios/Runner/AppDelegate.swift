import UIKit
import Flutter
import MessageUI

@main
@objc class AppDelegate: FlutterAppDelegate, MFMessageComposeViewControllerDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Set up SMS channel
        setupSMSChannel()
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func setupSMSChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return
        }
        
        let smsChannel = FlutterMethodChannel(
            name: "com.vortisllc.memre/sms",
            binaryMessenger: controller.binaryMessenger
        )
        
        smsChannel.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "canSendSMS":
                result(MFMessageComposeViewController.canSendText())
                
            case "sendSMS":
                guard let args = call.arguments as? [String: Any],
                      let recipients = args["recipients"] as? [String],
                      let message = args["message"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
                    return
                }
                
                self?.sendSMS(recipients: recipients, message: message, result: result)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    private func sendSMS(recipients: [String], message: String, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if MFMessageComposeViewController.canSendText() {
                let messageController = MFMessageComposeViewController()
                messageController.messageComposeDelegate = self
                messageController.recipients = recipients
                messageController.body = message
                
                if let viewController = self.window?.rootViewController {
                    viewController.present(messageController, animated: true)
                    result(true)
                } else {
                    result(FlutterError(code: "NO_CONTROLLER", message: "No view controller available", details: nil))
                }
            } else {
                result(FlutterError(code: "SMS_NOT_AVAILABLE", message: "SMS not available on this device", details: nil))
            }
        }
    }
    
    // MARK: - MFMessageComposeViewControllerDelegate
    
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true, completion: nil)
        
        switch result {
        case .cancelled:
            print("SMS cancelled")
        case .sent:
            print("SMS sent successfully")
        case .failed:
            print("SMS failed to send")
        @unknown default:
            print("SMS unknown result")
        }
    }
}