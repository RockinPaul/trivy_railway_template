# Trivy server on Railway

[Trivy](https://github.com/aquasecurity/trivy) in **client/server mode**: one hosted server holds
the vulnerability database so your CI jobs stop downloading 1.3 GB each. Clients send package lists
and get results back.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/trivy-server)

**There is no web interface.** This is an API endpoint for Trivy clients. Opening the domain in a
browser returns 404 by design; `/healthz` and `/version` are the only pages, and `/version` is the
useful one.

## Use it

```bash
trivy image  --server https://YOUR-DOMAIN.up.railway.app --token "$TRIVY_TOKEN" alpine:3.20
trivy fs     --server https://YOUR-DOMAIN.up.railway.app --token "$TRIVY_TOKEN" ./
trivy repo   --server https://YOUR-DOMAIN.up.railway.app --token "$TRIVY_TOKEN" https://github.com/you/repo
```

Or set `TRIVY_SERVER` and `TRIVY_TOKEN` in the environment and drop the flags. Check the server and
its database freshness with:

```bash
curl https://YOUR-DOMAIN.up.railway.app/version
```

## Service

| Service | Base | Public | Role |
|---|---|---|---|
| `trivy` | `ghcr.io/aquasecurity/trivy:0.76.1` | **yes** | The scan and cache RPC surface, plus `/healthz` and `/version`. |

One service, one volume, no database container. Upstream's image is used unmodified.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `TRIVY_TOKEN` | generated, 32 chars | The only access control on the endpoint. Clients send it as the `Trivy-Token` header. |
| `PORT` | `8080` | The port Railway's healthcheck probes and the domain targets. Leave it alone. |
| `TRIVY_CACHE_DIR` | `/data` | Baked. Vulnerability database and scan cache, on the volume. |

## What runs where

Not everything moves to the server, and that is deliberate.

| Scanner | Runs on |
|---|---|
| Vulnerability | **Server** |
| License | **Server** |
| Misconfiguration | Client |
| Secret | Client |

Clients analyse artifacts locally and upload **analysis results**, such as package lists. The
original file contents never reach the server, which is why secret scanning stays on the client.

## Security

**The token is mandatory here, and that is upstream's own instruction rather than a house rule.**
Upstream's server is optional-token because its default listen address is `localhost:4954` — there
is nothing to authenticate when nothing can reach it. Their guidance for the case this template is
in reads:

> The server listens on `localhost:4954` by default. When exposing it to other hosts, configure
> `--token` and restrict network access to trusted clients.

On a public Railway domain the second half is unavailable, so the token is the only access control
left. Upstream's check is `token != "" && token != header`, which means an empty token is not a weak
password, it is **no gate at all**. The container therefore refuses to start without one, or with
one shorter than 16 characters.

What an open server would actually cost you is worse than a free lookup. Again upstream: clients
*"can write and delete shared cache entries, affecting scans performed by other clients"*. A
stranger could poison the cache so your own pipeline reports a vulnerable image as clean. A scan
that quietly lies is worse than no scan.

Measured against a running instance:

- The scan and cache RPC surfaces return **401 `invalid token`** with no token and with a wrong one.
  A real client with a wrong token fails with `twirp error unauthenticated: invalid token`.
- `/healthz` and `/version` are unauthenticated by design, which is what lets Railway's healthcheck
  work. `/version` reveals the Trivy version and database timestamps, nothing about your scans.
- The token is passed in through the environment, never on the command line. It appears in neither
  `ps` output nor the logs.

**The honest limitation: one trust domain per deployment.** The token grants access to the scanning
*and* cache APIs with no per-client permissions and no tenant isolation. Every client you give it to
can write and delete shared cache entries. Upstream's advice is separate server instances for
mutually untrusted clients, so deploy one of these per team, not one for your whole company.

## What persists

The volume at `/data` holds the vulnerability database and the scan cache, **1.3 GB** after the
first update. Trivy takes an *exclusive lock* on it, so this service must stay at one replica; a
second server against the same cache exits with `cache may be in use by another process`.

## Timing

| | |
|---|---|
| First boot | ~8 s, and the database downloads **before** the port opens |
| Later boots | ~3 s, database reused from the volume |
| Database refresh | hourly, in the background |

The healthcheck timeout is 600 s because that first download happens before the server listens, and
your network is not mine.

## Why it is shaped this way

- **Upstream's image, unmodified.** A static Go binary that keeps all state in one cache directory,
  takes every setting from a `TRIVY_*` variable, and exits 0 on `SIGTERM`. Nothing to install.
- **`0.0.0.0:$PORT` with no relay.** Measured: a single dual-stack socket, with no separate v4
  listener, and both `127.0.0.1` and `[::1]` answering.
- **`PORT` is a real variable.** Railway probes the port it names, so the entrypoint turns it into
  `TRIVY_LISTEN`.
- **`restartPolicyType: ALWAYS`.** A clean `SIGTERM` exits `0`, which `ON_FAILURE` would not
  restart.

## Upgrading

Bump `TRIVY_VERSION` in the `Dockerfile` and push. Keep the server at or ahead of your clients'
version.

## Licences

Trivy is [Apache-2.0](https://github.com/aquasecurity/trivy/blob/main/LICENSE). The glue in this
repository is MIT.
