# Docker Bake configuration for provider-specific builds
# Enables optimized single-provider images (~350 MB) or multi-provider images (~1 GB)
#
# Usage:
#   docker buildx bake                          # Build all providers
#   docker buildx bake hivemoot-agent-claude    # Build Claude provider only
#   docker buildx bake --set *.platform=linux/amd64,linux/arm64  # Multi-arch
#
# See: https://docs.docker.com/build/bake/

variable "TAG" {
  default = "local"
}

variable "REGISTRY" {
  default = ""
}

variable "CODEX_VERSION" {
  default = "latest"
}

variable "GEMINI_VERSION" {
  default = "latest"
}

variable "KILO_VERSION" {
  default = "latest"
}

variable "CLAUDE_CODE_VERSION" {
  default = "latest"
}

variable "HIVEMOOT_CLI_VERSION" {
  default = "latest"
}

# Base target configuration
target "base" {
  context = "."
  dockerfile = "Dockerfile"
  platforms = ["linux/amd64"]
  args = {
    CODEX_VERSION = CODEX_VERSION
    GEMINI_VERSION = GEMINI_VERSION
    KILO_VERSION = KILO_VERSION
    CLAUDE_CODE_VERSION = CLAUDE_CODE_VERSION
    HIVEMOOT_CLI_VERSION = HIVEMOOT_CLI_VERSION
  }
}

# Provider matrix: generates targets for each provider
matrix = {
  provider = ["codex", "gemini", "claude", "kilo", "all"]
}

# Provider-specific targets
target "default" {
  name = "hivemoot-agent-${provider}"
  inherits = ["base"]
  target = "runtime"
  args = {
    PROVIDER = provider
  }
  tags = [
    notequal("", REGISTRY) ? "${REGISTRY}/hivemoot-agent:${TAG}-${provider}" : "hivemoot-agent:${TAG}-${provider}",
    notequal("", REGISTRY) && notequal("local", TAG) ? "${REGISTRY}/hivemoot-agent:${provider}" : "hivemoot-agent:${provider}"
  ]
  labels = {
    "org.opencontainers.image.title" = "Hivemoot Agent (${provider})"
    "org.opencontainers.image.description" = "Autonomous AI agent runner for ${provider} provider"
    "org.opencontainers.image.source" = "https://github.com/hivemoot/hivemoot-agent"
    "org.opencontainers.image.licenses" = "Apache-2.0"
    "hivemoot.provider" = provider
  }
}

# Default target for docker compose (claude provider)
target "compose" {
  inherits = ["base"]
  target = "runtime"
  args = {
    PROVIDER = "claude"
  }
  tags = ["hivemoot-agent:local"]
}
