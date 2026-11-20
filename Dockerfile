# Aptabase wrapper for Railway. The official image is the ASP.NET server plus the React dashboard, listens on 8080 and signs users in
# by emailed magic link only: there is no password and no default login, a fresh deploy has no user and no app, and the public
# /api/_auth/register route is open. Railway's healthcheck and edge dial the injected PORT, so nginx owns $PORT and the app listens on
# loopback behind it. The entrypoint waits for Postgres, starts the app (it runs its own Postgres and ClickHouse migrations), creates
# the owner account from ADMIN_EMAIL and one app whose ingestion key is APTABASE_APP_KEY, and only then starts nginx. nginx answers
# 401 to an event POST that carries no App-Key (the app answers 200 with an error body, which a client cannot tell from success) and
# 403 to /api/_auth/register unless ALLOW_SIGNUP=true. The sign-in link is only ever logged (no SMTP), and upstream's JSON console
# format reaches Railway's log viewer with an empty message, so the console formatter is switched to plain text. Literals a deployer should never have to type are baked in here as ENV.
#
# upstream: none aptabase/aptabase publishes no GitHub release and no git tag, only the :main image, so the pin is the :main digest
FROM ghcr.io/aptabase/aptabase:main@sha256:a8fc36774685dda96f8e511d9977dc02726c712d79ca71f0febf3d7caa2361ad

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx-light postgresql-client curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled /etc/nginx/conf.d/*

COPY --chmod=0755 boot.sh /railway-boot.sh

ENV REGION=SH \
    ADMIN_EMAIL=admin@example.com \
    ADMIN_NAME=Admin \
    APP_NAME=Aptabase \
    ALLOW_SIGNUP=false \
    ASPNETCORE_URLS=http://127.0.0.1:5000 \
    Logging__Console__FormatterName=simple \
    Logging__Console__FormatterOptions__SingleLine=true

WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["/railway-boot.sh"]
