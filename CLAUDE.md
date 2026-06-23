# CLAUDE.md — bme280-exporter

Documentação de contexto para o Claude Code. Leia inteiro antes de qualquer tarefa.


## O que este projeto faz

Exporta leituras do sensor BME280 (temperatura, pressão, umidade) para o Prometheus via **textfile collector do node_exporter**. O sensor fica dentro de uma caixa hermética junto com um Raspberry Pi 4 — o objetivo real é monitorar **umidade interna da caixa**.


## Estágio atual do código

O binário em `src/hello-world.c` é um **stub de validação** — ele não lê sensor nenhum. Apenas escreve um arquivo `bme280_dummy.prom` com valores zerados no diretório configurado via `TEXTFILE_DIR`. O objetivo é validar toda a esteira (empacotamento, systemd, permissões, CI) **antes** de implementar o leitor real do BME280.

O arquivo de saída do stub é `bme280_dummy.prom`; o leitor real usará `bme280.prom`.


## Identidade do mantenedor

| Campo | Valor |
|||
| Nome | Gustavo Caruazu |
| E-mail | gustavo@caruazu.com |

Esse e-mail deve constar em `debian/changelog` e `debian/control`.


## Alvo de deploy

| Campo | Valor |
|||
| Hardware | Raspberry Pi 4 Model B Rev 1.4 |
| SO | Debian GNU/Linux 13 (trixie) |
| Kernel | 6.18 (`rpt-rpi-v8`), `aarch64` |
| Arquivo de boot | `/boot/firmware/config.txt` |
| I²C | já habilitado (`dtparam=i2c_arm=on`), `/dev/i2c-1` presente |
| Sensor | BME280 legítimo (chip id `0x60`), barramento `i2c-1`, endereço `0x76` |
| Posição | dentro de caixa hermética com o Pi |


## Ambiente de desenvolvimento (devcontainer)

**Imagem base:** `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`  
**Usuário:** `vscode`  
**Arquitetura do container:** `arm64 / aarch64` (forçada via `--platform=linux/arm64` em `devcontainer.json`)

> **Mudança importante:** o devcontainer agora roda em **arm64**, a mesma arquitetura do alvo. A compilação é **nativa** — o `gcc` padrão já gera binário aarch64. **Não há mais cross-compilação**: o `install-stack.sh` não instala mais `crossbuild-essential-arm64` nem `libc6-*-cross`. Como a arquitetura bate com a do alvo, o binário do stub também **roda no próprio devcontainer**.

> **Nota sobre `gcc-aarch64-linux-gnu`/`binutils-aarch64-linux-gnu`:** num sistema arm64 nativo, o triplet do host *é* `aarch64-linux-gnu`, então o pacote `gcc` **depende** desses dois — eles permanecem instalados (marcados `auto`, não removidos por `apt autoremove`). **Não são leftover de cross-compilação**: fazem parte do toolchain nativo. Por isso não estão listados como ferramentas "instaladas pelo projeto" abaixo.

### Ferramentas instaladas

| Ferramenta | Versão |
|||
| gcc (aarch64) | 13.3.0 |
| g++ | 13.3.0 |
| gdb | instalado |
| cmake | 3.28.3 |
| make | 4.3 |
| valgrind | instalado |
| libc6-dev (arm64) | 2.39 |
| build-essential | instalado |
| claude (CLI) | auto-atualizado em runtime |
| dpkg / dpkg-buildpackage | 1.22.6 |
| debhelper (`dh`) | 13.14.1 |
| fakeroot | 1.33 |
| lintian | 2.117.0 |
| devscripts | 2.23.7 |

### Restrição do devcontainer

O diretório pai `/workspaces/` pertence a `root:root` e **não é gravável pelo usuário `vscode`**. Isso impede o uso de `dpkg-buildpackage` diretamente (ele grava `.deb`, `.buildinfo` e `.changes` em `..`). O comando correto no devcontainer está descrito na seção "Convenção de build".

### Volume persistente do Claude

`claude-code-config-<devcontainerId>` montado em `~/.claude` — persiste login e config entre rebuilds.


## Ambientes (Dev / Homologação / Produção)

Todos os três ambientes são **arm64 (aarch64)** — por isso o build é nativo de ponta a ponta.

| Ambiente | Máquina | Para quê |
|---|---|---|
| **Dev** | devcontainer arm64 (no notebook) | editar, compilar, empacotar, inspecionar **e rodar o stub** |
| **Homologação** | VM A1 arm64 com Debian 13 (trixie) | testar o `.deb` de verdade: systemd, sysusers, tmpfiles, ciclo install→enable→remove→purge |
| **Produção** | Raspberry Pi 4 | sensor real (IIO/BME280), deploy final |

O devcontainer cobre build + inspeção estática + execução do binário. A validação de **systemd/dpkg** acontece na **VM A1** (o container não roda systemd como PID 1). O **Pi** fica para o sensor real. Detalhes passo a passo em `TEST.md`.


## Arquitetura (decisões fechadas — não questionar)

### Driver do sensor: kernel / IIO
- Usar driver mainline `bmp280` via device-tree overlay `dtoverlay=i2c-sensor,bme280`.
- O kernel faz a compensação de temperatura/pressão/umidade.
- O sensor aparece em `/sys/bus/iio/devices/iio:deviceN/`.
- **NÃO** usar API C da Bosch. **NÃO** escrever driver em userspace.
- Resolver o device pelo atributo `name == bme280` — **não chumar `iio:device0`**.

### Leitor em C
- C11, binário único, linka apenas a libc (sem bibliotecas externas).
- Compilado com flags de hardening (ver seção abaixo).
- Lê o `/sys`, escala unidades, grava o `.prom`.
- Compilado **nativamente** para `aarch64` (devcontainer, VM e Pi são todos arm64).

### Modelo de execução: oneshot via systemd
- O leitor é **processo de execução curta**: acorda, roda uma vez, encerra.
- **Não é daemon. Não tem loop de sleep interno.**
- Gerenciado por um `systemd.timer` que dispara o `systemd.service`.
- Minimiza pegada de memória; combina com o modo forçado do BME280.

### Integração com Prometheus
- O leitor grava em `/var/lib/node_exporter/textfile_collector/bme280.prom` (caminho configurável via `TEXTFILE_DIR`).
- O node_exporter republica via `--collector.textfile.directory`.
- **Não editar nem configurar o node_exporter** — está fora do escopo.
- **Contrato entre projetos:** o caminho do diretório textfile.

### Empacotamento Debian declarativo
- Pacote `.deb` construído com `debhelper` compat 13.
- Ciclo de vida (instalar, habilitar, remover, purgar) é do `dpkg/apt`.
- Habilitação/criação de recursos é declarada via:
  - `sysusers.d` → cria usuário dedicado
  - `tmpfiles.d` → cria diretório de saída
  - seção `[Install]` das units
- O debhelper (`dh_installsystemd`, `dh_installtmpfiles`, `dh_installsysusers`) gera a lógica nos maintainer scripts.
- **Não escrever `install.sh`/`uninstall.sh` procedurais.**

### Habilitação do kernel: passo separado
- O overlay `dtoverlay=i2c-sensor,bme280` vai em `/boot/firmware/config.txt`.
- Isso é feito pelo script `kernel-setup.sh` — **fora do pacote**.
- O pacote **não edita config de boot e não reinicia**.

### Lógica de alerta
- **Toda lógica de limiar vive no Prometheus de outro projeto** (alerting rules).
- O leitor é "burro": só reporta valores e um sinal de saúde (`bme280_up`).


## Política de binários

Todo artefato compilado (binários, `.deb`, `.o`) deve ser gerado em `bin/`. O `.gitignore` exclui todo o conteúdo de `bin/*` mas rastreia `bin/.gitkeep` para que o diretório exista após um `git clone`. Nunca commitar binários.


## Restrições absolutas (não fazer)

- **NÃO** usar API C da Bosch nem driver userspace.
- **NÃO** transformar o leitor em daemon nem incluir loop de sleep.
- **NÃO** escrever `install.sh`/`uninstall.sh` para o programa.
- **NÃO** colocar habilitação do overlay dentro do pacote Debian.
- **NÃO** configurar ou editar o node_exporter.
- **NÃO** reiniciar a máquina automaticamente — apenas perguntar ao usuário.
- **NÃO** apagar o diretório `/var/lib/node_exporter/textfile_collector/` no purge — apenas o arquivo `bme280.prom`.
- **NÃO** chumar `iio:device0` diretamente — resolver pelo `name`.
- **NÃO** colocar lógica de alerta (ex.: `> 60%`) no leitor.
- **NÃO** usar `dpkg-buildpackage` diretamente no devcontainer — usar `fakeroot debian/rules` (ver seção abaixo).


## Métricas exportadas (formato Prometheus)

```
# HELP bme280_temperature_celsius Temperatura em graus Celsius
# TYPE bme280_temperature_celsius gauge
bme280_temperature_celsius 27.43

# HELP bme280_humidity_percent Umidade relativa em %
# TYPE bme280_humidity_percent gauge
bme280_humidity_percent 58.12

# HELP bme280_pressure_hpa Pressão atmosférica em hPa
# TYPE bme280_pressure_hpa gauge
bme280_pressure_hpa 1013.25

# HELP bme280_up 1 se a leitura foi bem-sucedida, 0 caso contrário
# TYPE bme280_up gauge
bme280_up 1
```


## Caminhos relevantes no alvo (Raspberry Pi)

| Caminho | Descrição |
|||
| `/sys/bus/iio/devices/iio:deviceN/` | Entradas do sensor via IIO |
| `/sys/bus/iio/devices/iio:deviceN/name` | Deve conter `bme280` |
| `/sys/bus/iio/devices/iio:deviceN/in_temp_input` | Temperatura (milligraus C) |
| `/sys/bus/iio/devices/iio:deviceN/in_humidityrelative_input` | Umidade (milli-%) |
| `/sys/bus/iio/devices/iio:deviceN/in_pressure_input` | Pressão (kPa, 3 decimais) |
| `/var/lib/node_exporter/textfile_collector/bme280.prom` | Saída para o Prometheus |
| `/boot/firmware/config.txt` | Config de boot do Pi |


## Usuário e permissões (no alvo)

- Usuário dedicado: `bme280-reader` (sem shell, sem home), criado via `sysusers.d`.
- Pertence ao grupo `i2c` (para acesso ao `/dev/i2c-1`, necessário no leitor real — ainda não configurado no stub).
- Acesso de escrita ao diretório textfile via `tmpfiles.d`.


## Flags de hardening para compilação C

```makefile
CFLAGS = -std=c11 -Wall -Wextra -Wpedantic \
         -D_FORTIFY_SOURCE=2 -fstack-protector-strong \
         -fPIE -pie \
         -O2
LDFLAGS = -Wl,-z,relro -Wl,-z,now
```

O `CC` fica no padrão (`gcc`). Como o devcontainer é arm64, o `gcc` nativo já emite aarch64 — **sem cross-compiler, sem `DEB_HOST_GNU_TYPE`, sem `architecture.mk`**.


## Estrutura debian/ existente

| Arquivo | Gerado por | Destino no pacote |
|||---|
| `debian/control` | manual | metadados do pacote |
| `debian/changelog` | manual | versão, maintainer |
| `debian/rules` | manual | lógica de build |
| `debian/source/format` | manual | `3.0 (native)` |
| `debian/bme280-reader.install` | manual | `bin/bme280-reader → usr/bin/` |
| `debian/bme280-reader.service` | manual | `usr/lib/systemd/system/` |
| `debian/bme280-reader.timer` | manual | `usr/lib/systemd/system/` |
| `debian/bme280-reader.sysusers` | manual | `usr/lib/sysusers.d/bme280-reader.conf` |
| `debian/bme280-reader.tmpfiles` | manual | `usr/lib/tmpfiles.d/bme280-reader.conf` |

O `debian/rules` usa compat 13 com as seguintes particularidades:

```makefile
%:
    dh $@ --with=installsysusers       # necessário no compat 13 (auto só no 14)

override_dh_auto_install:              # Makefile não tem target install

override_dh_install:
    dh_install --sourcedir=.           # lê bin/ diretamente, sem debian/tmp

override_dh_builddeb:
    dh_builddeb --destdir=bin          # saída em bin/ (pai não-gravável no devcontainer)
```

> Build nativo: o `CC` fica no padrão (`gcc`) e o `dh_shlibdeps` usa o multiarch do sistema (`/usr/lib/aarch64-linux-gnu`). Por isso **caíram** o `include architecture.mk`, o `export CC := …-gcc` e o `override_dh_shlibdeps` que existiam na versão cross.


## Gotchas de empacotamento (lições aprendidas)

| Problema | Causa | Solução |
|||---|
| `dh_installsysusers` não instala nada | no compat 13 não está na sequência padrão | `dh $@ --with=installsysusers` em `debian/rules` |
| `dpkg-buildpackage` falha com "Permission denied" | `/workspaces/` é `root:root`, não gravável | usar `fakeroot debian/rules clean && fakeroot debian/rules binary` |
| `dh binary` pula o `dh_auto_build` | `debian/debhelper-build-stamp` de build anterior persiste | sempre executar `debian/rules clean` antes de `binary` |

> Os gotchas de cross-compilação (overrides de `dh_shlibdeps`, `dpkg-architecture -aarm64`, `export $(…)`) **deixaram de existir** com o build nativo arm64.


## Convenção de build do pacote

**No devcontainer** (único jeito que funciona — `dpkg-buildpackage` não grava em `/workspaces/`):

```bash
# Limpa estado anterior e empacota (build nativo arm64)
fakeroot debian/rules clean
fakeroot debian/rules binary
```

Ou simplesmente `make deb`, que roda esse mesmo par. O `.deb` gerado fica em `bin/bme280-reader_<versão>_arm64.deb`.

**No CI (GitHub Actions)** — roda em runner arm64 nativo (`ubuntu-24.04-arm`) e usa o mesmo par de comandos por consistência.


## CI/CD — GitHub Actions

Workflow: `.github/workflows/build-deb.yml`

- **Trigger:** somente `workflow_dispatch` (manual via GitHub UI)
- **Runner:** `ubuntu-24.04-arm` (arm64 nativo — sem cross-compilação)
- **Passos:** instala toolchain (`build-essential`, `debhelper`, `fakeroot`, `lintian`) → build nativo → `dpkg-deb --info/--contents` → lintian (informacional) → upload artifact
- **Artifact:** `bme280-reader-arm64`, retido por 30 dias
- **Releases:** ainda não configuradas — fase atual é validação via artifact

Para disparar: **Actions → build-deb → Run workflow**.

O artifact é um `.zip` baixado pela UI do GitHub. Para instalar no Pi: extraia o `.zip`, copie o `.deb` via `scp` e instale com `sudo apt install ./bme280-reader_*.deb`.


## Fluxo de deploy manual (resumo)

1. **Dev (devcontainer):** `make deb` → gera `.deb` em `bin/`; opcionalmente rodar o stub localmente (`TEXTFILE_DIR=/tmp/tc ./bin/bme280-reader`)
2. **Homologação (VM A1):** `scp` o `.deb` para a VM e validar o ciclo completo `apt install → enable → remove → purge` com systemd real (ver `TEST.md`, Parte 3)
3. **Copiar** o `.deb` para o Pi (`scp bin/bme280-reader_*.deb pi@<IP>:~`)
4. **No Pi:** `sudo bash kernel-setup.sh` → edita `/boot/firmware/config.txt` e pede reboot
5. **Reboot** do Pi (manual)
6. **No Pi:** `sudo apt install ./bme280-reader_*.deb`
7. **Verificar:**
   ```bash
   id bme280-reader
   ls /var/lib/node_exporter/textfile_collector/
   systemctl status bme280-reader.timer
   sudo systemctl start bme280-reader.service
   cat /var/lib/node_exporter/textfile_collector/bme280_dummy.prom
   journalctl -u bme280-reader.service -n 20 --no-pager
   ```
