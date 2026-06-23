# bme280-exporter

![C](https://img.shields.io/badge/C-00599C?style=for-the-badge&logo=c&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-000000?style=for-the-badge&logo=linux&logoColor=white)
![systemd](https://img.shields.io/badge/systemd-000000?style=for-the-badge&logo=systemd&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)
![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-A22846?style=for-the-badge&logo=raspberrypi&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-2088FF?style=for-the-badge&logo=githubactions&logoColor=white)

---

## Sobre

O **bme280-exporter** expõe leituras de um sensor **BME280** (temperatura, pressão e umidade relativa) para o **Prometheus**, gravando um arquivo no formato do *textfile collector* do `node_exporter`.

O caso de uso real é **monitorar a umidade interna de uma caixa hermética** que abriga um Raspberry Pi 4 e o próprio sensor.

**Domínio:** monitoramento ambiental / observabilidade de infraestrutura embarcada.

**Funcionalidades relevantes:**

- Leitura do sensor pelo **subsistema IIO do kernel Linux** (driver mainline `bmp280` via device-tree overlay), sem bibliotecas de fornecedor.
- Conversão das grandezas e escrita de métricas no formato Prometheus.
- Execução **oneshot** disparada por `systemd.timer` — sem daemon, sem loop interno, pegada de memória mínima.
- Sinal de saúde dedicado (`bme280_up`) para alertas no Prometheus.
- Distribuição como pacote **`.deb`** declarativo (usuário dedicado, diretório de saída e units gerados via `sysusers.d`, `tmpfiles.d` e systemd).

> **Estágio atual:** o binário em `src/hello-world.c` é um **stub de validação** — grava `bme280_dummy.prom` com valores zerados. O objetivo é validar toda a esteira (empacotamento, systemd, permissões, CI) **antes** de implementar o leitor real, que gravará `bme280.prom`.

### Métricas exportadas

```text
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

---

## Instalação

### Dependências

A arquitetura alvo é **arm64 (aarch64)** em **todos** os ambientes — por isso a compilação é **nativa**, sem cross-compilação.

**Para compilar e empacotar (ambiente de desenvolvimento):**

| Requisito | Observação |
|---|---|
| SO base | Linux **arm64** (ex.: container `ubuntu-24.04` em `--platform=linux/arm64`) |
| Compilador | `gcc` nativo + `build-essential` (C11) |
| Build | `make` |
| Empacotamento | `debhelper` (compat 13), `dpkg-dev`, `fakeroot` |
| Qualidade (opcional) | `lintian`, `valgrind`, `gdb` |

O caminho mais simples é abrir o repositório no **Dev Container** incluso (`.devcontainer/`), que já provisiona toda essa stack. Veja [`.devcontainer/README.md`](.devcontainer/README.md).

**Para instalar/executar o pacote (homologação e produção):**

| Requisito | Observação |
|---|---|
| SO | Debian 13 (trixie) **arm64** |
| Init | `systemd` (PID 1 real) |
| Métricas | `node_exporter` com `--collector.textfile.directory` apontando para o diretório de saída |
| Sensor (só produção) | BME280 em I²C (`/dev/i2c-1`, endereço `0x76`) e overlay habilitado no boot |

### Configuração

Este projeto **não usa arquivo `.env`** — a configuração é feita por **variável de ambiente** e pelas units do systemd.

| Variável | Padrão | Descrição |
|---|---|---|
| `TEXTFILE_DIR` | `/var/lib/node_exporter/textfile_collector` | Diretório onde o `.prom` é gravado. Lido pelo binário em tempo de execução. |

- **No pacote `.deb`**, o diretório de saída é criado por [`debian/bme280-reader.tmpfiles`](debian/bme280-reader.tmpfiles) e o usuário dedicado `bme280-reader` por [`debian/bme280-reader.sysusers`](debian/bme280-reader.sysusers); o serviço é definido em [`debian/bme280-reader.service`](debian/bme280-reader.service).
- **Em desenvolvimento**, basta exportar `TEXTFILE_DIR` apontando para um diretório gravável antes de rodar o binário.

> O **contrato entre projetos** é apenas o caminho do diretório *textfile*. O `node_exporter` **não** é configurado por este projeto.

### Inicialização

Compilar e empacotar localmente (no devcontainer arm64):

```bash
# Apenas compilar o binário em bin/
make

# Compilar e gerar o pacote .deb em bin/
make deb
```

O `make deb` executa o par canônico de empacotamento:

```bash
fakeroot debian/rules clean
fakeroot debian/rules binary
```

> **Por que `fakeroot debian/rules` e não `dpkg-buildpackage`:** no devcontainer o diretório pai `/workspaces/` é `root:root` e não-gravável; o `dpkg-buildpackage` tentaria escrever os artefatos em `..` e falharia. O `override_dh_builddeb` direciona o `.deb` para `bin/`.

Artefato gerado: `bin/bme280-reader_<versão>_arm64.deb`.

---

## Execução

### Desenvolvimento (devcontainer arm64)

Como o devcontainer tem a **mesma arquitetura do alvo**, o binário roda localmente:

```bash
mkdir -p /tmp/tc
TEXTFILE_DIR=/tmp/tc ./bin/bme280-reader
cat /tmp/tc/bme280_dummy.prom
```

Sem sensor real, isso valida abertura do caminho, formato das métricas e código de saída (`Type=oneshot`).

### Testes / inspeção estática

```bash
dpkg-deb --info     bin/bme280-reader_*.deb     # metadados e dependências
dpkg-deb --contents bin/bme280-reader_*.deb     # arquivos empacotados
file   bin/bme280-reader                         # confirma ELF aarch64
readelf -d bin/bme280-reader | grep -E 'BIND_NOW|RELRO'   # flags de hardening
lintian bin/bme280-reader_*.deb                  # conformidade Debian
```

O ciclo completo de runtime do pacote (`install → enable → remove → purge` com systemd real) é validado na **VM de homologação**. O passo a passo detalhado está em [`TEST.md`](TEST.md).

### Produção (Raspberry Pi 4 Model B)

1. Habilitar o overlay do sensor (fora do pacote — não reinicia automaticamente):
   ```bash
   sudo bash kernel-setup.sh   # edita /boot/firmware/config.txt e pede reboot
   ```
2. **Reiniciar** o Pi (manual).
3. Instalar o pacote:
   ```bash
   sudo apt install ./bme280-reader_*.deb
   ```
4. Verificar:
   ```bash
   id bme280-reader
   systemctl status bme280-reader.timer
   sudo systemctl start bme280-reader.service
   cat /var/lib/node_exporter/textfile_collector/bme280_dummy.prom
   journalctl -u bme280-reader.service -n 20 --no-pager
   ```

A partir daí o `systemd.timer` dispara o leitor periodicamente e o `node_exporter` republica as métricas.

---

## Ambientes

Os três ambientes compartilham a arquitetura **arm64 (aarch64)**, o que torna o build nativo de ponta a ponta.

| Ambiente | Máquina | SO | Papel |
|---|---|---|---|
| **Desenvolvimento** | Devcontainer arm64 (notebook) | Ubuntu 24.04 (`--platform=linux/arm64`) | Editar, compilar, empacotar, inspecionar **e rodar o stub** |
| **Homologação** | VM A1 (arm64) | Debian 13 (trixie) | Testar o `.deb` de verdade: systemd, `sysusers`, `tmpfiles`, ciclo install→enable→remove→purge |
| **Produção** | Raspberry Pi 4 Model B Rev 1.4 | Debian 13 (trixie), kernel `rpt-rpi-v8` | Sensor BME280 real via IIO e deploy final |

**Configuração por ambiente:**

- **Desenvolvimento:** `TEXTFILE_DIR` aponta para um diretório temporário (ex.: `/tmp/tc`); sem systemd.
- **Homologação / Produção:** `TEXTFILE_DIR` usa o padrão `/var/lib/node_exporter/textfile_collector`, criado pelo `tmpfiles.d`; serviço sob systemd com `User=bme280-reader`.
- **Produção:** adicionalmente requer o overlay `dtoverlay=i2c-sensor,bme280` em `/boot/firmware/config.txt` e o sensor no barramento `i2c-1` (endereço `0x76`).

**CI/CD:** o workflow [`.github/workflows/build-deb.yml`](.github/workflows/build-deb.yml) roda em runner **`ubuntu-24.04-arm`** (arm64 nativo), gera e inspeciona o `.deb` e publica como *artifact* (`workflow_dispatch`, manual).

---

## Observações

### Notas operacionais

- O leitor é **oneshot**: cada disparo do timer executa, grava o `.prom` e encerra. Não há processo residente para monitorar.
- O pacote **não** edita configuração de boot nem reinicia a máquina — a habilitação do overlay do kernel é um passo separado (`kernel-setup.sh`), por design.
- No **purge** (`apt purge`), apenas o arquivo `.prom` é removido; o diretório `/var/lib/node_exporter/textfile_collector/` é **preservado**, pois pode ser compartilhado com outros exporters.
- O usuário dedicado `bme280-reader` (sem shell, sem home) precisa pertencer ao grupo `i2c` para acessar `/dev/i2c-1` no leitor real.

### Limitações conhecidas

- O binário atual é um **stub** (`bme280_dummy.prom` com zeros); a leitura real do sensor ainda não está implementada.
- O pacote é **arquitetura-específico (`arm64`)** — não se destina a x86_64.
- O leitor é deliberadamente "burro": **toda lógica de limiar/alerta** (ex.: umidade > 60%) vive nas *alerting rules* do Prometheus, fora deste projeto.
- A instalação real do `.deb` (systemd/`sysusers`/`tmpfiles`) **não** é validável dentro do devcontainer, pois o container não roda systemd como PID 1 — daí o ambiente de homologação.

### Desempenho, armazenamento e escalabilidade

- **Desempenho:** pegada mínima de memória e CPU — sem daemon, sem polling contínuo. A frequência de coleta é definida pelo `systemd.timer` (`OnBootSec`/`OnUnitActiveSec`).
- **Armazenamento:** a saída é um único arquivo `.prom` sobrescrito a cada execução (poucas centenas de bytes); não há crescimento acumulativo em disco.
- **Hardening:** o binário é compilado com `-D_FORTIFY_SOURCE=2`, `-fstack-protector-strong`, `-fPIE -pie` e linkado com `-Wl,-z,relro -Wl,-z,now`.
- **Escalabilidade:** o modelo é de **um sensor por host**. A agregação de múltiplos nós é responsabilidade do Prometheus (scrape do `node_exporter` de cada Pi), não deste exporter.

---

> Documentação de contexto para desenvolvimento: [`CLAUDE.md`](CLAUDE.md) · Guia de build e teste: [`TEST.md`](TEST.md)
