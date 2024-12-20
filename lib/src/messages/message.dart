// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

class Message {
  final String table;
  final String row;
  final String column;
  final String dataType;
  final String value;

  final String? serverTimestamp;
  final String localTimestamp;

  final String userId;
  final String clientId;

  const Message({
    required this.table,
    required this.row,
    required this.column,
    required this.dataType,
    required this.value,
    this.serverTimestamp,
    required this.localTimestamp,
    required this.userId,
    required this.clientId,
  });

  Message copyWith({
    String? table,
    String? row,
    String? column,
    String? dataType,
    String? value,
    String? serverTimestamp,
    String? localTimestamp,
    String? userId,
    String? clientId,
  }) {
    return Message(
      table: table ?? this.table,
      row: row ?? this.row,
      column: column ?? this.column,
      dataType: dataType ?? this.dataType,
      value: value ?? this.value,
      serverTimestamp: serverTimestamp ?? this.serverTimestamp,
      localTimestamp: localTimestamp ?? this.localTimestamp,
      userId: userId ?? this.userId,
      clientId: clientId ?? this.clientId,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'table': table,
      'row': row,
      'column': column,
      'dataType': dataType,
      'value': value,
      'serverTimestamp': serverTimestamp,
      'localTimestamp': localTimestamp,
      'userId': userId,
      'clientId': clientId,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      table: map['table'] as String,
      row: map['row'] as String,
      column: map['column'] as String,
      dataType: map['dataType'] as String,
      value: map['value'] as String,
      serverTimestamp: map['serverTimestamp'] != null
          ? map['serverTimestamp'] as String
          : null,
      localTimestamp: map['localTimestamp'] as String,
      userId: map['userId'] as String,
      clientId: map['clientId'] as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory Message.fromJson(String source) =>
      Message.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'Message(table: $table, row: $row, column: $column, dataType: $dataType, value: $value, serverTimestamp: $serverTimestamp, localTimestamp: $localTimestamp, userId: $userId, clientId: $clientId)';
  }

  @override
  bool operator ==(covariant Message other) {
    if (identical(this, other)) return true;

    return other.table == table &&
        other.row == row &&
        other.column == column &&
        other.dataType == dataType &&
        other.value == value &&
        other.serverTimestamp == serverTimestamp &&
        other.localTimestamp == localTimestamp &&
        other.userId == userId &&
        other.clientId == clientId;
  }

  @override
  int get hashCode {
    return table.hashCode ^
        row.hashCode ^
        column.hashCode ^
        dataType.hashCode ^
        value.hashCode ^
        serverTimestamp.hashCode ^
        localTimestamp.hashCode ^
        userId.hashCode ^
        clientId.hashCode;
  }
}
