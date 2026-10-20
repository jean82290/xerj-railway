# XERJ on Railway
#
# Downloads the official, pinned XERJ release binary from GitHub, checks it
# against a SHA-256 pinned in this file (not one fetched next to it), and runs
# it behind a small entrypoint that adapts it to Railway: $PORT, a volume at
# /data, an admin API key from a template variable, and TLS terminated at
# Railway's edge.
#
# To upgrade: change XERJ_VERSION and XERJ_SHA256 together (the weekly GitHub
# Action in .github/workflows does this for you and opens a pull request).

ARG XERJ_VERSION=1.0.0-rc.97
ARG XERJ_SHA256=f401da4dfc2e5c7dd27580d3896229baa088c598c77735266888669240149a00

FROM debian:bookworm-slim AS fetch
ARG XERJ_VERSION
ARG XERJ_SHA256
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

FROM debian:bookworm-slim
ARG XERJ_VERSION
# ca-certificates: needed only if you switch on neural embeddings, which
# download the model from the HuggingFace Hub over HTTPS on first start.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data /usr/share/doc/xerj
COPY --from=fetch /xerj /usr/local/bin/xerj
COPY --from=fetch /XERJ-LICENSE /usr/share/doc/xerj/LICENSE
COPY NOTICE /usr/share/doc/xerj/NOTICE
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
