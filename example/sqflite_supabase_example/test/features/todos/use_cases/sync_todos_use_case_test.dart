import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_supabase_example/features/todos/domain/todo.dart';
import 'package:sqflite_supabase_example/features/todos/domain/todo_repository.dart';
import 'package:sqflite_supabase_example/features/todos/domain/use_cases/sync_todos_use_case.dart';

class MockTodoRepository extends Mock implements TodoRepository {}

void main() {
  late MockTodoRepository mockRepository;
  late SyncTodosUseCase useCase;

  setUp(() {
    mockRepository = MockTodoRepository();
    useCase = SyncTodosUseCase(mockRepository);
  });

  test('calls sync then getTodos and returns todos', () async {
    final todos = [const Todo(id: '1', name: 'Synced todo', isDone: false)];

    when(() => mockRepository.sync()).thenAnswer((_) async {});
    when(() => mockRepository.getTodos()).thenAnswer((_) async => todos);

    final result = await useCase();

    verifyInOrder([
      () => mockRepository.sync(),
      () => mockRepository.getTodos(),
    ]);
    expect(result, equals(todos));
  });
}
