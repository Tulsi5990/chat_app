import 'package:chat_app_lattice/pages/LoginPage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:chat_app_lattice/models/FirebaseHelper.dart';
import 'package:chat_app_lattice/models/UserModel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:chat_app_lattice/pages/HomePage.dart';

var uuid = const Uuid();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  User? currentUser = FirebaseAuth.instance.currentUser;
  if(currentUser != null) {
    // Logged In
    UserModel? thisUserModel = await FirebaseHelper.getUserModelById(currentUser.uid);
    if(thisUserModel != null) {
      runApp(MyAppLoggedIn(userModel: thisUserModel, firebaseUser: currentUser));
    }
    else {
      runApp( const MyApp());
    }
  }
  else {
    // Not logged in
    runApp(const MyApp());
  }
}


// Not Logged In
class MyApp extends StatelessWidget {
  const MyApp({ Key? key }) : super(key: key);

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

