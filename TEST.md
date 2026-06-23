# Guia de montagem e teste do pacote .deb

Este documento explica o que cada etapa valida, por que ela existe e quais ferramentas são usadas.
A premissa central mudou: **o devcontainer agora é arm64 (aarch64)**, a mesma arquitetura do alvo. A compilação é **nativa** — não há mais cross-compilação.

Por causa disso, o que antes só rodava no Pi agora se divide em **três ambientes**:

| Ambiente | Máquina | Para quê |
|---|---|---|
| **Dev** | devcontainer arm64 (no notebook) | editar, compilar, empacotar, inspecionar **e rodar o stub** |
| **Homologação** | VM A1 arm64 com Debian 13 (trixie) | testar o `.deb` de verdade: systemd, sysusers, tmpfiles, ciclo install→enable→remove→purge |
| **Produção** | Raspberry Pi 4 | sensor real, IIO, deploy final |

---

## Pergunta direta: o que cada ambiente cobre?

| Necessidade | Dev (devcontainer arm64) | Homologação (VM A1) | Produção (Pi) |
|---|---|---|---|
| Compilar o binário aarch64 | Sim — `gcc` nativo | — | — |
| Empacotar o `.deb` | Sim — `debhelper`, `fakeroot`, `dpkg-dev` | — | — |
| Inspecionar o `.deb` sem instalar | Sim — `dpkg-deb`, `lintian`, `file`, `readelf` | — | — |
| Rodar o binário do stub | **Sim** — arquitetura igual à do alvo | Sim | Sim |
| Instalar o `.deb` (apt) e testar systemd | Não — container não tem systemd/PID 1 | **Sim** | Sim |
| Ciclo install→enable→remove→purge real | Não | **Sim** | Sim |
| Ler o sensor BME280 de verdade (IIO) | Não — sem hardware | Não — sem hardware | **Sim** |

**Resumo:** o devcontainer cobre 100% da esteira de *build*, *inspeção estática* e execução do binário. A validação de **systemd/dpkg** (instalar de verdade, criar usuário/diretório, habilitar timer, remover, purgar) acontece na **VM A1**. O **Pi** fica para o sensor real.

> Por que não instalar o `.deb` no devcontainer? Os maintainer scripts gerados pelo debhelper chamam `systemd-sysusers`, `systemd-tmpfiles --create` e `systemctl enable --now`. Um container Docker não roda o systemd como PID 1, então essas chamadas não refletem o comportamento real. A VM A1 tem systemd de verdade — é onde esse ciclo é confiável.

---

## O que está dentro do .deb?

O arquivo `bin/bme280-reader_0.1.0_arm64.deb` contém:

```
./usr/bin/bme280-reader                         ← o binário compilado
./usr/lib/systemd/system/bme280-reader.service  ← unit oneshot
./usr/lib/systemd/system/bme280-reader.timer    ← dispara a cada 60 s
./usr/lib/sysusers.d/bme280-reader.conf         ← cria o usuário bme280-reader
./usr/lib/tmpfiles.d/bme280-reader.conf         ← cria o diretório de saída
./usr/share/doc/bme280-reader/changelog.gz      ← changelog Debian (obrigatório)
```

### O binário vem de onde?

Sim, o `.deb` empacota o binário compilado. O fluxo é:

```
src/hello-world.c
       │
       │  gcc nativo (aarch64-linux-gnu)
       ▼
bin/bme280-reader          ← ELF 64-bit ARM aarch64, não-stripped (artefato de build)
       │
       │  dh_install + dh_strip (dentro do fakeroot debian/rules binary)
       ▼
debian/bme280-reader/usr/bin/bme280-reader   ← cópia stripped (sem símbolos de debug)
       │
       │  dh_builddeb --destdir=bin
       ▼
bin/bme280-reader_0.1.0_arm64.deb           ← arquivo final
```

O `dh_strip` separa os símbolos de debug em `bin/bme280-reader-dbgsym_0.1.0_arm64.ddeb`.
O binário dentro do `.deb` é o stripped — menor, sem informações de depuração.

---

## Parte 1 — Build do .deb (Dev — devcontainer)

Execute isso toda vez que alterar o código-fonte ou os arquivos `debian/`.

### Passo 1.1 — Rodar o build

```bash
make deb
```

**O que faz:** o target `deb` executa, em sequência:

```
fakeroot debian/rules clean
fakeroot debian/rules binary
```

**Por que é simples agora:** como o devcontainer é arm64, o `gcc` padrão já gera binário aarch64. Não há `.env`, nem `DEB_HOST_ARCH`, nem `dpkg-architecture`, nem cross-compiler. O `debian/rules` deixa o `CC` no padrão (`gcc`) e o debhelper resolve as dependências de biblioteca a partir do sistema nativo.

**Por que o `clean` antes do `binary`:** se `debian/debhelper-build-stamp` existir de um build anterior, o `dh binary` pula o `dh_auto_build` (a compilação em si), empacotando o binário antigo. O `clean` elimina esse estado.

**Por que continua sendo `fakeroot debian/rules` (e não `dpkg-buildpackage`):** o `dpkg-buildpackage` grava `.deb`/`.buildinfo`/`.changes` no diretório pai (`/workspaces/`), que é `root:root` e não-gravável pelo usuário `vscode`. O par `fakeroot debian/rules clean && binary` mantém tudo dentro do projeto e direciona o `.deb` para `bin/` via `override_dh_builddeb`.

### O que acontece dentro de `fakeroot debian/rules binary`

1. `dh_auto_build` — chama `make`, que invoca `gcc` para compilar `src/hello-world.c` e gerar `bin/bme280-reader`.
2. `dh_install` — copia `bin/bme280-reader` para `debian/bme280-reader/usr/bin/` usando o mapeamento em `debian/bme280-reader.install`.
3. `dh_installsystemd` — copia os arquivos `.service` e `.timer` para `debian/bme280-reader/usr/lib/systemd/system/` e gera fragmentos de `postinst`/`prerm`/`postrm` que habilitam/desabilitam as units na instalação.
4. `dh_installsysusers` — copia `debian/bme280-reader.sysusers` para `debian/bme280-reader/usr/lib/sysusers.d/bme280-reader.conf` e gera fragmento de `postinst` que chama `systemd-sysusers` para criar o usuário.
5. `dh_installtmpfiles` — copia `debian/bme280-reader.tmpfiles` para `debian/bme280-reader/usr/lib/tmpfiles.d/bme280-reader.conf` e gera fragmento de `postinst` que chama `systemd-tmpfiles --create`.
6. `dh_strip` — remove símbolos de debug do binário (cria o `.ddeb` separado).
7. `dh_shlibdeps` — analisa o binário, identifica dependências de bibliotecas compartilhadas (`libc6 (>= …)`) e as registra em `debian/bme280-reader.substvars`. Como o build é nativo, o multiarch padrão (`/usr/lib/aarch64-linux-gnu`) é suficiente — **não há mais o override `-l/usr/aarch64-linux-gnu/lib`**.
8. `dh_gencontrol` — gera `debian/bme280-reader/DEBIAN/control` substituindo `${shlibs:Depends}` e `${misc:Depends}` pelos valores calculados.
9. `dh_md5sums` — calcula checksums MD5 de todos os arquivos do pacote.
10. `dh_builddeb --destdir=bin` — empacota tudo em `bin/bme280-reader_0.1.0_arm64.deb`.

**Por que `fakeroot`:** as entradas dentro do `.deb` precisam ter `owner root:root`. O `fakeroot` intercepta chamadas de sistema (`chown`, `chmod`) e as simula sem precisar de privilégio real — o arquivo no disco continua sendo do `vscode`, mas o `dpkg-deb` "enxerga" `root:root`.

---

## Parte 2 — Inspeção estática + execução do stub (Dev — devcontainer)

Estes passos funcionam sem instalar o pacote e sem a VM/Pi.

### Passo 2.1 — Verificar metadados do pacote

```bash
dpkg-deb --info bin/bme280-reader_0.1.0_arm64.deb
```

**Saída esperada (trechos):**

```
Package: bme280-reader
Version: 0.1.0
Architecture: arm64
Maintainer: Gustavo Caruazu <gustavo@caruazu.com>
Depends: libc6 (>= 2.34), systemd | systemd-standalone-sysusers | systemd-sysusers
...
```

**O que valida:**
- `Architecture: arm64` — o binário é aarch64.
- `Depends: libc6 (>= …)` — o `dh_shlibdeps` resolveu a dependência da libc a partir do sistema nativo (sem o qualificador `:arm64` que aparecia no build cross).
- `Depends: systemd | systemd-sysusers` — o `dh_installsysusers` adicionou a dependência para criação do usuário.
- Versão e mantenedor batem com `debian/changelog` e `debian/control`.

### Passo 2.2 — Listar conteúdo do pacote

```bash
dpkg-deb --contents bin/bme280-reader_0.1.0_arm64.deb
```

**O que valida:** que todos os arquivos esperados estão presentes nos caminhos corretos dentro do pacote:

| Arquivo no .deb | O que confirma |
|---|---|
| `./usr/bin/bme280-reader` | o binário foi copiado corretamente |
| `./usr/lib/systemd/system/bme280-reader.service` | a unit foi incluída |
| `./usr/lib/systemd/system/bme280-reader.timer` | o timer foi incluído |
| `./usr/lib/sysusers.d/bme280-reader.conf` | a criação do usuário está declarada |
| `./usr/lib/tmpfiles.d/bme280-reader.conf` | a criação do diretório está declarada |

### Passo 2.3 — Verificar arquitetura do binário

```bash
file bin/bme280-reader
```

**Saída esperada:**

```
ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), dynamically linked, ...
```

**O que valida:**
- `ARM aarch64` — compilado para a arquitetura do alvo (agora a mesma do devcontainer).
- `pie executable` — a flag `-fPIE -pie` foi aplicada (ASLR habilitado).
- `dynamically linked` — depende da libc (esperado).

### Passo 2.4 — Verificar flags de hardening

```bash
readelf -d bin/bme280-reader | grep -E 'FLAGS|BIND_NOW|GNU_RELRO'
```

**Saída esperada:**

```
 0x000000000000001e (FLAGS)              BIND_NOW
 0x000000006ffffffb (FLAGS_1)            Flags: NOW PIE
```

**O que valida:** que `-Wl,-z,relro -Wl,-z,now` estão ativos. `BIND_NOW` significa que todos os símbolos são resolvidos na carga (proteção contra ataques de substituição de GOT). `GNU_RELRO` marca o segmento de relocações como somente-leitura após a carga.

### Passo 2.5 — Rodar o stub no próprio devcontainer

Como a arquitetura do devcontainer agora é igual à do alvo, dá para **executar o binário aqui** — sem VM, sem Pi. Aponte o `TEXTFILE_DIR` para um diretório gravável:

```bash
mkdir -p /tmp/tc
TEXTFILE_DIR=/tmp/tc ./bin/bme280-reader
echo "exit=$?"
cat /tmp/tc/bme280_dummy.prom
```

**Saída esperada:** `exit=0` e o arquivo `.prom` no formato Prometheus (ver Passo 3.7). Isso valida, ainda no Dev, que o binário abre o caminho correto, grava as métricas e encerra com sucesso (`Type=oneshot`). O comportamento sob systemd/permissões dedicadas continua sendo validado na VM A1.

### Passo 2.6 — Inspecionar scripts de maintainer

```bash
dpkg-deb --extract bin/bme280-reader_0.1.0_arm64.deb /tmp/deb-extract
dpkg-deb --control bin/bme280-reader_0.1.0_arm64.deb /tmp/deb-extract/DEBIAN
cat /tmp/deb-extract/DEBIAN/postinst
```

**O que valida:** que o `debhelper` gerou a lógica de ciclo de vida correta nos maintainer scripts. O `postinst` deve conter:

1. Chamada a `systemd-sysusers bme280-reader.conf` — cria o usuário `bme280-reader`.
2. Chamada a `systemd-tmpfiles --create bme280-reader.conf` — cria `/var/lib/node_exporter/textfile_collector/`.
3. Chamada a `systemctl enable --now bme280-reader.timer` — ativa o timer.

O `prerm` deve conter `systemctl disable bme280-reader.timer`. O `postrm` (no purge) deve conter a limpeza do arquivo `.prom` mas **não** do diretório (conforme restrição do projeto).

### Passo 2.7 — Rodar o lintian

```bash
lintian --tag-display-limit 0 bin/bme280-reader_0.1.0_arm64.deb
```

**O que valida:** conformidade com as políticas Debian. Os avisos atuais esperados são informativos:

| Tag | Significado | Ação |
|---|---|---|
| `E: no-copyright-file` | falta `debian/copyright` | aceitável nesta fase de validação |
| `W: no-manual-page` | falta manpage para `/usr/bin/bme280-reader` | aceitável nesta fase |

Um `E:` (error) diferente desses indica problema real de empacotamento.

---

## Parte 3 — Teste do ciclo de vida (Homologação — VM A1 arm64)

Estes testes rodam na **VM A1 com Debian 13 (trixie)**, que tem systemd real. É aqui que se valida o comportamento do `.deb` instalado — antes de tocar no Pi de produção.

### Passo 3.1 — Transferir o .deb

```bash
# No devcontainer
scp bin/bme280-reader_0.1.0_arm64.deb <user>@<IP-DA-VM>:~
```

### Passo 3.2 — Instalar o pacote

```bash
# Na VM
sudo apt install ./bme280-reader_0.1.0_arm64.deb
```

**O que valida:** que os maintainer scripts rodam sem erro — em particular que o usuário, o diretório e o timer foram criados.

### Passo 3.3 — Verificar usuário criado pelo sysusers

```bash
id bme280-reader
```

**Saída esperada:**

```
uid=XXXX(bme280-reader) gid=XXXX(bme280-reader) groups=XXXX(bme280-reader)
```

**O que valida:** que `systemd-sysusers` processou `/usr/lib/sysusers.d/bme280-reader.conf` e criou o usuário sem shell (`/usr/sbin/nologin`) e sem home (`/nonexistent`). Se este passo falhar, o serviço não conseguirá executar com `User=bme280-reader`.

### Passo 3.4 — Verificar diretório criado pelo tmpfiles

```bash
ls -la /var/lib/node_exporter/
```

**Saída esperada:**

```
drwxr-xr-x  2 bme280-reader bme280-reader 4096 ... textfile_collector
```

**O que valida:** que `systemd-tmpfiles` processou `/usr/lib/tmpfiles.d/bme280-reader.conf` e criou o diretório com `owner=bme280-reader:bme280-reader` e permissão `0755`. Este é o diretório onde o binário grava o `.prom` — se as permissões estiverem erradas, o serviço falhará com `Permission denied`.

### Passo 3.5 — Verificar o timer habilitado

```bash
systemctl status bme280-reader.timer
systemctl list-timers bme280-reader.timer
```

**O que valida:**
- `Active: active (waiting)` — o timer está habilitado e aguardando o próximo disparo.
- `NEXT` — quando o serviço vai rodar pela próxima vez.
- `ACTIVATES` — confirma que o timer está vinculado a `bme280-reader.service`.

O timer está configurado para disparar 30 segundos após o boot e a cada 60 segundos depois (`OnBootSec=30s`, `OnUnitActiveSec=60s`).

### Passo 3.6 — Disparar o serviço manualmente

```bash
sudo systemctl start bme280-reader.service
```

**O que valida:** que o binário executa sem erro de permissão, cria o arquivo `.prom` e encerra (`Type=oneshot`). O serviço não deve continuar rodando — após terminar, `systemctl status` deve mostrar `Active: inactive (dead)` com `Main PID: XXXX (code=exited, status=0/SUCCESS)`.

### Passo 3.7 — Verificar a saída do stub

```bash
cat /var/lib/node_exporter/textfile_collector/bme280_dummy.prom
```

**Saída esperada:**

```
# HELP bme280_up 1 if the last read was successful, 0 otherwise
# TYPE bme280_up gauge
bme280_up 1
# HELP bme280_temperature_celsius Temperature in Celsius (dummy)
# TYPE bme280_temperature_celsius gauge
bme280_temperature_celsius 0
# HELP bme280_humidity_percent Relative humidity in percent (dummy)
# TYPE bme280_humidity_percent gauge
bme280_humidity_percent 0
# HELP bme280_pressure_hpa Atmospheric pressure in hPa (dummy)
# TYPE bme280_pressure_hpa gauge
bme280_pressure_hpa 0
```

**O que valida:** que o binário (a) abriu o arquivo no caminho correto com sucesso, (b) gravou métricas no formato que o node_exporter espera, e (c) o `bme280_up 1` confirma que o stub considera a "leitura" bem-sucedida. Valores zero são esperados — este é o stub, não o leitor real.

### Passo 3.8 — Verificar logs do serviço

```bash
journalctl -u bme280-reader.service -n 20 --no-pager
```

**O que valida:** ausência de erros (`Permission denied`, `cannot open`, `write failed`). Qualquer linha com `bme280-reader:` no stderr indica problema no runtime — o binário usa `fprintf(stderr, ...)` para reportar erros antes de retornar código de saída 1.

### Passo 3.9 — Testar o ciclo de remoção

```bash
sudo apt remove bme280-reader
```

**O que valida:**
- O timer e o serviço foram desabilitados e parados (`prerm` chama `systemctl disable`).
- O arquivo `/usr/bin/bme280-reader` foi removido.
- O arquivo `.prom` e o diretório **foram preservados** (o `postrm` só age no `purge`, não no `remove`).
- O usuário `bme280-reader` ainda existe (só é removido no `purge`, que não implementamos).

```bash
sudo apt purge bme280-reader
```

**O que valida:** que o arquivo `bme280_dummy.prom` foi removido, mas o diretório `/var/lib/node_exporter/textfile_collector/` **permanece** (conforme restrição do projeto — outros exporters podem usar o mesmo diretório).

---

## Parte 4 — Produção (Raspberry Pi)

Só depois que a VM A1 valida o ciclo completo o `.deb` vai para o Pi. Lá entram os passos específicos de hardware, que nenhum dos outros ambientes cobre:

1. `sudo bash kernel-setup.sh` — habilita o overlay `dtoverlay=i2c-sensor,bme280` em `/boot/firmware/config.txt` e pede reboot (fora do pacote).
2. **Reboot manual** do Pi.
3. `sudo apt install ./bme280-reader_*.deb` — mesmo fluxo da VM (Passos 3.2–3.9).
4. Validação extra do sensor real (quando o leitor de verdade substituir o stub): conferir `/sys/bus/iio/devices/iio:deviceN/name == bme280` e as leituras de `in_temp_input`, `in_humidityrelative_input`, `in_pressure_input`.

---

## Resumo: o que cada ferramenta prova

| Ferramenta / Passo | Ambiente | Prova |
|---|---|---|
| `make deb` | Dev | build reproduzível: gcc nativo, sem privilégio root, sem cross |
| `dpkg-deb --info` | Dev | metadados, dependências e arquitetura corretos |
| `dpkg-deb --contents` | Dev | todos os arquivos estão no lugar certo |
| `file bin/bme280-reader` | Dev | binário é aarch64 |
| `readelf -d` | Dev | flags de hardening aplicadas pelo linker |
| `TEXTFILE_DIR=… ./bin/bme280-reader` | Dev | binário roda e grava o `.prom` no formato certo |
| `cat DEBIAN/postinst` | Dev | ciclo de vida declarativo gerado corretamente pelo debhelper |
| `lintian` | Dev | conformidade com políticas Debian |
| `id bme280-reader` | Homologação | sysusers funcionou — usuário dedicado criado |
| `ls -la /var/lib/node_exporter/` | Homologação | tmpfiles funcionou — diretório com owner correto |
| `systemctl status bme280-reader.timer` | Homologação | timer habilitado e agendado |
| `systemctl start bme280-reader.service` | Homologação | binário executa e encerra sem erro sob systemd |
| `journalctl -u bme280-reader.service` | Homologação | nenhum erro de runtime |
| `apt remove` + `apt purge` | Homologação | ciclo de remoção preserva o que deve preservar |
| overlay + IIO + sensor | Produção | leitura real do BME280 no Pi |
