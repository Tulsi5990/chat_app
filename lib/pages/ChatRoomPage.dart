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
        'createdon': DateTime.now(),
        'text': '',
        'cipherText': '',
        'fileName': fileName, 
        'seen': false,
      }, SetOptions(merge: true));

      print('File uploaded and metadata saved successfully!');
    } catch (e) {
      print('Error uploading file: $e');
    }
  }

  Future<void> sendMessage() async {
    String msg = messageController.text.trim();
    messageController.clear();

    if (pickedFile != null) {
      File file = File(pickedFile!.path);
      String messageId = uuid.v1();
      String fileType =
          pickedFile!.path.endsWith('.mp4') ? 'video' : 'image';
      await uploadFile(file, widget.chatroom.chatroomid!, messageId, fileType);
      setState(() {
        pickedFile = null;
      });
      return;
    }

    if (msg != "") {
      final keys = await lwe.getKeys();

      final pk = keys['pk'];
      final pk_t = keys['pk_t'];
      final A = keys['A'];

      final storedBits = lwe.stringToBits(msg);
      final encrypted = lwe.encryption(storedBits!, pk!, pk_t!, A!);

      String encryptedText = jsonEncode(encrypted['encryptedText']);
      log.i("Encrypted Text: $encryptedText");

      MessageModel newMessage = MessageModel(
        messageid: uuid.v1(),
        sender: widget.userModel.uid,
        createdon: DateTime.now(),
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
      await FirebaseFirestore.instance
          .collection("chatrooms")
          .doc(widget.chatroom.chatroomid)
          .set(widget.chatroom.toMap());

      log.i("Message Sent!");
    }
  }

  Future<String> decryptMessage(String cipherText) async {
    try {
      final keys = await lwe.getKeys();
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
  await FirebaseFirestore.instance
      .collection("chatrooms")
      .doc(widget.chatroom.chatroomid)
      .collection("messages")
      .doc(messageId)
      .delete();

  log.i("Message Deleted!");
}




  Widget _buildMessage(MessageModel message) {
    if (message.fileUrl != null) {
      if (message.fileType == 'image') {
        return Align(
          alignment: message.sender == widget.userModel.uid
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: GestureDetector(
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
              width: 140, // Square dimensions
              height: 140, // Square dimensions
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
        );
      } else if (message.fileType == 'video') {
        return Align(
          alignment: message.sender == widget.userModel.uid
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: GestureDetector(
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
              width: 140, // Square dimensions
              height: 140, // Square dimensions
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
        );
      } else if (message.fileType == 'pdf') {
        String fileName = message.fileName ?? 'Unknown.pdf'; 
        return Align(
          alignment: message.sender == widget.userModel.uid
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: GestureDetector(
             onLongPress: () {
              print("Long press detected on message ID: ${message.messageid}");
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
                  fileName, // Display the filename here
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
            return  GestureDetector(
            onLongPress: () {
              print("Long press detected on message ID: ${message.messageid}");
              _showDeleteDialog(message.messageid!);
            },
            child:Align(
              alignment: message.sender == widget.userModel.uid
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
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
                    onPressed: sendMessage,
                    icon: Icon(Icons.send, color: Colors.blue),
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
