import 'package:chat_app_lattice/pages/LoginPage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:chat_app_lattice/models/FirebaseHelper.dart';
import 'package:chat_app_lattice/models/UserModel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:chat_app_lattice/pages/HomePage.dart';
import 'package:chat_app_lattice/encryption/lwe.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';

var uuid = const Uuid();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyCwRUG8HBKqwmECWJNV24yO438G27YVedE",
      projectId: "chattingapp-586b0",
      storageBucket: "chattingapp-586b0.appspot.com",
      messagingSenderId: "206222612386",
      appId: "1:206222612386:android:e7de7e8f1ddbde9cd044fb",
    ),
  );

  // Initialize FCM and handle notifications
  await setupFCM();

  KeyManagement keyManagement = KeyManagement();
  await keyManagement.generateAndStoreKeys();

  User? currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    // Logged In
    UserModel? thisUserModel = await FirebaseHelper.getUserModelById(currentUser.uid);
    if (thisUserModel != null) {
      runApp(MyAppLoggedIn(userModel: thisUserModel, firebaseUser: currentUser));
    } else {
      runApp(const MyApp());
    }
  } else {
    // Not logged in
    runApp(const MyApp());
  }
}

Future<void> setupFCM() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  // Get the FCM registration token
  String? token = await messaging.getToken();
  print("FCM Registration Token: $token");

  // Request notification permissions for iOS
  if (Platform.isIOS) {
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      print('User granted provisional permission');
    } else {
      print('User declined or has not accepted permission');
    }
  }

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Received a message while in the foreground!');
    if (message.notification != null) {
      print('Message notification: ${message.notification!.title}, ${message.notification!.body}');
    }
  });

  // Handle background and terminated messages
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('Message clicked!');
    // Handle the interaction when the app is opened from a notification
  });

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

// Not Logged In
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}

// Already Logged In
class MyAppLoggedIn extends StatelessWidget {
  final UserModel userModel;
  final User firebaseUser;

  const MyAppLoggedIn({Key? key, required this.userModel, required this.firebaseUser}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(userModel: userModel, firebaseUser: firebaseUser),
    );
  }
}
