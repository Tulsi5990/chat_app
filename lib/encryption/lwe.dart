import 'dart:math';

class LWE {
  final int prime = 1523;

  List<int> generateUniqueRandomNumbers(int min, int max, int count) {
    final random = Random();
    Set<int> uniqueNumbers = {};

    while (uniqueNumbers.length < count) {
      int number = min + random.nextInt(max - min + 1);
      uniqueNumbers.add(number);
    }

    return uniqueNumbers.toList();
  }

  Map<String, List<List<int>>> encryption(List<int> storedBits, List<int> pk, List<int> pk_t, List<int> A) {
    final n = storedBits.length;
    List<List<int>> encryptedText = [];

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < 4; j++) {
        List<int> temp = [];
        for (int k = 0; k < 5; k++) {
          int x = 1 + Random().nextInt(190);
          temp.add(x);
        }

        List<int> v = [];
        int sum = 0;
        for (int ii = 0; ii < 128; ii++) {
          for (int jj = 0; jj < temp.length; jj++) {
            sum += (A[temp[jj]] | pk[ii]);
          }
          v.add(sum);
          sum = 0;
        }

        for (int jj = 0; jj < temp.length; jj++) {
          sum += pk_t[temp[jj]];
        }
        sum = sum % prime;
        if (storedBits[i] == 1) {
          v.add((sum % prime + prime ~/ 2) % prime);
        } else {
          v.add(sum % prime);
        }

        encryptedText.add(v);
      }
    }

    return {"encryptedText": encryptedText};
  }

  Map<String, dynamic> publicKey() {
    List<int> sk = [];
    List<int> sk_t = [];
    List<int> pk = [];
    List<int> pk_t = [];
    List<int> A = [];
    int prime = 1523;

    sk = generateUniqueRandomNumbers(10, 200, 128);
    sk_t = generateUniqueRandomNumbers(1, 120, 25);

    pk = generateUniqueRandomNumbers(1, 200, 128);
    A = generateUniqueRandomNumbers(1, 500, 200);

    int res = 0;
    int jj = 0, temp = 0;
    for (int i = 0; i < pk.length; i++) {
      if (i == sk_t[jj]) {
        jj++;
        continue;
      }
      res += pk[i] * sk[i];
    }
    pk_t.add((res % prime + temp % prime) % prime);
    res = 0;
    for (int i = 1; i < A.length; i++) {
      int x = 0, xx = 0;
      for (int j = 0; j < pk.length; j++) {
        if (j == sk_t[xx]) {
          xx++;
          continue;
        }
        res += ((pk[j] | A[i]) * sk[j]);
      }
      pk_t.add((res % prime + x % prime) % prime);
      res = 0;
    }

    List<int> err = [-5, -4, -3, -2, -1, 1, 2, 3, 4, 5];
    int j = 0;
    for (int i = 0; i < pk_t.length; i++) {
      pk_t[i] = (pk_t[i] + err[j++]) % prime;
      if (j == 10) j = 0;
    }

    return {"pk": pk, "pk_t": pk_t, "A": A, "sk": sk, "sk_t": sk_t};
  }

  String decryption(List<List<int>> cipherText, List<int> sk, List<int> sk_t) {
    List<int> resultantBits = [];
    int prime = 1523;
    for (int i = 0; i < cipherText.length; i++) {
      int sum = 0;
      int xx = 0;

      for (int j = 0; j < 128; j++) {
        if (j == sk_t[xx]) {
          xx++;
          continue;
        }
        sum += cipherText[i][j] * sk[j];
      }

      int kk = cipherText[i][cipherText[i].length - 1];
      if (kk < 0) {
        kk = prime - (kk.abs() % prime);
      }

      int diff = (sum % prime - kk % prime).abs() % prime;
      sum = 0;

      if ((diff >= 0 && diff <= 380) || (diff >= 1142 && diff <= 1522)) {
        resultantBits.add(0);
      } else {
        resultantBits.add(1);
      }
    }

    List<int> finalResult = [];
    int xx = resultantBits[0];

    for (int i = 1; i < resultantBits.length; i++) {
      if (i % 4 == 0) {
        finalResult.add(xx);
        xx = resultantBits[i];
      } else {
        xx = xx & resultantBits[i];
      }
    }

    finalResult.add(xx);
    String finalText = "";

    int ans = 0;
    for (int i = 0; i < finalResult.length; i++) {
      if (finalResult[i] == 1) {
        ans += 1 << i;
      }
    }
    finalText += String.fromCharCode(ans);

    return finalText;
  }

  List<int> stringToBits(String s) {
    List<int> bits = [];
    for (int i = 0; i < s.length; i++) {
      int charCode = s.codeUnitAt(i);
      for (int j = 7; j >= 0; j--) {
        bits.add((charCode >> j) & 1);
      }
    }
    return bits;
  }

  String bitsToString(List<int> bits) {
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < bits.length; i += 8) {
      int value = 0;
      for (int j = 0; j < 8; j++) {
        value = (value << 1) + bits[i + j];
      }
      buffer.writeCharCode(value);
    }
    return buffer.toString();
  }
}
