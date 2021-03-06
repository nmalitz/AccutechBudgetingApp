import 'package:budgetflow/global/strings.dart';
import 'package:budgetflow/model/abstract/serializable.dart';
import 'package:budgetflow/model/utils/serializer.dart';

class PaymentMethod implements Serializable {
  static final String cashName = 'Cash';

  String methodName;

  static final cash = PaymentMethod(cashName);

  PaymentMethod(this.methodName);

  /// Returns the value side of a key-value pair used in storing this object as a JSON object.
  String get serialize {
    Serializer serializer = Serializer();
    serializer.addPair(methodNameKey, methodName);
    return serializer.serialize;
  }

  bool operator ==(Object other) => other is PaymentMethod && _equals(other);

  bool _equals(PaymentMethod other) {
    return methodName == other.methodName;
  }

  int get hashCode => methodName.hashCode;
}
