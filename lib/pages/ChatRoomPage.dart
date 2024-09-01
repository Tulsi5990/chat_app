import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:chat_app_lattice/main.dart';
import 'package:chat_app_lattice/models/UserModel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:chat_app_lattice/models/ChatRoomModel.dart';
import 'package:chat_app_lattice/models/MessageModel.dart';
import 'package:chat_app_lattice/encryption/lwe.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:chat_app_lattice/fullScreen/full_screen_image.dart';
import 'package:chat_app_lattice/fullScreen/full_screen_video.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

class ChatRoomPage extends StatefulWidget {
  final UserModel targetUser;
  final ChatRoomModel chatroom;
  final UserModel userModel;
  final User firebaseUser;

  const ChatRoomPage({
    Key? key,
    required this.targetUser,
    required this.chatroom,
    required this.userModel,
    required this.firebaseUser,
  }) : super(key: key);

  @override
  _ChatRoomPageState createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  TextEditingController messageController = TextEditingController();
  final LWE lwe = LWE();
  final Logger log = Logger();
  final ImagePicker _picker = ImagePicker();
  final Uuid uuid = Uuid();
  XFile? pickedFile;

  Future<void> _pickImageOrVideoOrPDF() async {
    final action = await showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Media'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 1),
              child: Text('Image'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 2),
              child: Text('Video'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 3),
              child: Text('PDF'),
            ),
          ],
        );
      },
    );

    if (action != null) {
      if (action == 1) {
        pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      } else if (action == 2) {
        pickedFile = await _picker.pickVideo(source: ImageSource.gallery);
      } else if (action == 3) {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );

        if (result != null && result.files.single.path != null) {
          pickedFile = XFile(result.files.single.path!);
        }
      }

      if (pickedFile != null) {
        File file = File(pickedFile!.path);
        String messageId = uuid.v1();
        String fileType = pickedFile!.path.endsWith('.mp4')
            ? 'video'
            : pickedFile!.path.endsWith('.pdf')
                ? 'pdf'
                : 'image';
        await uploadFile(file, widget.chatroom.chatroomid!, messageId, fileType);
      }
    }
  }

  Future<void> uploadFile(
      File file, String chatroomId, String messageId, String fileType) async {
    try {
      final storageRef = FirebaseStorage.instance.ref();
      final fileRef = storageRef.child(
          'chatrooms/$chatroomId/$messageId.${fileType == 'image' ? 'jpg' : fileType == 'video' ? 'mp4' : 'pdf'}');

      await fileRef.putFile(file);

      final downloadURL = await fileRef.getDownloadURL();
      final fileName = p.basename(file.path); // Get the filename

      final messageRef = FirebaseFirestore.instance
          .collection('chatrooms')
          .doc(chatroomId)
          .collection('messages')
          .doc(messageId);
      await messageRef.set({
        'messageid': messageId,
        'fileUrl': downloadURL,
        'fileType': fileType,
        'sender': widget.userModel.uid,
        'createdon': Timestamp.now(),
        'text': '',
        'cipherText': '',
        'fileName': fileName,
        'seen': false,
      }, SetOptions(merge: true));

      widget.chatroom.lastMessage = fileName; // Set the filename as last message
      widget.chatroom.lastMessageType = fileType; // Set file type
      widget.chatroom.lastMessageContent = downloadURL; // Set file URL
      widget.chatroom.lastMessageTimestamp = Timestamp.now(); // Set timestamp
      await FirebaseFirestore.instance
          .collection("chatrooms")
          .doc(widget.chatroom.chatroomid)
          .set(widget.chatroom.toMap());

      log.i('File uploaded and metadata saved successfully!');
    } catch (e) {
      log.e('Error uploading file: $e');
    }
  }


void _incrementUnreadMessageCount(String chatroomId, String receiverId) async {
  DocumentReference chatroomRef = FirebaseFirestore.instance.collection("chatrooms").doc(chatroomId);

  await FirebaseFirestore.instance.runTransaction((transaction) async {
    DocumentSnapshot snapshot = await transaction.get(chatroomRef);

    if (snapshot.exists) {
      ChatRoomModel chatRoomModel = ChatRoomModel.fromMap(snapshot.data() as Map<String, dynamic>);
      
      // Initialize the unreadMessageCount map if it's null
      chatRoomModel.unreadMessageCount ??= {};

      // Increment the unread message count for the specific receiver
      chatRoomModel.unreadMessageCount![receiverId] = (chatRoomModel.unreadMessageCount![receiverId] ?? 0) + 1;

      transaction.update(chatroomRef, chatRoomModel.toMap());
    }
  });
}



// Listen to changes in the 'seen' field for the last message in the chatroom
void _listenForSeenUpdates() {
  FirebaseFirestore.instance
      .collection('chatrooms')
      .doc(widget.chatroom.chatroomid)
      .collection('messages')
      .orderBy('createdon', descending: true)
      .limit(1)
      .snapshots()
      .listen((snapshot) {
    if (snapshot.docs.isNotEmpty) {
      final messageData = snapshot.docs.first.data();
      
      // Check if the message is seen and sent by the current user
      if (messageData['seen'] == true && messageData['sender'] == widget.userModel.uid) {
        // Trigger UI update to show the seen icon
        setState(() {
          _lastMessageSeen = true;
        });
        print("Message seen status updated for message ID: ${snapshot.docs.first.id}");
      } else {
        print("No seen status update needed.");
      }
    } else {
      print("No messages found.");
    }
  });
}

bool _lastMessageSeen = false; // State variable to manage UI updates

@override
void initState() {
  super.initState();
  markMessagesAsSeen();
  if (widget.chatroom.chatroomid != null) {
    _resetUnreadMessageCount();
    _listenForSeenUpdates(); // Start listening for seen updates
  }
}


// void _incrementUnreadMessageCount(String receiverId) async {
//     if (widget.chatroom.chatroomid != null) {
//       await FirebaseFirestore.instance
//           .collection("chatrooms")
//           .doc(widget.chatroom.chatroomid)
//           .update({
//         "unreadMessageCount.$receiverId": FieldValue.increment(1),
//       });
//     }
//   }




 Future<void> sendMessage() async {
  String msg = messageController.text.trim();
  messageController.clear();

  if (pickedFile != null) {
    File file = File(pickedFile!.path);
    String messageId = uuid.v1();
    String fileType;

    if (pickedFile!.path.endsWith('.mp4')) {
      fileType = 'video';
    } else if (pickedFile!.path.endsWith('.pdf')) {
      fileType = 'pdf';
    } else {
      fileType = 'image';
    }

    // Handle file upload
    await uploadFile(file, widget.chatroom.chatroomid!, messageId, fileType);
    setState(() {
      pickedFile = null;
    });
    return;
  }

  if (msg.isNotEmpty) {
    String recipientId = widget.chatroom.participants!.keys.firstWhere(
        (key) => key != widget.userModel.uid,
        orElse: () => '');

    MessageModel newMessage;

    if (recipientId.isNotEmpty) {
      try {
        // Fetch recipient's public key
        Map<String, List<int>> publicKey = await lwe.getRecipientPublicKey(recipientId);

        if (publicKey['pk']!.isNotEmpty && publicKey['pk_t']!.isNotEmpty && publicKey['A']!.isNotEmpty) {
          // Encrypt the message using the recipient's public key
          final storedBits = lwe.stringToBits(msg);
          final encrypted = lwe.encryption(storedBits!, publicKey['pk']!, publicKey['pk_t']!, publicKey['A']!);

          String encryptedText = jsonEncode(encrypted['encryptedText']);
          log.i("Encrypted Text: $encryptedText");

          // Create message model with the encrypted text for receiver
          newMessage = MessageModel(
            messageid: uuid.v1(),
            sender: widget.userModel.uid,
            senderId: widget.userModel.uid,
            createdon: Timestamp.now().toDate(),
            text: msg, // Normal text for sender's side
            cipherText: encryptedText, // Encrypted text for receiver's side
            fileUrl: null,
            fileType: null,
            seen: false,
          );
        } else {
          log.e("Public key data is missing for recipient.");
          return;
        }
      } catch (e) {
        log.e("Failed to fetch recipient's public key: $e");
        return;
      }
    } else {
      log.e("Recipient ID could not be determined.");
      return;
    }

    // Save the message to Firestore
    await FirebaseFirestore.instance
        .collection("chatrooms")
        .doc(widget.chatroom.chatroomid)
        .collection("messages")
        .doc(newMessage.messageid)
        .set(newMessage.toMap());

    widget.chatroom.lastMessage = "sent a message";
    widget.chatroom.lastMessageType = 'text';
    widget.chatroom.lastMessageContent = "sent a message";
    widget.chatroom.lastMessageTimestamp = Timestamp.now();
    widget.chatroom.lastMessageId = newMessage.messageid;

    // Increment unread message count for the recipient
     _incrementUnreadMessageCount(widget.chatroom.chatroomid!, recipientId);

    

    await FirebaseFirestore.instance
        .collection("chatrooms")
        .doc(widget.chatroom.chatroomid)
        .set(widget.chatroom.toMap(), SetOptions(merge: true));

    log.i("Message Sent!");
  }
}







void markMessagesAsSeen() async {
  print("markMessagesAsSeen() called");  // Debugging statement
  final user = FirebaseAuth.instance.currentUser;

  // Get the recipient ID by finding the participant who is not the current user
  String recipientId = widget.chatroom.participants!.keys.firstWhere(
        (key) => key != widget.userModel.uid,
        orElse: () => '');

  if (user != null) {
    // Check if the current user is the recipient
    if (user.uid != recipientId) {
      // Do not mark as seen if the current user is not the recipient
      print("Current user is not the recipient, no need to update seen status.");
      return;
    }

    // Proceed with marking messages as seen
    await FirebaseFirestore.instance
        .collection('chatrooms')
        .doc(widget.chatroom.chatroomid)
        .collection('messages')
        .where('reciever', isEqualTo: user.uid)
        .where('seen', isEqualTo: false)
        .get()
        .then((snapshot) {
      for (var doc in snapshot.docs) {
        print("Updating seen status for message: ${doc.id}");  // Debugging statement
        doc.reference.update({'seen': true}).catchError((error) {
          print('Failed to update seen status: $error');
        });
      }
    }).catchError((error) {
      print('Failed to fetch unread messages: $error');
    });

    _resetUnreadMessageCount();
  }
}










void _updateUnreadMessageCount() async {
  // Only increment for the receiver
  if (widget.userModel.uid != widget.targetUser.uid) {
    await FirebaseFirestore.instance
        .collection("chatrooms")
        .doc(widget.chatroom.chatroomid)
        .update({
      "unreadMessageCount.${widget.targetUser.uid}": FieldValue.increment(1),
    });
  }
}

// Reset the unread message count when the receiver opens the chat room
  void _resetUnreadMessageCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (widget.chatroom.chatroomid != null) {
        await FirebaseFirestore.instance
            .collection("chatrooms")
            .doc(widget.chatroom.chatroomid)
            .update({
          "unreadMessageCount.${user.uid}": 0,
        });
      }
    }
  }








  Future<String> decryptMessage(String cipherText) async {
    try {
      final keys = await lwe.getPrivateKeys();
      final List<int> sk = keys['sk'] ?? [];
      final List<int> sk_t = keys['sk_t'] ?? [];

      if (sk.isEmpty || sk_t.isEmpty) {
        log.e("Decryption keys are missing");
        return "Error decrypting message: Missing keys";
      }

      final List<List<int>> encryptedText = List<List<int>>.from(
          jsonDecode(cipherText).map((x) => List<int>.from(x)));
      log.i("Encrypted Text Retrieved: $encryptedText");

      final String decryptedString = lwe.decryption(encryptedText, sk, sk_t);
      log.i("Decrypted String: $decryptedString");

      return decryptedString;
    } catch (e) {
      log.e("Error decrypting message: $e");
      return "Error decrypting message";
    }
  }



String formatTimestamp(Timestamp timestamp) {
  DateTime now = DateTime.now();
  DateTime date = timestamp.toDate();
  
  // Reset time to midnight for accurate day difference comparison
  DateTime nowMidnight = DateTime(now.year, now.month, now.day);
  DateTime dateMidnight = DateTime(date.year, date.month, date.day);
  
  Duration diff = nowMidnight.difference(dateMidnight);
  
  if (diff.inDays == 0) {
    // Today
    return DateFormat('h:mm a').format(date);
  } else if (diff.inDays == 1) {
    // Yesterday
    return 'Yesterday, ${DateFormat('h:mm a').format(date)}';
  } else if (diff.inDays < 7) {
    // Day of the week with time (e.g., Monday, 4:00 PM)
    return '${DateFormat('EEEE').format(date)}, ${DateFormat('h:mm a').format(date)}';
  } else {
    // Date with time (e.g., Jul 24, 2024, 4:00 PM)
    return '${DateFormat('MMM d, yyyy').format(date)}, ${DateFormat('h:mm a').format(date)}';
  }
}






Future<void> _launchURL(String url) async {
  Uri uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    log.e('Could not launch $url');
  }
}



Future<void> _showDeleteDialog(String messageId, String senderId) async {
  // Get the current user ID
  final currentUser = FirebaseAuth.instance.currentUser;

  if (currentUser == null || currentUser.uid != senderId) {
    // If the current user is not the sender, do nothing or show a message
    return; // Alternatively, you can show a message like a toast saying "You can only delete your own messages."
  }

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Delete Message'),
        content: Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _deleteMessage(messageId);
              Navigator.pop(context);
            },
            child: Text('Delete'),
          ),
        ],
      );
    },
  );
}


Future<void> _deleteMessage(String messageId) async {
  // Get the chat room document
  DocumentReference chatRoomRef = FirebaseFirestore.instance
      .collection("chatrooms")
      .doc(widget.chatroom.chatroomid);

  // Get the current chat room data
  DocumentSnapshot chatRoomDoc = await chatRoomRef.get();
  if (!chatRoomDoc.exists) return;

  ChatRoomModel chatRoomModel = ChatRoomModel.fromMap(chatRoomDoc.data() as Map<String, dynamic>);

  // Check if the deleted message was the last message
  if (chatRoomModel.lastMessageId == messageId) {
    // Update the chat room with "last message was deleted"
    await chatRoomRef.update({
      'lastMessage': 'The last message was deleted',
      'lastMessageType': 'deleted',
      'lastMessageContent': null,
      'lastMessageId': null,
      'lastMessageTimestamp': Timestamp.now(), // Update timestamp
    });
  } else {
    // If it's not the last message, no need to update the last message
    await chatRoomRef.update({
      'lastMessageId': chatRoomModel.lastMessageId, // Ensure this field is updated correctly
    });
  }

  // Delete the message
  await FirebaseFirestore.instance
      .collection("chatrooms")
      .doc(widget.chatroom.chatroomid)
      .collection("messages")
      .doc(messageId)
      .delete();

  log.i("Message Deleted!");
}






Widget _buildMessage(MessageModel message) {
  String formattedTime = formatTimestamp(Timestamp.fromDate(message.createdon!));
  bool isSender = message.sender == widget.userModel.uid;

  if (message.fileUrl != null) {
    // For media files (image, video, pdf)
    if (message.fileType == 'image') {
      return Align(
        alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () {
               _showDeleteDialog(message.messageid!, message.senderId!);
              },
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (BuildContext context) =>
                        FullScreenImage(message.fileUrl!),
                  ),
                );
              },
              child: Container(
                margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey, width: 3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Hero(
                  tag: message.fileUrl!,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      message.fileUrl!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formattedTime,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (isSender && message.seen)
                  Icon(Icons.visibility, color: Colors.blue, size: 16), // Seen indicator for sender
              ],
            ),
          ],
        ),
      );
    } else if (message.fileType == 'video') {
      return Align(
        alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () {
                _showDeleteDialog(message.messageid!, message.senderId!);
              },
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (BuildContext context) =>
                        FullScreenVideo(message.fileUrl!),
                  ),
                );
              },
              child: Container(
                margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey, width: 3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: VideoThumbnailWidget(message.fileUrl!),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formattedTime,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (isSender && message.seen)
                  Icon(Icons.visibility, color: Colors.blue, size: 16), // Seen indicator for sender
              ],
            ),
          ],
        ),
      );
    } else if (message.fileType == 'pdf') {
      String fileName = message.fileName ?? 'Unknown.pdf';
      return Align(
        alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () {
                _showDeleteDialog(message.messageid!, message.senderId!);
              },
              onTap: () async {
                try {
                  await _launchURL(message.fileUrl!);
                } catch (e) {
                  log.e('Could not launch ${message.fileUrl!}');
                }
              },
              child: Container(
                margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                width: 140,
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey, width: 3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.picture_as_pdf, size: 50, color: Colors.red),
                    Text(
                      fileName,
                      style: TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Open PDF',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formattedTime,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (isSender && message.seen)
                  Icon(Icons.visibility, color: Colors.blue, size: 16), // Seen indicator for sender
              ],
            ),
          ],
        ),
      );
    }
  } else if (message.cipherText != null && message.cipherText!.isNotEmpty) {
    if (isSender) {
      // For the sender, show the normal text without decryption
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              onLongPress: () {
                 _showDeleteDialog(message.messageid!, message.senderId!);
              },
              child: Container(
                margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  message.text!,
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formattedTime,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (message.seen)
                  Icon(Icons.remove_red_eye, color: Colors.blue, size: 16), // Seen indicator for sender
              ],
            ),
          ],
        ),
      );
    } else {
      // For the receiver, decrypt and display the message
      return FutureBuilder<String>(
        future: decryptMessage(message.cipherText!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return CircularProgressIndicator();
          } else if (snapshot.hasError) {
            return Text("Error decrypting message: ${snapshot.error}");
          } else {
            String decryptedMessage = snapshot.data ?? "Error decrypting message";

            return Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onLongPress: () {
                       _showDeleteDialog(message.messageid!, message.senderId!);
                    },
                    child: Container(
                      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        decryptedMessage,
                        style: TextStyle(fontSize: 16, color: Colors.black),
                      ),
                    ),
                  ),
                  Text(
                    formattedTime,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  // No seen icon for the receiver
                ],
              ),
            );
          }
        },
      );
    }
  }

  return Container(); // Default empty container
}


@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey[300],
            backgroundImage: NetworkImage(widget.targetUser.profilepic!),
          ),
          SizedBox(width: 10),
          Text(widget.targetUser.fullname!),
        ],
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
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
                      QuerySnapshot dataSnapshot =
                          snapshot.data as QuerySnapshot;

                      return ListView.builder(
                        reverse: true,
                        itemCount: dataSnapshot.docs.length,
                        itemBuilder: (context, index) {
                          MessageModel currentMessage = MessageModel.fromMap(
                              dataSnapshot.docs[index].data()
                                  as Map<String, dynamic>);

                          return _buildMessage(currentMessage);
                        },
                      );
                    } else if (snapshot.hasError) {
                      return Center(
                        child: Text(
                            "An error occurred! Please check your internet connection."),
                      );
                    } else {
                      return Center(
                        child: Text("Say Hi to your new friend"),
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
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                IconButton(
                  onPressed: _pickImageOrVideoOrPDF,
                  icon: Icon(Icons.attach_file),
                ),
                Flexible(
                  child: TextField(
                    controller: messageController,
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: "Enter message",
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    sendMessage();
                  },
                  icon: Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

}
class VideoThumbnailWidget extends StatefulWidget {
  final String videoUrl;

  VideoThumbnailWidget(this.videoUrl);

  @override
  _VideoThumbnailWidgetState createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  String? thumbnailPath;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: widget.videoUrl,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.PNG,
        maxWidth: 128,
        quality: 75,
      ) as String;

      setState(() {
        this.thumbnailPath = thumbnailPath;
      });
    } catch (e) {
      print("Error generating thumbnail: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (thumbnailPath != null) {
      return Image.file(
        File(thumbnailPath!),
        fit: BoxFit.cover,
      );
    } else {
      return Center(
        child: CircularProgressIndicator(),
      );
    }
  }
}