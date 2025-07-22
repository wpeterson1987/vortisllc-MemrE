import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class WebViewLoginScreen extends StatefulWidget {
  final String? initialUrl;
  
  const WebViewLoginScreen({
    Key? key,
    this.initialUrl,
  }) : super(key: key);

  @override
  State<WebViewLoginScreen> createState() => _WebViewLoginScreenState();
}

class _WebViewLoginScreenState extends State<WebViewLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            
            // Check if user is on dashboard/account page (successful login)
            if (url.contains('/dashboard/') || url.contains('/account/')) {
              _checkLoginStatus();
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            // Allow all navigation within your domain
            if (request.url.contains('memre.vortisllc.com')) {
              return NavigationDecision.navigate;
            }
            // Block external navigation
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl ?? 'https://memre.vortisllc.com/login/'));
  }

  Future<void> _checkLoginStatus() async {
    try {
      // Get cookies from the WebView
      final cookies = await _controller.runJavaScriptReturningResult('''
        document.cookie;
      ''');
      
      // Extract user info from the page
      final userInfo = await _controller.runJavaScriptReturningResult('''
        // Try to find user information on the page
        var userData = {};
        
        // Look for user ID in various places
        var userIdElement = document.querySelector('[data-user-id]');
        if (userIdElement) {
          userData.userId = userIdElement.getAttribute('data-user-id');
        }
        
        // Look for username in the page
        var usernameElement = document.querySelector('.user-name, .username, [data-username]');
        if (usernameElement) {
          userData.username = usernameElement.textContent || usernameElement.getAttribute('data-username');
        }
        
        // Check if we're on a logged-in page
        var isLoggedIn = document.querySelector('.dashboard, .account, .logout') !== null;
        userData.isLoggedIn = isLoggedIn;
        
        JSON.stringify(userData);
      ''');

      print('User info from WebView: $userInfo');
      
      if (userInfo.toString().contains('isLoggedIn":true')) {
        setState(() {
          _isLoggedIn = true;
        });
        
        // Return success to parent
        if (mounted) {
          Navigator.of(context).pop({'success': true, 'userInfo': userInfo});
        }
      }
    } catch (e) {
      print('Error checking login status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login to MemrE'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop({'success': false}),
        ),
        actions: [
          if (_isLoggedIn)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () => Navigator.of(context).pop({'success': true}),
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}