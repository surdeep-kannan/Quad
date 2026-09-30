# quad

A student community app: communities and discussions, real-time chat, rooms with voice and video, short videos, events with registrations and waitlists, and transparent college rankings, all in one place.

Built with **Flutter** (Android, iOS, web) and **Supabase** (Postgres, Auth, Realtime, Storage).

- [PROJECT.md](PROJECT.md): full guide, including status, what's done and not done, a map of every file, database reference and next steps
- [SPEC.md](SPEC.md): the product brief

## Quick start

```bash
# 1. Database (needs a Supabase project; put its keys in .env, see PROJECT.md §2)
cd tools
npm install
npm run db:check      # tests every migration locally in an in-memory Postgres
npm run db:migrate    # applies the schema to your Supabase project
npm run db:seed-demo  # optional demo students, communities, posts and events

# 2. App (copy app/env/dev.example.json to app/env/dev.json and fill it in)
cd ../app
flutter pub get
flutter run -d chrome --dart-define-from-file=env/dev.json
```

## Structure

```
app/        Flutter app (lib/core = shared, lib/features = one folder per feature)
supabase/   SQL migrations (schema, security rules, feeds, search, rankings) and seed data
tools/      Node scripts for testing, applying and seeding the database
```
