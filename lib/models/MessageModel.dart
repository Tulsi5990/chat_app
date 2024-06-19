class MessageModel {
  String? messageid;
  String? sender;
  String? text;
  String? cipherText;
  bool? seen;
  DateTime? createdon;

  MessageModel({this.messageid, this.sender, this.text, this.seen, this.createdon, this.cipherText});

  MessageModel.fromMap(Map<String, dynamic> map) {
    messageid = map["messageid"];
    sender = map["sender"];
    text = map["text"];
    cipherText= map["cipherText"];
    seen = map["seen"];
    createdon = map["createdon"].toDate();
  }

  Map<String, dynamic> toMap() {
    return {
      "messageid": messageid,
      "sender": sender,
      "text": text,
      "cipherText": cipherText,
      "seen": seen,
      "createdon": createdon
    };
  }
}