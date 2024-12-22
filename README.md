# Talon

A lightweight dependency free layer for making offline first apps.

## The magic

`Talon` is a quick and reliable way to make offline first apps with Flutter. Anybody who has ever dabbled with doing this knows the complexity and setup required to make sure that the app:

- Can be used without internet connection indefinetely
- Syncs all its changes to the server once connection is restored
- Only syncs relevant data to and from the server (not the whole database)
- Works with multiple (potentially offline) devices updating the same data

`Talon` has a straight forward way of solving all of these problems, enabling you to focus on features for your users, while also offering a seamless app experience, no matter the internet connection.

## Using `Talon` in Flutter

Works with any local sql package (eg. [sqflite](https://pub.dev/packages/sqflite)).

Initial setup takes ~300LOC, after which any changes to persisted data can be made in the following style:

```dart
class TodoRepository {
  Future<void> addTodo(String id, String name) async {
    await talon.saveChange(
      table: 'todos',
      row: id,
      column: 'name',
      value: name,
    );
  }

  Future<void> updateIsDone(String id, bool todoState) async {
    await talon.saveChange(
      table: 'todos',
      row: id,
      column: 'is_done',
      value: todoState ? '1' : '0',
    );
  }
}
```

All changes made in this way will be:

- Immediately applied to the local sql database
- Synced to the server at the next possible moment
- Conflict free between the same account & multiple devices updating the same database field

This package implements a CRDT (conflict-free replicated data type) to store each data change as `Message`, which contains:

- Which field was changed
- The new value of the field
- Who changed the field (which user & from which device)
- When was the field changed (to decide which change is the most current)
