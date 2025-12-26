// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

// todo(jacoo): create fromServerJson and fromLocalJson constructors that take potentially different params or default values
// fromServerJson would set 'hasBeenSynced' to true by default
class Message {
  final String id;

  final String table;
  final String row;
  final String column;
  final String dataType;
  final String value;

  final int? serverTimestamp;
  final String localTimestamp;

  final String userId;
  final String clientId;

  final bool hasBeenApplied;
  final bool hasBeenSynced;

  Message({
    required this.id,
    required this.table,
    required this.row,
    required this.column,
    required this.dataType,
    required this.value,
    this.serverTimestamp,
    required this.localTimestamp,
    required this.userId,
    required this.clientId,
    required this.hasBeenApplied,
    required this.hasBeenSynced,
  });

  Message copyWith({
    String? id,
    String? table,
    String? row,
    String? column,
    String? dataType,
    String? value,
    int? serverTimestamp,
    String? localTimestamp,
    String? userId,
    String? clientId,
    bool? hasBeenApplied,
    bool? hasBeenSynced,
  }) {
    return Message(
      id: id ?? this.id,
      table: table ?? this.table,
      row: row ?? this.row,
      column: column ?? this.column,
      dataType: dataType ?? this.dataType,
      value: value ?? this.value,
      serverTimestamp: serverTimestamp ?? this.serverTimestamp,
      localTimestamp: localTimestamp ?? this.localTimestamp,
      userId: userId ?? this.userId,
      clientId: clientId ?? this.clientId,
      hasBeenApplied: hasBeenApplied ?? this.hasBeenApplied,
      hasBeenSynced: hasBeenSynced ?? this.hasBeenSynced,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'table_name': table,
      'row': row,
      'column': column,
      'data_type': dataType,
      'value': value,
      'server_timestamp': serverTimestamp,
      'local_timestamp': localTimestamp,
      'user_id': userId,
      'client_id': clientId,
      'hasBeenApplied': hasBeenApplied ? 1 : 0,
      'hasBeenSynced': hasBeenSynced ? 1 : 0,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      table: map['table_name'] as String,
      row: map['row'] as String,
      column: map['column'] as String,
      dataType: map['data_type'] as String,
      value: map['value'] as String,
      serverTimestamp: map['server_timestamp'] != null
          ? map['server_timestamp'] as int
          : null,
      localTimestamp: map['local_timestamp'] as String,
      userId: map['user_id'] as String,
      clientId: map['client_id'] as String,
      hasBeenApplied: map['hasBeenApplied'] == 1 ? true : false,
      hasBeenSynced: map['hasBeenSynced'] == 1 ? true : false,
    );
  }

  String toJson() => json.encode(toMap());

  factory Message.fromJson(String source) =>
      Message.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'Message(id: $id, table: $table, row: $row, column: $column, dataType: $dataType, value: $value, serverTimestamp: $serverTimestamp, localTimestamp: $localTimestamp, userId: $userId, clientId: $clientId, hasBeenApplied: $hasBeenApplied, hasBeenSynced: $hasBeenSynced)';
  }

  @override
  bool operator ==(covariant Message other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.table == table &&
        other.row == row &&
        other.column == column &&
        other.dataType == dataType &&
        other.value == value &&
        other.serverTimestamp == serverTimestamp &&
        other.localTimestamp == localTimestamp &&
        other.userId == userId &&
        other.clientId == clientId &&
        other.hasBeenApplied == hasBeenApplied &&
        other.hasBeenSynced == hasBeenSynced;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        table.hashCode ^
        row.hashCode ^
        column.hashCode ^
        dataType.hashCode ^
        value.hashCode ^
        serverTimestamp.hashCode ^
        localTimestamp.hashCode ^
        userId.hashCode ^
        clientId.hashCode ^
        hasBeenApplied.hashCode ^
        hasBeenSynced.hashCode;
  }

  /// Deserialize the value based on dataType.
  ///
  /// Returns the original typed value based on the dataType field.
  /// Supported types: null, string, int, double, bool, datetime, json.
  ///
  /// Note: This is a convenience method for reading values.
  /// The actual database storage/retrieval is the developer's responsibility.
  dynamic get typedValue {
    switch (dataType) {
      case 'null':
        return null;
      case '':
        if (value.isEmpty) return null;
        return value;
      case 'string':
        return value;
      case 'int':
        return int.tryParse(value) ?? 0;
      case 'double':
        return double.tryParse(value) ?? 0.0;
      case 'bool':
        return value == '1' || value.toLowerCase() == 'true';
      case 'datetime':
        return DateTime.tryParse(value);
      case 'json':
        try {
          return json.decode(value);
        } catch (e) {
          return value;
        }
      default:
        return value;
    }
  }
}
