import 'dart:convert'; // Import for JSON encoding and decoding
import 'dart:developer';

import 'package:chat_app_lattice/main.dart';
import 'package:chat_app_lattice/models/UserModel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:chat_app_lattice/models/ChatRoomModel.dart';
import 'package:chat_app_lattice/models/MessageModel.dart';
import 'package:chat_app_lattice/encryption/lwe.dart'; // Import the lwe.dart

class ChatRoomPage extends StatefulWidget {
  final UserModel targetUser;
  final ChatRoomModel chatroom;
  final UserModel userModel;
  final User firebaseUser;

  const ChatRoomPage({Key? key, required this.targetUser, required this.chatroom, required this.userModel, required this.firebaseUser}) : super(key: key);

  @override
  _ChatRoomPageState createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  TextEditingController messageController = TextEditingController();
  final LWE lwe = LWE(); // Instantiate the LWE class

  void sendMessage() async {
    String msg = messageController.text.trim();
    messageController.clear();

    if (msg != "") {
      // Generate encryption keys
      final keys = lwe.publicKey();
      final pk = keys['pk'];
      final pk_t = keys['pk_t'];
      final A = keys['A'];

      // Encrypt the message
      final storedBits = lwe.stringToBits(msg);
      final encrypted = lwe.encryption(storedBits, pk, pk_t, A);

      // Convert encryptedText to JSON string
      String encryptedText = jsonEncode(encrypted['encryptedText']);

      // Send Message
      MessageModel newMessage = MessageModel(
        messageid: uuid.v1(),
        sender: widget.userModel.uid,
        createdon: DateTime.now(),
        text: msg,
        cipherText: encryptedText,
        seen: false,
      );

      await FirebaseFirestore.instance
          .collection("chatrooms")
          .doc(widget.chatroom.chatroomid)
          .collection("messages")
          .doc(newMessage.messageid)
          .set(newMessage.toMap());

      widget.chatroom.lastMessage = msg;
      await FirebaseFirestore.instance
          .collection("chatrooms")
          .doc(widget.chatroom.chatroomid)
          .set(widget.chatroom.toMap());

      log("Message Sent!");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.grey[300],
              backgroundImage: NetworkImage(widget.targetUser.profilepic.toString()),
            ),
            SizedBox(width: 10),
            Text(widget.targetUser.fullname.toString()),
          ],
        ),
      ),
      body: SafeArea(
        child: Container(
          child: Column(
            children: [
              // This is where the chats will go
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: StreamBuilder(
                    stream: FirebaseFirestore.instance
                        .collection("chatrooms")
                        .doc(widget.chatroom.chatroomid)
                        .collection("messages")
                        .orderBy("createdon", descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.active) {
                        if (snapshot.hasData) {
                          QuerySnapshot dataSnapshot = snapshot.data as QuerySnapshot;

                          return ListView.builder(
                            reverse: true,
                            itemCount: dataSnapshot.docs.length,
                            itemBuilder: (context, index) {
                              MessageModel currentMessage = MessageModel.fromMap(dataSnapshot.docs[index].data() as Map<String, dynamic>);

                              return Row(
                                mainAxisAlignment: (currentMessage.sender == widget.userModel.uid)
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: EdgeInsets.symmetric(vertical: 2),
                                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: (currentMessage.sender == widget.userModel.uid)
                                          ? Colors.grey
                                          : Theme.of(context).colorScheme.secondary,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      currentMessage.text.toString(),
                                      style: TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        } else if (snapshot.hasError) {
                          return Center(
                            child: Text("An error occurred! Please check your internet connection."),
                          );
                        } else {
                          return Center(
                            child: Text("Say hi to your new friend"),
                          );
                        }
                      } else {
                        return Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                    },
                  ),
                ),
              ),
              Container(
                color: Colors.grey[200],
                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                child: Row(
                  children: [
                    Flexible(
                      child: TextField(
                        controller: messageController,
                        maxLines: null,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: "Enter message",
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: sendMessage,
                      icon: Icon(
                        Icons.send,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}