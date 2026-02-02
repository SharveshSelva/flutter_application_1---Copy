  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:flutter/foundation.dart';
  import 'package:shared_preferences/shared_preferences.dart';

  class AuthService {
    final FirebaseAuth _auth = FirebaseAuth.instance;
    
    // Initialize shared preferences
    Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

    // Sign in with email and password
    Future<UserCredential> signInWithEmailPassword(String email, String password) async {
      try {
        debugPrint('Attempting to sign in with: $email');
        final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        
        debugPrint('Sign in successful for: ${userCredential.user?.email}');
        
        // Store the user's email locally
        final SharedPreferences prefs = await _prefs;
        await prefs.setString('user_email', email);
         
        return userCredential;
      } catch (e) {
        debugPrint('Sign in error: $e');
        rethrow;
      }
    }

    // Create new account
    Future<UserCredential> createAccount(String email, String password) async {
      try {
        debugPrint('Creating account for: $email');
        final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        
        debugPrint('Account created successfully for: ${userCredential.user?.email}');
        
        // Store the user's email locally
        final SharedPreferences prefs = await _prefs;
        await prefs.setString('user_email', email);
        
        return userCredential;
      } catch (e) {
        debugPrint('Create account error: $e');
        rethrow;
      }
    }

    // Sign out
    Future<void> signOut() async {
      try {
        await _auth.signOut();
        // Clear stored email
        final SharedPreferences prefs = await _prefs;
        await prefs.remove('user_email');
      } catch (e) {
        debugPrint('Sign out error: $e');
        rethrow;
      }
    }

    // Get current user
    User? get currentUser => _auth.currentUser;

    // Listen to auth state changes
    Stream<User?> get authStateChanges => _auth.authStateChanges();

    // Check if user is logged in
    Future<bool> isLoggedIn() async {
      return _auth.currentUser != null;
    }

    // Get stored user email
    Future<String?> getStoredEmail() async {
      final SharedPreferences prefs = await _prefs;
      return prefs.getString('user_email');
    }

    // Test Firebase connectivity
    Future<bool> testFirebaseConnection() async {
      try {
        debugPrint('Testing Firebase connection...');
        final User? user = _auth.currentUser;
        debugPrint('Firebase Auth instance: ${_auth.app.name}');
        debugPrint('Current user: ${user?.email ?? "No user signed in"}');
        return true;
      } catch (e) {
        debugPrint('Firebase connection test failed: $e');
        return false;
      }
    }
  }