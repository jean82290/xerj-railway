# XERJ on Railway
#
# Downloads the official, pinned XERJ and Caddy release binaries from GitHub,
# checks each against a checksum pinned in this file (not one fetched next to
# it), and runs them behind a small entrypoint that adapts XERJ to Railway:
# $PORT, a volume at /data, an admin API key from a template variable, and TLS
# terminated at Railway's edge. XERJ listens on loopback only; Caddy is the
# public front door and keeps XERJ's web console off the internet.
#
# To upgrade XERJ: change XERJ_VERSION and XERJ_SHA256 together (the weekly
# GitHub Action in .github/workflows does this for you and opens a pull
# request). To upgrade Caddy: change CADDY_VERSION and CADDY_SHA512 together,
# from caddy_<version>_checksums.txt on the Caddy release page.

ARG XERJ_VERSION=1.0.0-rc.100
ARG XERJ_SHA256=4b12a47e8433e9d01d2b3f505b17b342a6e28d41edaabd274eba5a759e9cde1e
ARG CADDY_VERSION=2.11.9
ARG CADDY_SHA512=0e85544340290a16ce4bfb76fe7d65e9de1bf3a6e67f5ccfff30b30d27ea4c73e078077b7bf3e58ae60b6b12e44327705287059c775bca5782e8ee85ea7edd75

FROM debian:bookworm-slim AS fetch
ARG XERJ_VERSION
ARG XERJ_SHA256
ARG CADDY_VERSION
ARG CADDY_SHA512
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /fetch
RUN set -eu; \
    asset="xerj-${XERJ_VERSION}-x86_64-unknown-linux-musl.tar.gz"; \
    curl -fsSL --retry 3 -o "${asset}" \
      "https://github.com/xerj-org/xerj/releases/download/v${XERJ_VERSION}/${asset}"; \
    echo "${XERJ_SHA256}  ${asset}" | sha256sum -c -; \
    tar -xzf "${asset}"; \
    install -m 0755 "xerj-${XERJ_VERSION}-x86_64-unknown-linux-musl/xerj" /xerj; \
    cp "xerj-${XERJ_VERSION}-x86_64-unknown-linux-musl/LICENSE" /XERJ-LICENSE
RUN set -eu; \
    asset="caddy_${CADDY_VERSION}_linux_amd64.tar.gz"; \
    curl -fsSL --retry 3 -o "${asset}" \
      "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/${asset}"; \
    echo "${CADDY_SHA512}  ${asset}" | sha512sum -c -; \
    mkdir caddy; \
    tar -xzf "${asset}" -C caddy caddy LICENSE; \
    install -m 0755 caddy/caddy /caddy; \
    cp caddy/LICENSE /CADDY-LICENSE

FROM debian:bookworm-slim
ARG XERJ_VERSION
# ca-certificates: needed only if you switch on neural embeddings, which
# download the model from the HuggingFace Hub over HTTPS on first start.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data /usr/share/doc/xerj /usr/share/doc/caddy /etc/caddy
COPY --from=fetch /xerj /usr/local/bin/xerj
COPY --from=fetch /XERJ-LICENSE /usr/share/doc/xerj/LICENSE
COPY --from=fetch /caddy /usr/local/bin/caddy
COPY --from=fetch /CADDY-LICENSE /usr/share/doc/caddy/LICENSE
COPY NOTICE /usr/share/doc/xerj/NOTICE
COPY Caddyfile /etc/caddy/Caddyfile
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

LABEL org.opencontainers.image.title="XERJ for Railway" \
      org.opencontainers.image.description="XERJ search engine for AI agents, packaged for Railway" \
      org.opencontainers.image.version="${XERJ_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0"

ENV PORT=9200 \
    XERJ_DATA_DIR=/data \
    XERJ_EMBED_MODE=lexical \
    XERJ_LOG=info

EXPOSE 9200
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
