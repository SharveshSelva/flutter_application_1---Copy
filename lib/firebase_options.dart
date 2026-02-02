import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.windows:
        return windows;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA0Y5nXHO1ER8thDyqUn19j25UGFzyRPuY',
    appId: '1:848553401987:web:67aa07b0e4df74706bc5b6',
    messagingSenderId: '848553401987',
    projectId: 'memora-be657',
    authDomain: 'memora-be657.firebaseapp.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA0Y5nXHO1ER8thDyqUn19j25UGFzyRPuY',
    appId: '1:848553401987:android:67aa07b0e4df74706bc5b6',
    messagingSenderId: '848553401987',
    projectId: 'memora-be657',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA0Y5nXHO1ER8thDyqUn19j25UGFzyRPuY',
    appId: '1:848553401987:ios:67aa07b0e4df74706bc5b6',
    messagingSenderId: '848553401987',
    projectId: 'memora-be657',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyA0Y5nXHO1ER8thDyqUn19j25UGFzyRPuY',
    appId: '1:848553401987:windows:67aa07b0e4df74706bc5b6',
    messagingSenderId: '848553401987',
    projectId: 'memora-be657',
    authDomain: 'memora-be657.firebaseapp.com',
  );
}
