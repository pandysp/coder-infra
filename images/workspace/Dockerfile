# Custom workspace image for Coder
# Extends enterprise-base with developer tools, version managers, and package managers.
# Runtimes (Node, Python, Go) are NOT baked in — managed by mise at workspace start
# and cached in the persistent /home/coder volume.
#
# Build: docker build -t coder-workspace images/workspace/
# Push:  docker push ghcr.io/pandysp/coder-workspace:latest

FROM codercom/enterprise-base@sha256:5abfb835c2421f89d5a30fe42bfa369de91222f3e13145172448d9fd173676de

# ── Layer 1: Docker CLI (large, rarely changes) ──────────────────
RUN curl -fsSL https://get.docker.com | sh

# ── Layer 2: Tailscale client (medium, rarely changes) ───────────
RUN curl -fsSL https://tailscale.com/install.sh | sh

# ── Layer 3: GitHub CLI apt repo + system packages ───────────────
# gh from official repo (Ubuntu's default is ancient)
# fd-find installs as fdfind — symlink to fd for convenience
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt-get update -qq \
    && sudo apt-get install -y -qq --no-install-recommends \
      jq htop tree nano tmux direnv make \
      ripgrep fd-find gh \
      bash-completion \
    && sudo ln -sf "$(which fdfind)" /usr/local/bin/fd \
    && sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*

# ── Layer 3b: git-lfs (separate — post-install script fails under QEMU)
RUN sudo apt-get update -qq \
    && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends git-lfs \
    || (sudo dpkg --configure -a && sudo apt-get install -y -qq git-lfs) \
    && sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*

# ── Layer 4: yq (pinned version — not in Ubuntu repos) ───────────
ARG YQ_VERSION=v4.52.5
RUN sudo curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_$(dpkg --print-architecture)" \
      -o /usr/local/bin/yq \
    && sudo chmod +x /usr/local/bin/yq

# ── Layer 5: Developer tools (mise, uv, pnpm) ───────────────────
ENV SHELL="/bin/bash"
RUN curl https://mise.run | sh \
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && curl -fsSL https://get.pnpm.io/install.sh | sh -

# ── PATH (explicit — works in non-interactive contexts) ──────────
ENV PATH="/home/coder/.local/bin:/home/coder/.local/share/pnpm:$PATH"
ENV MISE_PYTHON_COMPILE="0"
