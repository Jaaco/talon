class Todo {
  final String id;
  final String name;
  final bool isDone;

  const Todo({
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

  factory Todo.fromMap(Map<String, dynamic> map) {
    return Todo(
      id: map['id'] as String,
      name: (map['name'] as String?) ?? '',
      isDone: map['is_done'] == 1 || map['is_done'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Todo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          isDone == other.isDone;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ isDone.hashCode;

  @override
  String toString() => 'Todo(id: $id, name: $name, isDone: $isDone)';
}
