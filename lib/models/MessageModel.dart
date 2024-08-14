// class MessageModel {
//   String? messageid;
//   String? sender;
//   String? text;
//   String? cipherText;
//   bool? seen;
//   DateTime? createdon;

//   MessageModel({this.messageid, this.sender, this.text, this.seen, this.createdon, this.cipherText});

//   MessageModel.fromMap(Map<String, dynamic> map) {
//     messageid = map["messageid"];
//     sender = map["sender"];
//     text = map["text"];
//     cipherText= map["cipherText"];
//     seen = map["seen"];
//     createdon = map["createdon"].toDate();
//   }

//   Map<String, dynamic> toMap() {
//     return {
//       "messageid": messageid,
//       "sender": sender,
//       "text": text,
//       "cipherText": cipherText,
//       "seen": seen,
//       "createdon": createdon
//     };
//   }
// }
import 'package:cloud_firestore/cloud_firestore.dart'; // Ensure this import is present

class MessageModel {
  final String? messageid;
  final String? sender;
  final DateTime? createdon;
  final String? text;
  final String? cipherText;
  final String? fileUrl;
  final String? fileType;
  final bool? seen;
  final String? fileName;
  final DateTime timestamp;

  MessageModel({
    this.messageid,
    this.sender,
    this.text,
    this.seen,
    this.createdon,
    this.cipherText,
    this.fileUrl,
    this.fileName,
    this.fileType,
    // this.timestamp,
  });

  factory MessageModel.fromMap(Map<String, dynamic> data) {
    return MessageModel(
      messageid: data['messageid'],
      sender: data['sender'],
      text: data['text'],
      seen: data['seen'],
      createdon: (data['createdon'] as Timestamp).toDate(), // Correct usage
      cipherText: data['cipherText'],
      fileUrl: data['fileUrl'],
      fileType: data['fileType'],
      fileName:data['fileName'],
      // timestamp:data['timestamp'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'messageid': messageid,
      'sender': sender,
      'text': text,
      'seen': seen,
      'createdon': createdon != null ? Timestamp.fromDate(createdon!) : null, // Correct usage
      'cipherText': cipherText,
      'fileUrl': fileUrl,
      'fileType': fileType,
      'fileName':fileName,
      // 'timestamp':timestamp,
    };
  }
}
