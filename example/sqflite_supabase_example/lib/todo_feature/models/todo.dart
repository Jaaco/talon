import 'dart:convert';

// ignore_for_file: public_member_api_docs, sort_constructors_first
class Todo {
  final String id;
  final String name;
  final bool isDone;

  Todo({
    required this.id,
    required this.name,
    required this.isDone,
  });

  Todo copyWith({
    String? id,
    String? name,
    bool? isDone,
  }) {
    return Todo(
      id: id ?? this.id,
      name: name ?? this.name,
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'is_done': isDone,
    };
  }

  factory Todo.fromMap(Map<String, dynamic> map) {
    return Todo(
      id: map['id'] as String,
      name: map['name'] as String,
      isDone: map['is_done'] == 1 ? true : false,
    );
  }

  String toJson() => json.encode(toMap());

  factory Todo.fromJson(String source) =>
      Todo.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'Todo(id: $id, name: $name, isDone: $isDone)';

  @override
  bool operator ==(covariant Todo other) {
    if (identical(this, other)) return true;

    return other.id == id && other.name == name && other.isDone == isDone;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ isDone.hashCode;
}
