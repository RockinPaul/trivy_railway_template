# Trivy vulnerability scanner in client/server mode
# https://github.com/aquasecurity/trivy
#
# Upstream's image is used unmodified. It is a static Go binary that already
# binds dual-stack, exits 0 on SIGTERM, keeps all its state in one cache
# directory, and takes every setting from a TRIVY_* environment variable — so
# nothing needs installing and nothing needs patching.
#
# The wrapper adds one thing: the server refuses to start without a token.
# Upstream's token is optional because its default listen address is loopback;
# its own guidance for an exposed server is "When exposing it to other hosts,
# configure --token and restrict network access to trusted clients." On a public
# Railway domain the network restriction is not available, which leaves the
# token as the only access control. See entrypoint.sh.
ARG TRIVY_VERSION=0.74.0
FROM ghcr.io/aquasecurity/trivy:${TRIVY_VERSION}

# TRIVY_CACHE_DIR is the whole persistence story: the vulnerability database
# (~1.3 GB) and the scan cache live here, on the volume.
#
# TRIVY_LISTEN is set by the entrypoint from PORT, because Railway's healthcheck
# probes the port named by the PORT service variable.
#
# The token is deliberately NOT given a default. An empty token disables
# authentication in upstream's code (`token != "" && token != header`), so a
# default would be the one value that must never be guessable.
ENV TRIVY_CACHE_DIR=/data \
    PORT=8080

COPY --chmod=755 entrypoint.sh /usr/local/bin/railway-entrypoint

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/railway-entrypoint"]
