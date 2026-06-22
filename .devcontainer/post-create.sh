#!/usr/bin/env bash
# GENÉRICO — executado após a criação do container, como usuário "vscode".
# Existe apenas para o que NÃO pode ser feito no build da imagem:
# o volume do Claude só é montado em tempo de execução.
set -euo pipefail

sudo chown -R "$(id -un):$(id -gn)" "$HOME/.claude"

echo "post-create concluído."