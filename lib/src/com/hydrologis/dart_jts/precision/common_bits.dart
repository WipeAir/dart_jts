part of dart_jts;


class CommonBits
{

  static int signExpBits(int num)
  {
    return num >> 52;
  }

  static int numCommonMostSigMantissaBits(int num1, int num2)
  {
    int count = 0;
    for (int i = 52; i >= 0; i--) {
      if (getBit(num1, i) != getBit(num2, i)) {
        return count;
      }
      count++;
    }
    return 52;
  }

  static int zeroLowerBits(int bits, int nBits)
  {
    int invMask = ((1 << nBits) - 1);
    int mask = (~invMask);
    int zeroed = (bits & mask);
    return zeroed;
  }

  static int getBit(int bits, int i)
  {
    int mask = (1 << i);
    return ((bits & mask) != 0) ? 1 : 0;
  }
  bool isFirst = true;
  int commonMantissaBitsCount = 53;
  int commonBits = 0;
  int commonSignExp;

  CommonBits()
  {
  }

  void add(double num)
  {
    // final data = ByteData(8)..setFloat64(0,, num);
    final data = ByteData(8);
    data.setFloat64(0, num);

    final numBits = data.getInt64(0);

    if (isFirst) {
      commonBits = numBits;
      commonSignExp = signExpBits(commonBits);
      isFirst = false;
      return;
    }
    int numSignExp = signExpBits(numBits);
    if (numSignExp != commonSignExp) {
      commonBits = 0;
      return;
    }
    commonMantissaBitsCount = numCommonMostSigMantissaBits(commonBits, numBits);
    commonBits = zeroLowerBits(commonBits, 64 - (12 + commonMantissaBitsCount));
  }

  double getCommon()
  {
    final data = ByteData(8);
    data.setInt64(0, commonBits);

    return data.getFloat64(0);
  }

  String toStringBits(int bits)
  {
    /*double x = Double.longBitsToDouble(bits);
    String numStr = Long.toBinaryString(bits);
    String padStr = ("0000000000000000000000000000000000000000000000000000000000000000" + numStr);
    String bitStr = padStr.substring(padStr.length - 64);
    String str = (((((((bitStr.substring(0, 1) + "  ") + bitStr.substring(1, 12)) + "(exp) ") + bitStr.substring(12)) + " [ ") + x) + " ]");
    return str;*/
    return "";
  }
}
