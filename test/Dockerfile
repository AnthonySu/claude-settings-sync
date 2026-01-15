# Dockerfile for testing claude-settings-sync plugin installation
# Usage:
#   docker build -t claude-sync-test ./test
#   docker run -it --rm claude-sync-test

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
    && echo '{}' > /root/.claude/settings.json \
    && echo '# Test CLAUDE.md' > /root/.claude/CLAUDE.md

# Add some test commands to simulate existing setup
RUN echo '---\nname: test\n---\nTest command' > /root/.claude/commands/test.md

WORKDIR /root

# Copy test scripts
COPY test-install.sh /root/test-install.sh
COPY test-all-features.sh /root/test-all-features.sh
RUN chmod +x /root/test-install.sh /root/test-all-features.sh

# Default: interactive shell
CMD ["/bin/bash"]
