# aptabase-railway

Wrapper image that runs [Aptabase](https://github.com/aptabase/aptabase) (self-hosted, privacy-first app analytics) on Railway
with no manual setup. It waits for Postgres, starts the app (which runs its own Postgres and ClickHouse migrations), creates the
owner account from `ADMIN_EMAIL` and one app whose ingestion key is `APTABASE_APP_KEY`, then puts nginx on Railway's `$PORT`.
nginx answers 401 to an event POST with no `App-Key` and 403 to `/api/_auth/register` unless `ALLOW_SIGNUP=true`.

Built by GitHub Actions and published to `ghcr.io/bon5co/aptabase-railway`. Used by the Railway template of the same name.
