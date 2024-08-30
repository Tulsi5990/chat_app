import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chat_app_lattice/models/UIHelper.dart';
import 'package:chat_app_lattice/models/UserModel.dart';
import 'package:chat_app_lattice/pages/CompleteProfile.dart';
import 'package:chat_app_lattice/encryption/lwe.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({ Key? key }) : super(key: key);

  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final LWE lwe = LWE(); // Initialize the lwe instance
  final KeyManagement keyManagement = KeyManagement();
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController cPasswordController = TextEditingController();

  void checkValues() {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();
    String cPassword = cPasswordController.text.trim();

    if (email == "" || password == "" || cPassword == "") {
      UIHelper.showAlertDialog(
          context, "Incomplete Data", "Please fill all the fields");
    }
    else if (password != cPassword) {
      UIHelper.showAlertDialog(context, "Password Mismatch",
          "The passwords you entered do not match!");
    }
    else {
      signUp(email, password);
    }
  }

  void signUp(String email, String password) async {
    UserCredential? credential;

    UIHelper.showLoadingDialog(context, "Creating new account..");

    try {
      credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email, password: password);
      print("User credential received: $credential");
    } on FirebaseAuthException catch (ex) {
      Navigator.pop(context);
      print("Error during sign up: ${ex.message}");
      UIHelper.showAlertDialog(
          context, "An error occurred", ex.message.toString());
      return; // Exit the function if there's an error
    }

    if (credential != null) {
      String uid = credential.user!.uid;
      UserModel newUser = UserModel(
        uid: uid,
        email: email,
        fullname: "",
        profilepic: "",
      );

      try {
        // Generate keys using LWE
        Map<String, List<int>> keys = lwe.publicKey();

        // Store private keys locally
        await lwe.storeKeys(keys);
        print("Private keys stored locally.");

        // Assign public keys to the user model
        newUser.pk = keys['pk'];
        newUser.pk_t = keys['pk_t'];
        newUser.A = keys['A'];
        print("Public keys assigned to user model.");

        // Save the user model to Firestore
        await FirebaseFirestore.instance.collection("users").doc(uid).set(newUser.toMap());
        print("User data uploaded to Firestore.");

        // Navigate to the CompleteProfile page
        Navigator.popUntil(context, (route) => route.isFirst);
       final user = credential.user;

if (user != null) {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (context) {
        return CompleteProfile(
          userModel: newUser,
          firebaseUser: user,
        );
      },
    ),
  );
} else {
  // Handle null case
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Failed to sign in. Please try again.')),
  );
}

      } catch (e) {
        Navigator.pop(context);
        print("Exception during sign-up: $e");
        UIHelper.showAlertDialog(context, "Error", "An error occurred during sign up. Please try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 40,
          ),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                children: [

                  Text("Chat App", style: TextStyle(
                      color: Theme
                          .of(context)
                          .colorScheme
                          .secondary,
                      fontSize: 45,
                      fontWeight: FontWeight.bold
                  ),),

                  SizedBox(height: 10,),

                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                        labelText: "Email Address"
                    ),
                  ),

                  SizedBox(height: 10,),

                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: "Password"
                    ),
                  ),

                  SizedBox(height: 10,),

                  TextField(
                    controller: cPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: "Confirm Password"
                    ),
                  ),

                  SizedBox(height: 20,),

                  CupertinoButton(
                    onPressed: () {
                      checkValues();
                    },
                    color: Theme
                        .of(context)
                        .colorScheme
                        .secondary,
                    child: Text("Sign Up"),
                  ),

                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            Text("Already have an account?", style: TextStyle(
                fontSize: 16
            ),),

            CupertinoButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text("Log In", style: TextStyle(
                  fontSize: 16
              ),),
            ),

          ],
        ),
      ),
    );
  }
}
