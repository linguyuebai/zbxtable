# Docker deployment

The supported single-command Docker deployment is the release manager:

```bash
curl -fsSL https://github.com/linguyuebai/zbxtable/releases/latest/download/install-release.sh \
  | sudo bash -s -- --docker-install --port=8089
```

It checks Docker, optionally installs Docker Engine on Ubuntu/Debian, downloads
and verifies the source release, builds the embedded frontend and application,
preserves the existing `config/app.conf`, starts the container, checks the web
assets, and opens the selected port in an active UFW/firewalld firewall.
Choose another host port with `--port=PORT`.

## Compose from a source checkout

The root `docker-compose.yml` builds only the ZbxTable application. It does not
start a second MySQL server: configure `config/app.conf` to use the intended
database first. To share Zabbix's database, set the same database endpoint and
database name, and use an account with the required permissions. ZbxTable's
tables use the `zbxtable_` prefix. From inside a container, `127.0.0.1` means
the container itself; for a database on the Docker host use a reachable host
address (the compose file maps `host.docker.internal` to the host gateway on
Linux).

Build a source archive with `scripts/package-release.sh` (Linux/macOS) or
`scripts/package-release.ps1` (Windows). The archive must contain
`api/v1/web/web/index.html`; the release Dockerfile intentionally fails early
when the embedded frontend is missing.

```bash
docker compose up -d --build
docker compose logs -f zbxtable
docker compose down
```

The legacy `deployments/docker/docker.sh` and `Dockerfile` are retained for
compatibility with older releases. New deployments should use the release
manager or the root Compose file above.
