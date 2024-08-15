import 'package:cloud_firestore/cloud_firestore.dart';


class ChatRoomModel {
  String? chatroomid;
  Map<String, dynamic>? participants;
  String? lastMessage;
  String? lastMessageType;
   String? lastMessageId; // Add this field
  String? lastMessageContent;
  Timestamp? lastMessageTimestamp;
  Map<String, int>? unreadMessageCount; // Add this field

  ChatRoomModel({
    this.chatroomid,
    this.participants,
    this.lastMessage,
    this.lastMessageType,
     this.lastMessageId,
    this.lastMessageContent,
    this.lastMessageTimestamp,
    this.unreadMessageCount, 
  });

  // Initialize unreadMessageCount in the initializer list
   ChatRoomModel.fromMap(Map<String, dynamic> map) {
    chatroomid = map["chatroomid"];
    participants = map["participants"];
    lastMessage = map["lastmessage"];
    lastMessageId = map["lastMessageId"];
    lastMessageType = map["lastMessageType"];
    lastMessageContent = map["lastMessageContent"];
    lastMessageTimestamp = map["lastMessageTimestamp"];

    // Handling both int and Map<String, int>
    if (map["unreadMessageCount"] is Map) {
      unreadMessageCount = Map<String, int>.from(map["unreadMessageCount"]);
    } else if (map["unreadMessageCount"] is int) {
      // Assuming the previous implementation was using an integer
      unreadMessageCount = {participants!.keys.first: map["unreadMessageCount"]};
    } else {
      unreadMessageCount = {};
    }
  }

  Map<String, dynamic> toMap() {
    return {
      "chatroomid": chatroomid,
      "participants": participants,
      "lastmessage": lastMessage,
      "lastMessageType": lastMessageType,
       "lastMessageId": lastMessageId, // Add the type
      "lastMessageContent": lastMessageContent, // Add the content
      "lastMessageTimestamp": lastMessageTimestamp,
      'unreadMessageCount': unreadMessageCount,
    };
  }
}
