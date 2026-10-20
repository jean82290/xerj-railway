# Text for the Railway template form

Copy each block into the matching field when you publish the template.

---

## Name

```
XERJ | Elasticsearch-Compatible Search & Memory for AI Agents
```

## Short description

```
Search, vector kNN and agent memory in one Rust binary, ES-compatible.
```

## Category

```
AI/ML
```

## Overview (Markdown)

```markdown
# Deploy and Host XERJ on Railway

XERJ is an open-source search engine built for AI agents, shipped as a single Rust binary. It speaks the Elasticsearch 8.x REST API, so existing Elasticsearch clients connect unchanged, and it adds semantic search, kNN vector search, hybrid retrieval and namespaced long-term memory, with no JVM and no separate vector database.

## About Hosting XERJ

This template runs the official XERJ release, pinned by version and SHA-256, as one service with a Railway volume at `/data` for indices and the write-ahead log. Railway serves it over HTTPS and routes the public domain to the Elasticsearch-compatible API.

Three things a bare XERJ deploy gets wrong on Railway, handled here:

- **It would be unreachable.** XERJ binds to loopback by default. The template binds `0.0.0.0` and declares that TLS is terminated at Railway's edge, which XERJ requires before listening on a network address. API-key authentication stays on.
- **You would be locked out.** XERJ writes its admin key to a file on first boot and never prints it. The template generates the key as the `XERJ_ADMIN_KEY` variable and hands it to XERJ, so it is in your Variables tab immediately. Change it and redeploy to rotate.
- **It would ignore `$PORT`.** Ports live in XERJ's TOML config; the entrypoint writes it on every boot.

The health check uses `/health/ready`, the one endpoint that answers without a key. Shutdown is graceful: Railway's stop signal reaches XERJ directly, which flushes to the volume before exiting.

## Common Use Cases

- A retrieval backend (RAG) for an AI app: full-text, semantic and hybrid search over your documents
- Long-term memory for agents over plain HTTP: store and recall facts per namespace
- A lightweight Elasticsearch-compatible API for apps already written against Elasticsearch clients
- A remote search and memory server for Claude Code, Cursor or any MCP client, through `xerj mcp`

## Dependencies for XERJ Hosting

- XERJ (official release binary from github.com/xerj-org/xerj, Apache-2.0)
- A Railway volume mounted at `/data`

### Deployment Dependencies

- XERJ repository: https://github.com/xerj-org/xerj
- XERJ documentation: https://xerj.org/docs/
- Agent-oriented reference and caveats: https://xerj.org/llms.txt

### Implementation Details

Connect from another service in the same project over the private network:

    XERJ_URL=http://${{xerj.RAILWAY_PRIVATE_DOMAIN}}:${{xerj.PORT}}
    XERJ_API_KEY=${{xerj.XERJ_ADMIN_KEY}}

Every request carries `Authorization: ApiKey <XERJ_ADMIN_KEY>`. The default embedding mode is lexical; set `XERJ_EMBED_MODE=neural` before indexing for the built-in MiniLM model (about 90 MB, downloaded once into the volume).

This is a community-maintained template, not affiliated with the XERJ project.

## Why Deploy XERJ on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying XERJ on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
```

## Service settings to enter in the template composer

| Setting | Value |
|---|---|
| Service name | `xerj` |
| Source | your GitHub repository (this one) |
| Volume mount path | `/data` |
| Public networking | HTTP, target port `9200` |
| Healthcheck path | `/health/ready` |
| Restart policy | On failure |

| Variable | Value |
|---|---|
| `XERJ_ADMIN_KEY` | `${{secret(64, "abcdef0123456789")}}` |
| `PORT` | `9200` |
| `XERJ_EMBED_MODE` | `lexical` |
