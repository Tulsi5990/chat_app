class ChatRoomModel {
  String? chatroomid;
  Map<String, dynamic>? participants;
  String? lastMessage;
  String? lastMessageType; // Add this field
  String? lastMessageContent; // Add this field

  ChatRoomModel({
    this.chatroomid,
    this.participants,
    this.lastMessage,
    this.lastMessageType,
    this.lastMessageContent,
  });

  ChatRoomModel.fromMap(Map<String, dynamic> map) {
    chatroomid = map["chatroomid"];
    participants = map["participants"];
    lastMessage = map["lastmessage"];
    lastMessageType = map["lastMessageType"]; // Parse the type
    lastMessageContent = map["lastMessageContent"]; // Parse the content
  }

  Map<String, dynamic> toMap() {
    return {
      "chatroomid": chatroomid,
      "participants": participants,
      "lastmessage": lastMessage,
      "lastMessageType": lastMessageType, // Add the type
      "lastMessageContent": lastMessageContent, // Add the content
    };
  }
}
