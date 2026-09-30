# Remote deployment

## Target shape

The first production-like environment can run on a managed container host with a managed PostgreSQL database:

```text
Android/web app -> HTTPS ingress -> Go API container -> managed PostgreSQL
                                      |
                                      `-> push/payment providers
```

Examples include Cloud Run plus Cloud SQL, Azure Container Apps plus Azure Database for PostgreSQL, AWS App Runner/ECS plus RDS, or a small VPS with a managed database. The design does not require a specific vendor.

## Configuration

Runtime values are environment variables. `.env.example` documents names only; real secrets belong in the host's secret manager.

Minimum initial variables:

- `APP_ENV`
- `PORT`
- `DATABASE_URL`
- `PAYMENT_PROVIDER=simulated`
- `ALLOWED_ORIGINS` for any future web client

## Deployment sequence

1. Provision PostgreSQL with automated backups and TLS.
2. Build `services/api/Dockerfile` and push the immutable image to a registry.
3. Back up the database and run `/api migrate` from the new immutable image as
   a one-off release job. Do not start the new API revision if this job fails.
4. Deploy the API with a non-root runtime, health probe `/healthz`, and HTTPS ingress.
5. Restrict database networking to the API environment.
6. Configure logs, error alerts, CPU/memory limits, and uptime checks.
7. Set the Flutter build's `API_BASE_URL` to the HTTPS API origin.
8. Run smoke tests, then distribute through an internal Play track.

## Local containers

`docker-compose.yml` defines the API, migration job, and PostgreSQL environment.
The API waits for the migration job to finish successfully before it starts.

```bash
docker compose up --detach --build --wait
docker compose ps
docker compose down
```

To apply migrations without starting the API, or to retry a failed migration
after correcting its cause:

```bash
docker compose run --rm migrate
```

For local development without containers:

```bash
cd services/api
go run ./cmd/api migrate
go run ./cmd/api
```

## Migration operations

Migration files live in `services/api/internal/database/migrations` and are
embedded in the API image. Names use consecutive versions such as
`0001_baseline.sql`. Applied versions, names, checksums, and timestamps are
recorded in `schema_migrations`. Never edit an applied migration; add a new
forward migration instead.

The migration command takes a PostgreSQL advisory lock and applies each pending
migration in its own transaction. A failure rolls back that migration and exits
non-zero. API startup only verifies that the database is at the exact embedded
version; it never applies DDL.

Before deploying a schema change:

1. Take and verify a database backup.
2. Run the new image with `/api migrate` against staging.
3. Verify `schema_migrations` and run the smoke test with the previous API image.
4. Deploy the new API image only after compatibility is confirmed.

To inspect the recorded version:

```sql
SELECT version, name, checksum, applied_at
FROM schema_migrations
ORDER BY version;
```

There are no automatic down migrations. If a migration fails, correct the
cause and rerun it. If a committed migration causes a release problem, keep
financial records intact and ship a forward fix. Restore the verified backup
only when a forward fix cannot safely recover the environment.

## Release gates

- Unit and integration tests pass.
- Database migrations are backward compatible with the previous API image.
- The API is authenticated before domain mutation endpoints become public.
- No simulator UI or API claims a real transfer occurred.
- A rollback image and a tested database restore procedure exist.
