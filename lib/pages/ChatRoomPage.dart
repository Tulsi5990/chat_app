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






 Future<void> sendMessage() async {
  String msg = messageController.text.trim();
  messageController.clear();

  if (pickedFile != null) {
    File file = File(pickedFile!.path);
    String messageId = uuid.v1();
    String fileType = pickedFile!.path.endsWith('.mp4')
        ? 'video'
        : pickedFile!.path.endsWith('.pdf')
            ? 'pdf'
            : 'image';
    await uploadFile(file, widget.chatroom.chatroomid!, messageId, fileType);
    setState(() {
      pickedFile = null;
    });
    return;
  }

  if (msg.isNotEmpty) {
    // Identify the recipient based on the chatroom's participants
    String recipientId = widget.chatroom.participants!.keys.firstWhere(
        (key) => key != widget.userModel.uid,
        orElse: () => '');

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

          MessageModel newMessage = MessageModel(
            messageid: uuid.v1(),
            sender: widget.userModel.uid,
            createdon: Timestamp.now().toDate(),
            text: msg,
            cipherText: encryptedText,
            fileUrl: null,
            fileType: null,
            seen: false,
          );

          await FirebaseFirestore.instance
              .collection("chatrooms")
              .doc(widget.chatroom.chatroomid)
              .collection("messages")
              .doc(newMessage.messageid)
              .set(newMessage.toMap());

          widget.chatroom.lastMessage = msg;
          widget.chatroom.lastMessageType = 'text';
          widget.chatroom.lastMessageContent = msg;
          widget.chatroom.lastMessageTimestamp = Timestamp.now();
          widget.chatroom.lastMessageId = newMessage.messageid;

          // Increment unread message count for the recipient
          FirebaseFirestore.instance
              .collection("chatrooms")
              .doc(widget.chatroom.chatroomid)
              .update({"unreadMessageCount.$recipientId": FieldValue.increment(1)});

          await FirebaseFirestore.instance
              .collection("chatrooms")
              .doc(widget.chatroom.chatroomid)
              .set(widget.chatroom.toMap(), SetOptions(merge: true));

          log.i("Message Sent!");
        } else {
          log.e("Public key data is missing for recipient.");
        }
      } catch (e) {
        log.e("Failed to fetch recipient's public key: $e");
      }
    } else {
      log.e("Recipient ID could not be determined.");
    }
  }
}











void markMessagesAsSeen() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    await FirebaseFirestore.instance
        .collection('chatrooms')
        .doc(widget.chatroom.chatroomid)
        .collection('messages')
        .where('receiver', isEqualTo: user.uid)
        .where('seen', isEqualTo: false)
        .get()
        .then((snapshot) {
      for (var doc in snapshot.docs) {
        doc.reference.update({'seen': true});
      }
    });

    // Reset unread message count after marking messages as seen
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
  if (widget.chatroom.chatroomid != null) {
    await FirebaseFirestore.instance
        .collection("chatrooms")
        .doc(widget.chatroom.chatroomid)
        .update({
      "unreadMessageCount.${widget.userModel.uid}": 0,
    });
  }
}


@override
void initState() {
  super.initState();
  markMessagesAsSeen(); 
 if (widget.chatroom.chatroomid != null) {
  _resetUnreadMessageCount(); // Use the non-null assertion operator
}// Call when the chat page is opened
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



Future<void> _showDeleteDialog(String messageId) async {
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

  if (message.fileUrl != null) {
    if (message.fileType == 'image') {
      return Align(
        alignment: message.sender == widget.userModel.uid
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: message.sender == widget.userModel.uid
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () {
                _showDeleteDialog(message.messageid!);
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
            Text(
              formattedTime,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (message.seen)
              Icon(Icons.visibility, color: Colors.blue, size: 16), // Seen indicator
          ],
        ),
      );
    } else if (message.fileType == 'video') {
      return Align(
        alignment: message.sender == widget.userModel.uid
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: message.sender == widget.userModel.uid
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () {
                _showDeleteDialog(message.messageid!);
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
            Text(
              formattedTime,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (message.seen)
              Icon(Icons.visibility, color: Colors.blue, size: 16), // Seen indicator
          ],
        ),
      );
    } else if (message.fileType == 'pdf') {
      String fileName = message.fileName ?? 'Unknown.pdf';
      return Align(
        alignment: message.sender == widget.userModel.uid
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: message.sender == widget.userModel.uid
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () {
                _showDeleteDialog(message.messageid!);
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
            Text(
              formattedTime,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (message.seen)
              Icon(Icons.visibility, color: Colors.blue, size: 16), // Seen indicator
          ],
        ),
      );
    }
  } else if (message.cipherText != null && message.cipherText!.isNotEmpty) {
    return FutureBuilder<String>(
      future: decryptMessage(message.cipherText!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Text("Error: ${snapshot.error}");
        } else {
          return GestureDetector(
            onLongPress: () {
              _showDeleteDialog(message.messageid!);
            },
            child: Align(
              alignment: message.sender == widget.userModel.uid
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: message.sender == widget.userModel.uid
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: message.sender == widget.userModel.uid
                          ? Colors.grey[300]
                          : Theme.of(context).colorScheme.secondary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      snapshot.data ?? '',
                      style: TextStyle(fontSize: 16, color: Colors.black),
                    ),
                  ),
                  Text(
                    formattedTime,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (message.seen)
                    Icon(Icons.visibility, color: Colors.blue, size: 16), // Seen indicator
                ],
              ),
            ),
          );
        }
      },
    );
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