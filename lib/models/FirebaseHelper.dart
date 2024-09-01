import 'dart:io'; // Import for File
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart'; // Import for Firebase Storage
import 'package:chat_app_lattice/models/UserModel.dart';

class FirebaseHelper {
  static Future<UserModel?> getUserModelById(String uid) async {
    UserModel? userModel;

    DocumentSnapshot docSnap = await FirebaseFirestore.instance.collection("users").doc(uid).get();

    if (docSnap.data() != null) {
      userModel = UserModel.fromMap(docSnap.data() as Map<String, dynamic>);
    }

    return userModel;
  }

  static Future<String> uploadUserProfilePicture(String uid, File imageFile) async {
    try {
      // Define the storage reference
      Reference storageReference = FirebaseStorage.instance.ref().child("profile_pictures").child(uid);

      // Upload the file
      UploadTask uploadTask = storageReference.putFile(imageFile);
      TaskSnapshot taskSnapshot = await uploadTask;

      // Get the download URL
      String downloadURL = await taskSnapshot.ref.getDownloadURL();
      return downloadURL;
    } catch (e) {
      throw Exception("Error uploading profile picture: $e");
    }
  }
}
