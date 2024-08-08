import 'dart:convert'; // Import for JSON encoding and decoding
import 'dart:io'; // Import for File
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
import 'package:chat_app_lattice/encryption/lwe.dart'; // Import the lwe.dart
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:chat_app_lattice/fullScreen/full_screen_image.dart';
import 'package:chat_app_lattice/fullScreen/full_screen_video.dart';

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
  final LWE lwe = LWE();
  final Logger log = Logger();
  final ImagePicker _picker = ImagePicker();
  final Uuid uuid = Uuid();
  XFile? pickedFile;

  Future<void> _pickImageOrVideo() async {
  // Show options to choose between image or video
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
        ],
      );
    },
  );

  if (action != null) {
    final ImagePicker _picker = ImagePicker();
    XFile? pickedFile;

    if (action == 1) {
      pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    } else if (action == 2) {
      pickedFile = await _picker.pickVideo(source: ImageSource.gallery);
    }

    if (pickedFile != null) {
      File file = File(pickedFile.path);
      String messageId = uuid.v1();
      String fileType = pickedFile.path.endsWith('.mp4') ? 'video' : 'image';
      await uploadFile(file, widget.chatroom.chatroomid!, messageId, fileType);
    }
  }
}


  
  
Future<void> uploadFile(File file, String chatroomId, String messageId, String fileType) async {
  try {
    final storageRef = FirebaseStorage.instance.ref();
    final fileRef = storageRef.child('chatrooms/$chatroomId/$messageId.${fileType == 'image' ? 'jpg' : 'mp4'}');

    await fileRef.putFile(file);

    final downloadURL = await fileRef.getDownloadURL();

    final messageRef = FirebaseFirestore.instance.collection('chatrooms').doc(chatroomId).collection('messages').doc(messageId);
    await messageRef.set({
      'fileUrl': downloadURL,
      'fileType': fileType,
      'sender': widget.userModel.uid,
      'createdon': DateTime.now(),
      'text': '',
      'cipherText': '',
      'seen': false,
    }, SetOptions(merge: true));

    print('File uploaded and metadata saved successfully!');
  } catch (e) {
    print('Error uploading file: $e');
  }
}



// Future<void> _pickImageOrVideo() async {
//   final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery); // For images
//   // To enable video selection, you can add an option for the user to pick a video
//   // final XFile? pickedFile = await _picker.pickVideo(source: ImageSource.gallery);

//   if (pickedFile != null) {
//     File file = File(pickedFile.path);
//     String messageId = uuid.v1();
//     String fileType = pickedFile.path.endsWith('.mp4') ? 'video' : 'image';
//     await uploadFile(file, widget.chatroom.chatroomid!, messageId, fileType);
//   }
// }







  // Future<void> sendMessage() async {
  //   String msg = messageController.text.trim();
  //   messageController.clear();

  //   if (msg != "") {
  //     final keys = await lwe.getKeys();

  //     final pk = keys['pk'];
  //     final pk_t = keys['pk_t'];
  //     final A = keys['A'];

  //     final storedBits = lwe.stringToBits(msg);
  //     final encrypted = lwe.encryption(storedBits!, pk!, pk_t!, A!);

  //     String encryptedText = jsonEncode(encrypted['encryptedText']);
  //     log.i("Encrypted Text: $encryptedText");

  //     MessageModel newMessage = MessageModel(
  //       messageid: uuid.v1(),
  //       sender: widget.userModel.uid,
  //       createdon: DateTime.now(),
  //       text: msg,
  //       cipherText: encryptedText,
  //       fileUrl: null,
  //       fileType: null,
  //       seen: false,
  //     );

  //     await FirebaseFirestore.instance
  //         .collection("chatrooms")
  //         .doc(widget.chatroom.chatroomid)
  //         .collection("messages")
  //         .doc(newMessage.messageid)
  //         .set(newMessage.toMap());

  //     widget.chatroom.lastMessage = msg;
  //     await FirebaseFirestore.instance
  //         .collection("chatrooms")
  //         .doc(widget.chatroom.chatroomid)
  //         .set(widget.chatroom.toMap());

  //     log.i("Message Sent!");
  //   }
  // }





Future<void> sendMessage() async {
    String msg = messageController.text.trim();
    messageController.clear();

    if (pickedFile != null) {
      File file = File(pickedFile!.path);
      String messageId = uuid.v1();
      String fileType = pickedFile!.path.endsWith('.mp4') ? 'video' : 'image';
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
          jsonDecode(cipherText).map((x) => List<int>.from(x))
      );
      log.i("Encrypted Text Retrieved: $encryptedText");

      final String decryptedString = lwe.decryption(encryptedText, sk, sk_t);
      log.i("Decrypted String: $decryptedString");

      return decryptedString;
    } catch (e) {
      log.e("Error decrypting message: $e");
      return "Error decrypting message";
    }
  }








Widget _buildMessage(MessageModel message) {
  if (message.fileUrl != null) {
    if (message.fileType == 'image') {
      return Align(
        alignment: message.sender == widget.userModel.uid
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (BuildContext context) => FullScreenImage(message.fileUrl!),
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
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (BuildContext context) => FullScreenVideo(message.fileUrl!),
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
    }
  } else {
    return FutureBuilder<String>(
      future: decryptMessage(message.cipherText!),
      builder: (BuildContext context, AsyncSnapshot<String> decryptedSnapshot) {
        if (decryptedSnapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else if (decryptedSnapshot.hasError) {
          return Text("Error decrypting message");
        } else if (decryptedSnapshot.hasData) {
          String decryptedMessage = decryptedSnapshot.data!;
          return Row(
            mainAxisAlignment: (message.sender == widget.userModel.uid)
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Container(
                margin: EdgeInsets.symmetric(vertical: 2),
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                decoration: BoxDecoration(
                  color: (message.sender == widget.userModel.uid)
                      ? Colors.grey
                      : Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  decryptedMessage,
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        } else {
          return Container();
        }
      },
    );
  }
  return Container();
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
        actions: [
          IconButton(
            icon: Icon(Icons.photo_camera),
            onPressed: _pickImageOrVideo,
          ),
        ],
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
                        QuerySnapshot dataSnapshot = snapshot.data as QuerySnapshot;

                        return ListView.builder(
                          reverse: true,
                          itemCount: dataSnapshot.docs.length,
                          itemBuilder: (context, index) {
                            MessageModel currentMessage = MessageModel.fromMap(dataSnapshot.docs[index].data() as Map<String, dynamic>);
                            return _buildMessage(currentMessage);
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
            if (pickedFile != null)
              Container(
                color: Colors.grey[300],
                padding: EdgeInsets.all(10),
                child: Row(
                  children: [
                    if (pickedFile!.path.endsWith('.mp4'))
                      VideoPlayerWidget(pickedFile!.path),
                    if (!pickedFile!.path.endsWith('.mp4'))
                      Image.file(
                        File(pickedFile!.path),
                        width: 100,
                        height: 100,
                      ),
                    IconButton(
                      icon: Icon(Icons.cancel),
                      onPressed: () {
                        setState(() {
                          pickedFile = null;
                        });
                      },
                    ),
                  ],
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
    );
  }

}



class VideoThumbnailWidget extends StatefulWidget {
  final String videoUrl;

  const VideoThumbnailWidget(this.videoUrl, {Key? key}) : super(key: key);

  @override
  _VideoThumbnailWidgetState createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  late Future<String?> _thumbnail;

  @override
  void initState() {
    super.initState();
    _thumbnail = _generateThumbnail(widget.videoUrl);
  }

  Future<String?> _generateThumbnail(String videoUrl) async {
    final directory = await getTemporaryDirectory();
    final thumbnailPath = await VideoThumbnail.thumbnailFile(
      video: videoUrl,
      thumbnailPath: directory.path,
      imageFormat: ImageFormat.PNG,
      maxHeight: 120, // Adjust the height as needed
      quality: 75,
    );
    return thumbnailPath;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _thumbnail,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Icon(Icons.error));
        } else {
          return Stack(
            alignment: Alignment.center,
            children: [
              Image.file(
                File(snapshot.data!),
                fit: BoxFit.cover,
                width: 140, // Square dimensions
                height: 140, // Square dimensions
              ),
              Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 40, // Adjust the size of the play button as needed
              ),
            ],
          );
        }
      },
    );
  }
}



class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerWidget(this.videoUrl, {Key? key}) : super(key: key);

  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_controller.value.isPlaying) {
          _controller.pause();
        } else {
          _controller.play();
        }
        setState(() {
          _isPlaying = !_isPlaying;
        });
      },
      child: _controller.value.isInitialized
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            )
          : Center(child: CircularProgressIndicator()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class FullScreenVideo extends StatelessWidget {
  final String videoUrl;

  const FullScreenVideo(this.videoUrl, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video'),
      ),
      body: Center(
        child: VideoPlayerWidget(videoUrl),
      ),
    );
  }
}