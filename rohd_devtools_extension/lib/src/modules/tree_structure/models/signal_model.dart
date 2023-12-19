class SignalModel {
  final String key;
  final String direction;
  final String value;
  final String width;

  SignalModel({
    required this.key,
    required this.direction,
    required this.value,
    required this.width,
  });

  factory SignalModel.fromMap(Map<String, dynamic> map) {
    return SignalModel(
      key: map['key'] as String,
      direction: map['direction'] as String,
      value: map['value'] as String,
      width: map['width'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'direction': direction,
      'value': value,
      'width': width,
    };
  }
}
