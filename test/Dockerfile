# Dockerfile for testing claude-settings-sync plugin
# Usage:
#   docker build -t claude-sync-test ./test
#   docker run -it --rm -v $(pwd)/scripts:/plugin/scripts:ro claude-sync-test

FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    xz-utils \
    git \
    tar \
    && rm -rf /var/lib/apt/lists/*

# Simulate Claude Code installation (minimal structure)
RUN mkdir -p /root/.claude/commands \
    && mkdir -p /root/.claude/skills \
    && mkdir -p /root/.claude/agents \
    && mkdir -p /root/.claude/plugins/marketplaces/claude-settings-sync \
    && echo '{}' > /root/.claude/settings.json \
    && echo '# Test CLAUDE.md from Docker' > /root/.claude/CLAUDE.md

# Add test content
RUN echo '---\nname: test\n---\nTest command' > /root/.claude/commands/test.md \
    && echo '{"test": true}' > /root/.claude/settings.local.json

WORKDIR /root

# Copy test scripts
COPY test-install.sh test-all-features.sh test-corner-cases.sh /root/
RUN chmod +x /root/*.sh

# Default: interactive shell
CMD ["/bin/bash"]
