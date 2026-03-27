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
