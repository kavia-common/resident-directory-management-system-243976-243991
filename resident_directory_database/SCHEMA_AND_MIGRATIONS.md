# Resident Directory Database: Schema & Migrations

This database container runs PostgreSQL locally (default port `5000`) and stores a connection string in `db_connection.txt`.

## Start PostgreSQL

From `resident_directory_database/`:

```bash
./startup.sh
```

This will ensure:
- Postgres is running
- Database `myapp` exists
- User `appuser` exists
- `db_connection.txt` is written with the canonical connection string

## Apply schema migrations + seeds

```bash
./migrate.sh
```

What it does:
- Applies all `migrations/*.sql` in sorted order
- Applies all `seeds/*.sql` in sorted order

### Important note about the seeded admin user
The seed file creates:
- Roles: `admin`, `resident`
- A bootstrap user `admin@example.com` with a placeholder password hash

You should replace that password hash via the backend’s actual hashing algorithm (or remove that seed section entirely if you don't want a default admin).

## Tables created

- `roles`, `users`, `user_roles`
- `resident_profiles` (includes privacy flags)
- `announcements`
- `contact_requests`, `message_threads`, `message_thread_participants`, `messages`
- `data_import_jobs`, `data_export_jobs`
- `audit_logs`
