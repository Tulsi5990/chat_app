import 'package:flutter/material.dart';
import 'package:chat_app_lattice/models/FirebaseHelper.dart';
import 'package:chat_app_lattice/models/UserModel.dart';
import 'package:chat_app_lattice/pages/ChatRoomPage.dart';
import 'package:chat_app_lattice/pages/LoginPage.dart';
import 'package:chat_app_lattice/pages/SearchPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:chat_app_lattice/models/ChatRoomModel.dart';
import 'package:chat_app_lattice/pages/ProfilePage.dart';



class HomePage extends StatefulWidget {
  final UserModel userModel;
  final User firebaseUser;


  const HomePage({Key? key, required this.userModel, required this.firebaseUser}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<UserModel?> userModelFuture;

  @override
  void initState() {
    super.initState();
    userModelFuture = FirebaseHelper.getUserModelById(widget.firebaseUser.uid!);
  }


  Future<void> _refreshUserModel() async {
    setState(() {
      userModelFuture = FirebaseHelper.getUserModelById(widget.firebaseUser.uid!);
    });
  }


Widget _buildLastMessageSubtitle(ChatRoomModel chatRoomModel) {
  final lastMessageContent = chatRoomModel.lastMessageContent ?? "";
  final lastMessageTimestamp = chatRoomModel.lastMessageTimestamp?.toDate();

  String formattedTime = "";
  if (lastMessageTimestamp != null) {
    DateTime now = DateTime.now();
    DateTime todayMidnight = DateTime(now.year, now.month, now.day);
    DateTime messageMidnight = DateTime(lastMessageTimestamp.year, lastMessageTimestamp.month, lastMessageTimestamp.day);

    if (messageMidnight == todayMidnight) {
      formattedTime = "Today, ${TimeOfDay.fromDateTime(lastMessageTimestamp).format(context)}";
    } else if (todayMidnight.difference(messageMidnight).inDays == 1) {
      formattedTime = "Yesterday, ${TimeOfDay.fromDateTime(lastMessageTimestamp).format(context)}";
    } else {
      formattedTime = "${lastMessageTimestamp.day}/${lastMessageTimestamp.month}/${lastMessageTimestamp.year}, ${TimeOfDay.fromDateTime(lastMessageTimestamp).format(context)}";
    }
  }

  String lastMessageDisplay = "";
  switch (chatRoomModel.lastMessageType) {
    case "image":
      lastMessageDisplay = "Sent a photo";
      break;
    case "video":
      lastMessageDisplay = "Sent a video";
      break;
    case "pdf":
      lastMessageDisplay = "Sent a file";
      break;
    case "deleted":
      lastMessageDisplay = "The last message was deleted";
      break;
    case "text":
    default:
      lastMessageDisplay = lastMessageContent;
      break;
  }

  final unreadCount = chatRoomModel.unreadMessageCount?[widget.userModel.uid] ?? 0;

  return Row(
    children: [
      Expanded(child: Text("$lastMessageDisplay • $formattedTime")),
      if (unreadCount > 0)
        Container(
          margin: EdgeInsets.only(left: 5),
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            unreadCount.toString(),
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
    ],
  );
}

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text("Chat App"),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'profile') {
                // Navigate to the Profile Page and refresh the user model when returning
                final result= await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfilePage(userModel: widget.userModel, firebaseUser: widget.firebaseUser,),
                  ),
                );
                // Refresh user model after coming back
               if (result == true) {
                  _refreshUserModel();
                }
              } else if (value == 'logout') {
                // Handle logout
                await FirebaseAuth.instance.signOut();
                Navigator.popUntil(context, (route) => route.isFirst);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => LoginPage()),
                );
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: 'profile',
                  child: Text('My Profile'),
                ),
                PopupMenuItem<String>(
                  value: 'logout',
                  child: Text('Logout'),
                ),
              ];
            },
            icon: Icon(Icons.more_vert),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<UserModel?>(
          future: userModelFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text("Error: ${snapshot.error}"));
            }
            if (!snapshot.hasData || snapshot.data == null) {
              return Center(child: Text("No User Data"));
            }
            final userModel = snapshot.data!;

            return StreamBuilder(
              stream: FirebaseFirestore.instance.collection("chatrooms")
                  .where("participants.${userModel.uid}", isEqualTo: true)
                  .snapshots(),
              builder: (context, chatSnapshot) {
                if (chatSnapshot.connectionState == ConnectionState.active) {
                  if (chatSnapshot.hasData) {
                    QuerySnapshot chatRoomSnapshot = chatSnapshot.data as QuerySnapshot;

                    return ListView.builder(
                      itemCount: chatRoomSnapshot.docs.length,
                      itemBuilder: (context, index) {
                        ChatRoomModel chatRoomModel = ChatRoomModel.fromMap(chatRoomSnapshot.docs[index].data() as Map<String, dynamic>);

                        Map<String, dynamic> participants = chatRoomModel.participants!;
                        List<String> participantKeys = participants.keys.toList();
                        participantKeys.remove(userModel.uid);

                        return FutureBuilder(
                          future: FirebaseHelper.getUserModelById(participantKeys[0]),
                          builder: (context, userData) {
                            if (userData.connectionState == ConnectionState.done) {
                              if (userData.data != null) {
                                UserModel targetUser = userData.data as UserModel;

                                return ListTile(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) {
                                        return ChatRoomPage(
                                          chatroom: chatRoomModel,
                                          firebaseUser: widget.firebaseUser,
                                          userModel: userModel,
                                          targetUser: targetUser,
                                        );
                                      }),
                                    );
                                  },
                                  leading: CircleAvatar(
                                    backgroundImage: NetworkImage(targetUser.profilepic.toString()),
                                  ),
                                  title: Text(targetUser.fullname.toString()),
                                  subtitle: _buildLastMessageSubtitle(chatRoomModel),
                                );
                              } else {
                                return Container();
                              }
                            } else {
                              return Center(child: CircularProgressIndicator());
                            }
                          },
                        );
                      },
                    );
                  } else if (chatSnapshot.hasError) {
                    return Center(child: Text(chatSnapshot.error.toString()));
                  } else {
                    return Center(child: Text("No Chats"));
                  }
                } else {
                  return Center(child: CircularProgressIndicator());
                }
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SearchPage(userModel: widget.userModel, firebaseUser: widget.firebaseUser),
            ),
          );
        },
        child: Icon(Icons.search),
      ),
    );
  }
}
