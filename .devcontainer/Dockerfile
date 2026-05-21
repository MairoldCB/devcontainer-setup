FROM debian:13.4-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    zsh \
    sudo \
    iptables \
    ipset \
    aggregate \
    dnsutils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create the `dev` user (with its own home + sudo group membership).
RUN groupadd --gid 1001 dev \
    && useradd --uid 1001 --gid dev --create-home --shell /bin/zsh dev

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh
#Do not auto update claude code
ENV DISABLE_AUTOUPDATER=1
#Nicer looking terminal
ENV COLORTERM=truecolor

# Workaround for OrbStack/Docker Desktop "fakeowner" bind-mount filesystems:
# git's stat cache misinterprets inode/ctime changes and falsely reports unmodified
# files as dirty during rebase/merge. Disabling ctime trust and using a minimal
# stat comparison avoids "local changes would be overwritten" errors on clean trees.
RUN git config --global core.checkStat minimal && \
  git config --global core.trustctime false

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
COPY allowed-domains.conf /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "dev ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/init-firewall && \
  chmod 0440 /etc/sudoers.d/init-firewall

WORKDIR /workspace
