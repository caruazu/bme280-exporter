# CLAUDE.md — bme280-exporter

Documentação de contexto para o Claude Code. Leia inteiro antes de qualquer tarefa.


## O que este projeto faz

Exporta leituras do sensor BME280 (temperatura, pressão, umidade) para o Prometheus via **textfile collector do node_exporter**. O sensor fica dentro de uma caixa hermética junto com um Raspberry Pi 4 — o objetivo real é monitorar **umidade interna da caixa**.


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
**Arquitetura do container:** `x86_64 / amd64`

### Ferramentas instaladas

| Ferramenta | Versão |
|||
| gcc (amd64) | 13.3.0 |
| g++ | 13.3.0 |
| gdb | instalado |
| cmake | 3.28.3 |
| make |4.3 |
| valgrind | instalado |
| libc6-dev (amd64) | 2.39 |
| build-essential | instalado |
| claude (CLI) | auto-atualizado em runtime |
| dpkg / dpkg-buildpackage | 1.22.6 |
| debhelper (`dh`) | 13.14.1 |
| fakeroot | 1.33 |
| gcc-aarch64-linux-gnu | 13.2.0 |
| binutils-aarch64-linux-gnu | 2.42 |
| libc6-dev-arm64-cross | 2.39 |
| crossbuild-essential-arm64 | 12.10 |
| lintian | 2.117.0 |
| devscripts | 2.23.7 |

### Volume persistente do Claude

`claude-code-config-<devcontainerId>` montado em `~/.claude` — persiste login e config entre rebuilds.

## Arquitetura (decisões fechadas — não questionar)

### Driver do sensor: kernel / IIO
- Usar driver mainline `bmp280` via device-tree overlay `dtoverlay=i2c-sensor,bme280`.
- O kernel faz a compensação de temperatura/pressão/umidade.
- O sensor aparece em `/sys/bus/iio/devices/iio:deviceN/`.
- **NÃO** usar API C da Bosch. **NÃO** escrever driver em userspace.
- Resolver o device pelo atributo `name == bme280` — **não chumar `iio:device0`**.

### Leitor em C
- C11, binário único, linka apenas a libc (sem bibliotecas externas).
- Compilado com flags de hardening (ver §10).
- Lê o `/sys`, escala unidades, grava o `.prom`.
- Cross-compilado para `aarch64` no devcontainer.

### Modelo de execução: oneshot via systemd
- O leitor é **processo de execução curta**: acorda, roda uma vez, encerra.
- **Não é daemon. Não tem loop de sleep interno.**
- Gerenciado por um `systemd.timer` que dispara o `systemd.service`.
- Minimiza pegada de memória; combina com o modo forçado do BME280.

### Integração com Prometheus
- O leitor grava em `/var/lib/node_exporter/textfile_collector/bme280.prom` (caminho configurável).
- O node_exporter republica via `--collector.textfile.directory`.
- **Não editar nem configurar o node_exporter** — está fora do escopo.
- **Contrato entre projetos:** o caminho do diretório textfile.

### Empacotamento Debian declarativo
- Pacote `.deb` construído com `debhelper`.
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

- Usuário dedicado: `bme280-exporter` (sem shell, sem home), criado via `sysusers.d`.
- Pertence ao grupo `i2c` (para acesso ao `/dev/i2c-1`, se necessário).
- Acesso de escrita ao diretório textfile via `tmpfiles.d`.



## Flags de hardening para compilação C

```makefile
CFLAGS = -std=c11 -Wall -Wextra -Wpedantic \
         -D_FORTIFY_SOURCE=2 -fstack-protector-strong \
         -fPIE -pie \
         -Wl,-z,relro -Wl,-z,now \
         -O2
```

Cross-compilation para aarch64:
```makefile
CC = aarch64-linux-gnu-gcc
```



## Convenção de build do pacote

```bash
# no devcontainer, na raiz do repo
dpkg-buildpackage -us -uc -b --host-arch arm64
```

O `.deb` gerado vai para o diretório bin.



## Fluxo de deploy manual (resumo)

1. **No devcontainer:** `dpkg-buildpackage -us -uc -b --host-arch arm64` → gera `.deb`
2. **Copiar** o `.deb` para o Pi (`scp`)
3. **No Pi:** `sudo bash kernel-setup.sh` → edita `/boot/firmware/config.txt` e pede reboot
4. **Reboot** do Pi (manual)
5. **No Pi:** `sudo apt install ./bme280-exporter_*.deb`
6. **Verificar:** `systemctl status bme280-exporter.timer` e `cat /var/lib/node_exporter/textfile_collector/bme280.prom`
