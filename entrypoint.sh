#!/bin/sh
set -eu

LISTEN_PORT="${PORT:-8080}"

# ---------------------------------------------------------------------------
# Fail closed without a token
# ---------------------------------------------------------------------------
# Trivy's token is optional, and that is correct for how upstream ships: the
# default listen address is `localhost:4954`, so the server is not reachable
# and there is nothing to authenticate. Upstream's guidance for the case this
# template is in is explicit:
#
#   "The server listens on localhost:4954 by default. When exposing it to other
#    hosts, configure --token and restrict network access to trusted clients."
#
# On a public Railway domain the second half of that sentence is unavailable —
# the edge is open to the internet — which leaves the token as the only access
# control in the design. An empty token is not "no password", it is no gate at
# all: upstream's check is `token != "" && token != header`, so an unset token
# makes every request authorised.
#
# That matters more than a free vulnerability lookup would. Upstream again:
# clients "can write and delete shared cache entries, affecting scans performed
# by other clients". An open server lets a stranger poison the cache so that a
# deployment's own pipeline reports a vulnerable image as clean. A scan that
# quietly lies is worse than no scan.
if [ -z "${TRIVY_TOKEN:-}" ]; then
    echo "FATAL: TRIVY_TOKEN is empty." >&2
    echo "  Trivy treats an empty token as 'no authentication', and this server" >&2
    echo "  is reachable from a public domain. Anyone could then read results" >&2
    echo "  and, worse, write or delete shared cache entries that your own" >&2
    echo "  scans depend on. The template generates a token; read it from the" >&2
    echo "  service variables." >&2
    exit 1
fi
if [ "$(printf '%s' "${TRIVY_TOKEN}" | wc -c)" -lt 16 ]; then
    echo "FATAL: TRIVY_TOKEN is shorter than 16 characters." >&2
    echo "  It is the only access control on a public endpoint. The template" >&2
    echo "  generates a 32-character value." >&2
    exit 1
fi

# Trivy takes an EXCLUSIVE lock on its cache directory: a second server on the
# same cache exits with "cache may be in use by another process". That is fine
# here — one service, one volume — but it means this service must not be scaled
# to multiple replicas, and it is why the note exists rather than being
# discovered during an outage.
mkdir -p "${TRIVY_CACHE_DIR:-/data}"

# Every setting goes in through the environment rather than the command line,
# so the token never appears in the process table. Verified: `ps` inside the
# container shows only `trivy server`.
#
# 0.0.0.0 is upstream's documented form for accepting outside connections.
# Measured: it produces a single dual-stack socket ([::]:PORT in /proc/net/tcp6,
# no separate v4 listener) and both 127.0.0.1 and [::1] answer, so Railway's
# edge and the IPv6-only private network are served without a relay.
export TRIVY_LISTEN="0.0.0.0:${LISTEN_PORT}"

echo "trivy: cache at ${TRIVY_CACHE_DIR:-/data}, serving on :${LISTEN_PORT} with token auth"
echo "trivy: the vulnerability database downloads before the port opens; first boot takes longer"

exec trivy server "$@"
