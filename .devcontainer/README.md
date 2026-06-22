# Template de Dev Container

Ambiente isolado com **Claude Code** pré-instalado (login via navegador, plano Pro) e a stack do projeto instalada por shell script.

## Trocando de stack (Python, Java, Angular, etc.)

Edite apenas **2 arquivos**:

1. **`.devcontainer/install-stack.sh`** — instala a stack (roda no build da imagem, como root). Exemplos:
   - **Python**: `apt-get install -y python3 python3-pip python3-venv python-is-python3`
   - **Java**: `apt-get install -y openjdk-21-jdk maven`
   - **PHP**: `apt-get install -y php-cli composer`
   - **Angular**: Node via NodeSource + `npm install -g @angular/cli` (versão atual deste repo)
2. **`.vscode/extensions.json`** — extensões recomendadas da stack (instalação manual, com 1 clique na notificação do VS Code).

Os demais arquivos **não mudam** entre projetos.

## Como funciona

| Arquivo | Papel | Quando roda |
|---|---|---|
| `.devcontainer/devcontainer.json` | Genérico: build, volume do Claude, extensão do Claude | — |
| `.devcontainer/Dockerfile` | Genérico: orquestra os scripts em 2 fases (root → vscode) | build |
| `.devcontainer/install-stack.sh` | **Específico**: instala a stack | build (root) |
| `.devcontainer/install-claude.sh` | Genérico: Claude Code via instalador nativo (`~/.local/bin`) | build (vscode) |
| `.devcontainer/post-create.sh` | Genérico: `chown` do volume `~/.claude` (só possível em runtime) | pós-criação |
| `.vscode/extensions.json` | **Específico**: extensões da stack | abertura do workspace |

## Detalhes importantes

- **Login do Claude**: na 1ª abertura, rode `claude` no terminal e logue pelo navegador. O volume nomeado (`claude-code-config-<id>`) persiste o login entre rebuilds; cada projeto tem volume próprio (1 login por projeto).
- **Atualizações do Claude**: a imagem congela a versão do dia do build; em runtime o Claude se auto-atualiza sozinho. Para o build partir do mais novo: "Rebuild Without Cache".
- **Cache**: editar `install-stack.sh` invalida a camada e refaz a instalação no próximo rebuild; sem edição, rebuilds são rápidos.
- **Imagem base**: `base:ubuntu-24.04` (pinada — a tag flutuante `ubuntu` muda as versões do apt sem aviso).
- **Regra de ouro**: instalação que depende de root/apt → `install-stack.sh` (build); operação que depende do container rodando (volumes) → `post-create.sh`.
