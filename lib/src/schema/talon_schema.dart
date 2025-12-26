/// Schema definitions for Talon's messages table.
///
/// Use these in your database initialization to ensure
/// consistency with Talon's expectations.
///
/// ## SQLite Example
/// ```dart
/// await db.execute(TalonSchema.messagesTableSql);
/// ```
///
/// ## PostgreSQL/Supabase Example
/// ```sql
/// -- Run in Supabase SQL editor
/// -- (copy the content of TalonSchema.messagesTablePostgres)
/// ```
class TalonSchema {
  TalonSchema._();

  /// SQL schema for the messages table (SQLite compatible).
  ///
  /// Creates a table with all required columns and indexes
  /// for optimal Talon performance.
  ///
  /// Use in your OfflineDatabase.init():
  /// ```dart
  /// await db.execute(TalonSchema.messagesTableSql);
  /// ```
  static const String messagesTableSql = '''
CREATE TABLE IF NOT EXISTS talon_messages (
  id TEXT PRIMARY KEY,
  table_name TEXT NOT NULL,
  row TEXT NOT NULL,
  "column" TEXT NOT NULL,
  data_type TEXT NOT NULL DEFAULT '',
  value TEXT NOT NULL,
  server_timestamp INTEGER,
  local_timestamp TEXT NOT NULL,
  user_id TEXT NOT NULL,
  client_id TEXT NOT NULL,
  hasBeenApplied INTEGER NOT NULL DEFAULT 0 CHECK (hasBeenApplied IN (0, 1)),
  hasBeenSynced INTEGER NOT NULL DEFAULT 0 CHECK (hasBeenSynced IN (0, 1))
);

CREATE INDEX IF NOT EXISTS idx_talon_messages_sync
  ON talon_messages(hasBeenSynced);

CREATE INDEX IF NOT EXISTS idx_talon_messages_lookup
  ON talon_messages(table_name, row, "column");

CREATE INDEX IF NOT EXISTS idx_talon_messages_server_ts
  ON talon_messages(server_timestamp);
''';

  /// PostgreSQL schema for server-side messages table.
  ///
  /// Includes Row Level Security policies for Supabase.
  /// Run this in your Supabase SQL editor or as a migration.
  static const String messagesTablePostgres = '''
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  table_name TEXT NOT NULL,
  row TEXT NOT NULL,
  "column" TEXT NOT NULL,
  data_type TEXT NOT NULL DEFAULT '',
  value TEXT NOT NULL,
  server_timestamp BIGINT GENERATED ALWAYS AS IDENTITY,
  local_timestamp TEXT NOT NULL,
  user_id TEXT NOT NULL,
  client_id TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_sync
  ON messages(user_id, server_timestamp);

CREATE INDEX IF NOT EXISTS idx_messages_client
  ON messages(client_id);

-- Enable Row Level Security
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Users can only see their own messages
CREATE POLICY "Users can view own messages" ON messages
  FOR SELECT USING (auth.uid()::text = user_id);

-- Users can only insert their own messages
CREATE POLICY "Users can insert own messages" ON messages
  FOR INSERT WITH CHECK (auth.uid()::text = user_id);

-- Enable realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
''';

  /// Column names for the messages table.
  ///
  /// Useful for building queries or validating data.
  static const List<String> columnNames = [
    'id',
    'table_name',
    'row',
    'column',
    'data_type',
    'value',
    'server_timestamp',
    'local_timestamp',
    'user_id',
    'client_id',
    'hasBeenApplied',
    'hasBeenSynced',
  ];

  /// Column names for server-side table (without local tracking fields).
  static const List<String> serverColumnNames = [
    'id',
    'table_name',
    'row',
    'column',
    'data_type',
    'value',
    'server_timestamp',
    'local_timestamp',
    'user_id',
    'client_id',
  ];
}
