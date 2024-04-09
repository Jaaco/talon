// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

class Message {
  final String id;
  final String hlcTimestamp;
  final String row;
  final String column;
  final String value;
  Message({
    required this.id,
    required this.hlcTimestamp,
    required this.row,
    required this.column,
    required this.value,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'hlc_timestamp': hlcTimestamp,
      'row': row,
      'column': column,
      'value': value,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      hlcTimestamp: map['hlc_timestamp'] as String,
      row: map['row'] as String,
      column: map['column'] as String,
      value: map['value'] as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory Message.fromJson(String source) =>
      Message.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'Message(id: $id, hlc_timestamp: $hlcTimestamp, row: $row, column: $column, value: $value)';
  }

  @override
  bool operator ==(covariant Message other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.hlcTimestamp == hlcTimestamp &&
        other.row == row &&
        other.column == column &&
        other.value == value;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        hlcTimestamp.hashCode ^
        row.hashCode ^
        column.hashCode ^
        value.hashCode;
  }
}
