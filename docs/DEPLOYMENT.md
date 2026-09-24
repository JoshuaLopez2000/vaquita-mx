# Remote deployment

## Target shape

The first production-like environment can run on a managed container host with a managed PostgreSQL database:

```text
Android app -> HTTPS ingress -> Go API container -> managed PostgreSQL
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
3. Run schema migrations as a one-off release job.
4. Deploy the API with a non-root runtime, health probe `/healthz`, and HTTPS ingress.
5. Restrict database networking to the API environment.
6. Configure logs, error alerts, CPU/memory limits, and uptime checks.
7. Set the Flutter build's `API_BASE_URL` to the HTTPS API origin.
8. Run smoke tests, then distribute through an internal Play track.

## Local containers

`docker-compose.yml` defines the API and PostgreSQL environment. It has been built and smoke-tested locally with Docker Desktop: PostgreSQL reached its healthy state, the API health endpoint responded, and the simulated provider created an MXN payment request.

```bash
docker compose up --detach --build --wait
docker compose ps
docker compose down
```

## Release gates

- Unit and integration tests pass.
- Database migrations are backward compatible with the previous API image.
- The API is authenticated before domain mutation endpoints become public.
- No simulator UI or API claims a real transfer occurred.
- A rollback image and a tested database restore procedure exist.
