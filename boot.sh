#!/bin/bash
# Aptabase on Railway: Postgres wait, app (migrates), owner + app bootstrap, then nginx on $PORT.
set -eu

PORT="${PORT:-8080}"
: "${PGHOST:?PGHOST is not set}" "${APTABASE_APP_KEY:?APTABASE_APP_KEY is not set}"
KEY="$(printf '%s' "$APTABASE_APP_KEY" | tr '[:lower:]' '[:upper:]')"
case "$KEY" in
  A-SH-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
  *) echo "APTABASE_APP_KEY must be A-SH- followed by 10 digits, got: $APTABASE_APP_KEY" >&2; exit 1 ;;
esac
EMAIL="$(printf '%s' "$ADMIN_EMAIL" | tr '[:upper:]' '[:lower:]')"

echo "waiting for Postgres at $PGHOST"
n=0
until pg_isready -q -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE"; do
  n=$((n+1)); [ "$n" -le 150 ] || { echo "Postgres never became ready" >&2; exit 1; }
  sleep 2
done

echo "starting Aptabase on 127.0.0.1:5000"
dotnet /app/Aptabase.dll &
APP_PID=$!

n=0
until curl -fs -o /dev/null http://127.0.0.1:5000/healthz; do
  kill -0 "$APP_PID" 2>/dev/null || { echo "Aptabase exited before it became healthy" >&2; exit 1; }
  n=$((n+1)); [ "$n" -le 300 ] || { echo "Aptabase never became healthy" >&2; exit 1; }
  sleep 2
done

# Ids are 22 characters and deterministic, so a redeploy finds the same rows and the inserts do nothing.
USER_ID="$(printf 'user:%s' "$EMAIL" | md5sum | cut -c1-22)"
APP_ID="$(printf 'app:%s' "$KEY" | md5sum | cut -c1-22)"
n=0
until psql -v ON_ERROR_STOP=1 -q \
  -v email="$EMAIL" -v uname="$ADMIN_NAME" -v uid="$USER_ID" -v aid="$APP_ID" -v akey="$KEY" -v aname="$APP_NAME" <<'SQL'
BEGIN;
INSERT INTO users (id, name, email, free_quota) VALUES (:'uid', :'uname', :'email', 20000) ON CONFLICT DO NOTHING;
INSERT INTO apps (id, owner_id, name, app_key, has_events)
  SELECT :'aid', u.id, :'aname', :'akey', false FROM users u WHERE u.email = :'email'
  ON CONFLICT DO NOTHING;
COMMIT;
SQL
do
  n=$((n+1)); [ "$n" -le 60 ] || { echo "bootstrap SQL kept failing" >&2; exit 1; }
  sleep 2
done
echo "owner $EMAIL and app key $KEY are in place"

if [ "$ALLOW_SIGNUP" = "true" ]; then
  REGISTER='proxy_pass http://127.0.0.1:5000;'
else
  REGISTER='return 403 "{\"error\":\"Sign-up is closed on this instance.\"}";'
fi
cat > /etc/nginx/nginx.conf <<CONF
worker_processes 1;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;
events { worker_connections 1024; }
http {
  access_log off;
  client_max_body_size 5m;
  default_type application/json;
  map "\$request_method:\$http_app_key" \$no_key { default 0; "POST:" 1; }
  map \$http_x_forwarded_for \$client_ip { default \$remote_addr; "~^([^,\s]+)" \$1; }
  map \$http_upgrade \$conn_up { default upgrade; "" close; }
  server {
    listen $PORT;
    listen [::]:$PORT;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$client_ip;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$conn_up;
    proxy_read_timeout 120s;
    location ~ ^/api/v0/events?\$ {
      if (\$no_key) { return 401 "{\"error\":\"Missing App-Key header.\"}"; }
      proxy_pass http://127.0.0.1:5000;
    }
    location = /api/_auth/register {
      $REGISTER
    }
    location / { proxy_pass http://127.0.0.1:5000; }
  }
}
CONF
nginx -t
nginx -g 'daemon off;' &
NGINX_PID=$!
trap 'kill "$APP_PID" "$NGINX_PID" 2>/dev/null || true' TERM INT
wait -n "$APP_PID" "$NGINX_PID" || true
echo "a child process exited, restarting the container" >&2
exit 1
