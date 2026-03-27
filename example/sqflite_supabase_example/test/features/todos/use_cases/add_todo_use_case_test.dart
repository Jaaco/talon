import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_supabase_example/features/todos/domain/todo_repository.dart';
import 'package:sqflite_supabase_example/features/todos/domain/use_cases/add_todo_use_case.dart';

class MockTodoRepository extends Mock implements TodoRepository {}

void main() {
  late MockTodoRepository mockRepository;
  late AddTodoUseCase useCase;

  setUp(() {
    mockRepository = MockTodoRepository();
    useCase = AddTodoUseCase(mockRepository);
  });

  test('delegates addTodo to repository', () async {
    when(() => mockRepository.addTodo(any(), any()))
        .thenAnswer((_) async {});

    await useCase('test-id', 'Buy milk');

    verify(() => mockRepository.addTodo('test-id', 'Buy milk')).called(1);
  });
}
