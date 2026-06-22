FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# 1) Stack do projeto — roda como root (apt, instaladores de sistema).
COPY install-stack.sh /tmp/install/
RUN bash /tmp/install/install-stack.sh && rm -rf /tmp/install

# 2) Claude Code (instalador nativo) — roda como o usuário final,
#    pois instala em ~/.local/bin.
USER vscode
COPY --chown=vscode:vscode install-claude.sh /tmp/install-claude.sh
RUN bash /tmp/install-claude.sh && rm -f /tmp/install-claude.sh
ENV PATH="/home/vscode/.local/bin:${PATH}"