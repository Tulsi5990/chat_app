class UserModel {
  String? uid;
  String? fullname;
  String? email;
  String? profilepic;
  List<int>? pk;
  List<int>? pk_t;
  List<int>? A;

  UserModel({this.uid, this.fullname, this.email, this.profilepic, this.pk, this.pk_t, this.A});

  UserModel.fromMap(Map<String, dynamic> map) {
    uid = map["uid"];
    fullname = map["fullname"];
    email = map["email"];
    profilepic = map["profilepic"];
    pk = map["pk"] != null ? List<int>.from(map["pk"]) : null;
    pk_t = map["pk_t"] != null ? List<int>.from(map["pk_t"]) : null;
    A = map["A"] != null ? List<int>.from(map["A"]) : null;
  }

  Map<String, dynamic> toMap() {
    return {
      "uid": uid,
      "fullname": fullname,
      "email": email,
      "profilepic": profilepic,
      "pk": pk,
      "pk_t": pk_t,
      "A": A,
    };
  }
}
