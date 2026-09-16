# Deploy and Host Trivy Server on Railway

[Trivy](https://github.com/aquasecurity/trivy) is Aqua Security's vulnerability scanner for
containers, filesystems, repositories and more. This template runs it in **client/server mode**: one
hosted server holds the vulnerability database, and your scanners become thin clients that send
package lists and get results back.

**This is an API endpoint, not a web application.** There is no browser interface, and opening the
domain returns 404 by design. If you were looking for a dashboard, this is not it. What it gives you
is a shared database so every continuous-integration job stops downloading 1.3 GB of vulnerability
data.

## About Hosting Trivy Server

After deploying, point any Trivy client at the domain:

```
trivy image --server https://YOUR-DOMAIN.up.railway.app --token "$TRIVY_TOKEN" alpine:3.20
```

The same flags work for `trivy fs` and `trivy repo`, and both can be supplied as `TRIVY_SERVER` and
`TRIVY_TOKEN` environment variables instead. To check the server and how fresh its database is, open
`/version` in a browser.

The division of labour is deliberate. Vulnerability and license scanning run on the server;
misconfiguration and secret scanning stay on the client. Clients analyse artifacts locally and
upload only the analysis results, such as package lists, so the contents of your files never reach
the server.

Everything the server owns lives in one cache directory on the volume: the vulnerability database
and the scan cache, about 1.3 GB once populated. The first boot downloads that database before the
port opens, which takes seconds rather than minutes but explains the generous health check timeout.
Later boots reuse it and start in a few seconds. The database refreshes itself hourly in the
background.

One deployment serves one trust domain. The token grants access to the scanning and cache APIs
together, with no per-client permissions, so run one of these per team rather than one for an entire
company.

## Why Deploy Trivy Server on Railway?

- **Stop downloading the database everywhere.** One copy on one volume instead of 1.3 GB per job.
- **Faster pipelines.** Clients skip the download entirely and send a package list instead.
- **One service, no assembly.** No database container, no cache service, no second process.
- **Your artifacts stay put.** Only analysis results are uploaded, never file contents.
- **TLS without effort.** Trivy serves plain HTTP and expects a proxy in front; Railway's edge is
  that proxy.

## Common Use Cases

- A shared scanning endpoint for continuous-integration pipelines across several repositories.
- Scanning from ephemeral runners that would otherwise re-download the database on every job.
- Air-gapped or bandwidth-constrained runners that can reach one internal endpoint but should not
  pull large artifacts.
- Keeping every team on one consistent, centrally updated vulnerability database rather than
  whatever each runner last cached.
- A stable scanning target for local development, so laptops do not each hold a copy.

## Dependencies for Trivy Server Hosting

- Nothing. No database, no cache service, no external accounts.
- On the client side, any Trivy build that supports `--server`, which is every current release.

### Deployment Dependencies

- Upstream project: [aquasecurity/trivy](https://github.com/aquasecurity/trivy) (Apache-2.0), image
  `ghcr.io/aquasecurity/trivy:0.74.0`.
- Upstream documentation:
  [client/server mode](https://github.com/aquasecurity/trivy/blob/main/docs/guide/references/modes/client-server.md).
- Template source:
  [RockinPaul/trivy_railway_template](https://github.com/RockinPaul/trivy_railway_template) (MIT).

### Implementation Details

**After deploying:** copy `TRIVY_TOKEN` from the service's Variables tab and pass it to your clients
as `--token` or `TRIVY_TOKEN`. Confirm the server is up by opening `/version`.

**Why the token is mandatory.** Trivy's token is optional upstream, and that is correct for how it
ships: the default listen address is `localhost:4954`, so there is nothing to authenticate because
nothing can reach it. Upstream's guidance for the situation this template creates is explicit, that
when exposing the server to other hosts you should configure a token and restrict network access to
trusted clients. On a public domain the network restriction is not available, which leaves the token
as the only access control in the design. Upstream's check treats an empty token as "allow
everything", so an unset token is not a weak password but no gate at all. The container refuses to
start without one, or with one shorter than 16 characters.

The cost of getting this wrong is higher than an unauthorised lookup. Upstream notes that clients
can write and delete shared cache entries, affecting scans performed by other clients, so an open
server would let a stranger poison the cache until your own pipeline called a vulnerable image
clean.

**Security.** Measured against a running instance: the scanning and cache endpoints return 401 with
no token and with a wrong one, and a real client with a wrong token fails immediately. The health
and version endpoints are deliberately unauthenticated, which is what lets the platform health check
work; the version endpoint reveals the Trivy release and database timestamps and nothing about your
scans. The token is supplied through the environment rather than the command line, so it appears in
neither the process table nor the logs.

**Notes.** `PORT` is 8080 and the entrypoint turns it into the server's listen address. Health is
`/healthz`. Trivy takes an exclusive lock on its cache, so keep this service at a single replica.
Keep the server at or ahead of your clients' Trivy version when you bump `TRIVY_VERSION`.

## Licences

Trivy is Apache-2.0. The template's glue is MIT.
