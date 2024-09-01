import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/UserModel.dart';
import '../models/FirebaseHelper.dart';

class ProfilePage extends StatefulWidget {
  final UserModel userModel;
  final User firebaseUser;
//    final VoidCallback onProfileUpdated;

  const ProfilePage({Key? key, required this.userModel, required this.firebaseUser,}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  File? _image;

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

Future<void> _updateProfilePicture() async {
  if (_image != null) {
    // Upload the image to Firebase Storage and update the user profile
    String imageUrl = await FirebaseHelper.uploadUserProfilePicture(widget.userModel.uid!, _image!);

    // Update the user profile in Firestore
    await FirebaseFirestore.instance.collection('users').doc(widget.userModel.uid!).update({
      'profilepic': imageUrl,
    });

    setState(() {
      _image = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Profile picture updated successfully!')),
    );

    // Pass 'true' back to indicate that the profile was updated
    Navigator.pop(context, true); // This will trigger a refresh in HomePage
  }
}



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Profile'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 80,
                backgroundImage: _image == null 
                    ? NetworkImage(widget.userModel.profilepic!) as ImageProvider<Object>
                    : FileImage(_image!),
              ),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Your email ID: ${widget.userModel.email!}',
                  style: TextStyle(fontSize: 18),
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _pickImage,
                child: Text('Change Profile Picture'),
              ),
              if (_image != null)
                ElevatedButton(
                  onPressed: _updateProfilePicture,
                  child: Text('Update Profile Picture'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
