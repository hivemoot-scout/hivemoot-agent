# Multi-stage Dockerfile for provider-specific builds
# Reduces image size by 60% for single-provider deployments (350 MB vs 1 GB)
#
# Build modes:
#   docker build --build-arg PROVIDER=claude .     # Single provider (optimized)
#   docker build --build-arg PROVIDER=all .        # All providers (testing/flexibility)
#   docker buildx bake                             # All provider variants via Bake
#
# See docker-bake.hcl for production multi-variant builds.

ARG PROVIDER=all

# ────────────────────────────────────────────────────────────────────────────
# Stage: base
# Common system dependencies shared by all providers
# ────────────────────────────────────────────────────────────────────────────
FROM node:24-slim AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG CODEX_VERSION=latest
ARG GEMINI_VERSION=latest
ARG KILO_VERSION=latest
ARG OPENCODE_VERSION=latest
ARG CLAUDE_CODE_VERSION=latest
ARG HIVEMOOT_CLI_VERSION=latest

# Install system dependencies. gh is installed from GitHub's official apt repo
# because the Debian-packaged version is too old (2.23 vs 2.80+).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  curl \
  git \
  gpg \
  jq \
  less \
  openssh-client \
  procps \
  ripgrep \
  tini \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && apt-get purge -y gpg && apt-get autoremove -y \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/share/npm-global \
  && chown -R node:node /usr/local/share/npm-global

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV HOME=/home/node
ENV PATH=/home/node/.local/bin:/usr/local/share/npm-global/bin:${PATH}

USER node

# Install hivemoot CLI (shared across all providers)
RUN --mount=type=cache,target=/home/node/.npm,uid=1000 \
  npm install -g "@hivemoot-dev/cli@${HIVEMOOT_CLI_VERSION}"

USER root
RUN ln -sf /usr/local/share/npm-global/bin/hivemoot /usr/local/bin/hivemoot
USER node

# ────────────────────────────────────────────────────────────────────────────
# Stage: provider-codex
# OpenAI Codex CLI (~50 MB)
# ────────────────────────────────────────────────────────────────────────────
FROM base AS provider-codex

ARG CODEX_VERSION=latest
RUN --mount=type=cache,target=/home/node/.npm,uid=1000 \
  npm install -g "@openai/codex@${CODEX_VERSION}" \
  && mkdir -p /home/node/.codex

USER root
RUN ln -sf /usr/local/share/npm-global/bin/codex /usr/local/bin/codex
USER node

# ────────────────────────────────────────────────────────────────────────────
# Stage: provider-gemini
# Google Gemini CLI (~45 MB)
# ────────────────────────────────────────────────────────────────────────────
FROM base AS provider-gemini

ARG GEMINI_VERSION=latest
RUN --mount=type=cache,target=/home/node/.npm,uid=1000 \
  npm install -g "@google/gemini-cli@${GEMINI_VERSION}" \
  && mkdir -p /home/node/.gemini

USER root
RUN ln -sf /usr/local/share/npm-global/bin/gemini /usr/local/bin/gemini
USER node

# ────────────────────────────────────────────────────────────────────────────
# Stage: provider-claude
# Anthropic Claude Code native installer (~150 MB)
# ────────────────────────────────────────────────────────────────────────────
FROM base AS provider-claude

ARG CLAUDE_CODE_VERSION=latest

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Anthropic deprecated npm installation for Claude Code; use the native
# installer so we stay aligned with supported distribution. Install from a
# small temporary directory to avoid known installer OOM failures in Docker.
WORKDIR /tmp/claude-install
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_VERSION}" \
  && rm -rf /tmp/claude-install \
  && mkdir -p /home/node/.claude /home/node/.config/claude

USER root
RUN ln -sf /home/node/.local/bin/claude /usr/local/bin/claude
USER node

# ────────────────────────────────────────────────────────────────────────────
# Stage: provider-kilo
# Kilo.ai CLI (~50 MB)
# ────────────────────────────────────────────────────────────────────────────
FROM base AS provider-kilo

ARG KILO_VERSION=latest
RUN --mount=type=cache,target=/home/node/.npm,uid=1000 \
  npm install -g "@kilocode/cli@${KILO_VERSION}" \
  && mkdir -p /home/node/.config/kilo

USER root
RUN ln -sf /usr/local/share/npm-global/bin/kilo /usr/local/bin/kilo
USER node

# ────────────────────────────────────────────────────────────────────────────
# Stage: provider-opencode
# OpenCode CLI (~50 MB)
# ────────────────────────────────────────────────────────────────────────────
FROM base AS provider-opencode

ARG OPENCODE_VERSION=latest
RUN --mount=type=cache,target=/home/node/.npm,uid=1000 \
  npm install -g "opencode-ai@${OPENCODE_VERSION}" \
  && mkdir -p /home/node/.config/opencode /home/node/.local/share/opencode

USER root
RUN ln -sf /usr/local/share/npm-global/bin/opencode /usr/local/bin/opencode
USER node

# ────────────────────────────────────────────────────────────────────────────
# Stage: provider-all
# Multi-provider stage with all CLI tools (backward compatibility)
# Size: ~550 MB (base + 5 providers)
# ────────────────────────────────────────────────────────────────────────────
FROM base AS provider-all

ARG CODEX_VERSION=latest
ARG GEMINI_VERSION=latest
ARG KILO_VERSION=latest
ARG OPENCODE_VERSION=latest
ARG CLAUDE_CODE_VERSION=latest

# Install all npm-based CLIs
RUN --mount=type=cache,target=/home/node/.npm,uid=1000 \
  npm install -g \
    "@openai/codex@${CODEX_VERSION}" \
    "@google/gemini-cli@${GEMINI_VERSION}" \
    "@kilocode/cli@${KILO_VERSION}" \
    "opencode-ai@${OPENCODE_VERSION}" \
  && mkdir -p /home/node/.codex /home/node/.gemini /home/node/.config/kilo /home/node/.config/opencode /home/node/.local/share/opencode

# Install Claude native installer
WORKDIR /tmp/claude-install
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_VERSION}" \
  && rm -rf /tmp/claude-install \
  && mkdir -p /home/node/.claude /home/node/.config/claude

USER root

# Create symlinks for all providers
RUN ln -sf /usr/local/share/npm-global/bin/codex /usr/local/bin/codex \
  && ln -sf /usr/local/share/npm-global/bin/gemini /usr/local/bin/gemini \
  && ln -sf /usr/local/share/npm-global/bin/kilo /usr/local/bin/kilo \
  && ln -sf /usr/local/share/npm-global/bin/opencode /usr/local/bin/opencode \
  && ln -sf /home/node/.local/bin/claude /usr/local/bin/claude

USER node

# ────────────────────────────────────────────────────────────────────────────
# Stage: runtime
# Runtime selector based on PROVIDER build arg
# ────────────────────────────────────────────────────────────────────────────
# hadolint ignore=DL3006
FROM provider-${PROVIDER} AS runtime

WORKDIR /workspace

COPY --chown=node:node scripts /opt/hivemoot-agent/scripts
COPY --chown=node:node prompts /opt/hivemoot-agent/prompts

RUN chmod +x /opt/hivemoot-agent/scripts/*.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/hivemoot-agent/scripts/entrypoint.sh"]
