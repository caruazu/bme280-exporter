#!/usr/bin/env bash
# GENÉRICO — instala o Claude Code via instalador nativo (sem Node/npm).
# Executado no build da imagem, como usuário "vscode".
set -euo pipefail

curl -fsSL https://claude.ai/install.sh | bash

"$HOME/.local/bin/claude" --version