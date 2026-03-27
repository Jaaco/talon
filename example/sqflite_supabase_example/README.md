# sqflite_supabase_example

A Flutter example app demonstrating offline-first CRUD with Supabase sync using the talon package.

## Setup

### 1. Get your Supabase credentials

From your [Supabase dashboard](https://supabase.com/dashboard), copy:
- **Project URL** (e.g. `https://abc123.supabase.co`)
- **Anon public key** (found under Settings > API)

### 2. Run the app

Pass your credentials via `--dart-define`:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

If you omit the credentials, the app will show a helpful error screen with instructions.

### 3. Optional: use a dart-define file

To avoid typing keys each time, create a `.env` file (git-ignored):

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

Then run:

```bash
flutter run -d chrome --dart-define-from-file=.env
```

Each Chrome tab gets a unique clientId via sessionStorage, so opening two tabs demonstrates two-client sync.

## Unit tests

```bash
flutter test
```

## Integration tests (Patrol)

The integration tests verify end-to-end CRUD sync between two independent Talon clients through a real Supabase backend.

### Prerequisites

```bash
# Install patrol_cli globally
dart pub global activate patrol_cli

# Verify installation
patrol doctor
```

Node.js is required for web testing (Patrol uses Playwright under the hood).

### Running

```bash
patrol test --device chrome \
  --dart-define=SUPABASE_URL=<url> \
  --dart-define=SUPABASE_ANON_KEY=<key>
```

Headless (CI):

```bash
patrol test --device chrome \
  --dart-define=SUPABASE_URL=<url> \
  --dart-define=SUPABASE_ANON_KEY=<key> \
  --web-headless true
```

### What the test does

`patrol_test/two_instance_sync_test.dart` runs a full CRUD sync flow:

1. **Client A** creates a todo with a unique title and syncs to Supabase
2. **Client B** syncs from Supabase and verifies the todo appears
3. **Client A** toggles the todo as done and syncs
4. **Client B** syncs and verifies the todo is marked done
5. **Client A** deletes the todo and syncs
6. **Client B** syncs and verifies the todo is gone

Client B uses its own sqflite database and a different clientId — a truly independent Talon client sharing only the Supabase backend.
