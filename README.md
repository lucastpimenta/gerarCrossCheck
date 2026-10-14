# gerarCrossCheck.sh

Script para automatizar a geração de rotinas RMAN CrossCheck integradas ao Veritas NetBackup em ambientes Oracle.

Permite validar e remover backups expirados registrados no catálogo do RMAN tanto de forma **interativa** quanto **não-interativa / silenciosa (`--silent`)**, suportando ambientes **Single Instance** e **Oracle RAC** com autenticação via Oracle Wallet ou SO (`/ as sysdba`).

---

## 📦 Funcionalidades

- **Multiplataforma:** Detecta automaticamente o sistema operacional (**Linux**, **Solaris** e **AIX**) e associa a respectiva biblioteca NetBackup SBT (`libobk`)[cite: 1]:
  - Linux: `/usr/openv/netbackup/bin/libobk.so64`
  - Solaris: `/usr/openv/netbackup/bin/libobk.so64.1`
  - AIX: `/usr/openv/netbackup/bin/libobk.a64(shr.o)`[cite: 1]
- **Dois Modos de Operação:**
  - **Interativo:** Conduz o preenchimento com validações e sugestões automáticas.
  - **Modo Silencioso (`--silent`):** Executa sem paradas via flags de linha de comando ou arquivo `.conf` (ideal para automações com Ansible, pipelines ou shell script).
- **Oracle RAC Multi-Node:** Aloca canais simultâneos para cada nó participante com seus respectivos `NB_ORA_CLIENT`[cite: 1], prevenindo expirações incorretas de peças entre nós.
- **Integração com Catálogo NetBackup:** Monta automaticamente o descritor `NB_ORA_CATALOG_HOST` no padrão `<DB_NAME>_<DB_ID>`.
- **Feedbacks em Tempo Real no Monitor de Jobs:** Formata as saídas do Launcher com o prefixo `INF - `, permitindo que o processo `bphdb` do NetBackup encaminhe o progresso e o resumo do RMAN diretamente para o **Job Details** da Web UI e Activity Monitor.
- **Geração Segura de Arquivos:**
  - Launcher: `/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh` (permissão `755`)
  - Arquivo RMAN: `~/script/crosscheck_*.rmn` (permissão restrita `640`)

---

## 🛠️ Tecnologias Envolvidas

- Bash
- Oracle RMAN
- Veritas NetBackup (10.x / 9.x)[cite: 1]

---

## 🚀 Instalação

Execute como `root` no servidor Oracle:

### IBM AIX (Python 3)

```text
python3 -c "import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh','gerarCrossCheck.sh')"
chmod 755 gerarCrossCheck.sh
```

### Linux (cURL)

```text
curl -sSL https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh -o gerarCrossCheck.sh
chmod 755 gerarCrossCheck.sh
```

---

## 💻 Modos de Uso

### 1. Modo Interativo

Basta executar o script sem parâmetros:

```bash
./gerarCrossCheck.sh
```

O assistente guiará a configuração com base nas telas do NetBackup:
- Sugestão automática de `Service name` baseada no `Database Name`.
- Sugestão da porta padrão `[1521]`.
- Sugestão sequencial de nomes de instâncias RAC (`ORCL001`, `ORCL002`, ...).
- Reutilização do primeiro `ORACLE_HOME` para os demais nós do cluster.

---

### 2. Modo Silencioso (`--silent` via CLI)

Permite passar todos os parâmetros diretamente por argumentos de linha de comando.

#### Exemplo: Oracle RAC

```bash
./gerarCrossCheck.sh --silent \
  --master master-server.domain.com \
  --user oracle \
  --type rac \
  --dbname orcl \
  --dbid 1234567890 \
  --scan scan-cluster \
  --wallet /oracle/ORCL/wallet \
  --nodes "ORCL001:192.168.1.10:/oracle/app/product/19.0.0,ORCL002:192.168.1.11:/oracle/app/product/19.0.0"
```

> **Nota:** Parâmetros omitidos como `--port` (assume `1521`) e `--service` (assume o valor de `--dbname`) utilizam seus valores padrão inteligentes.

#### Exemplo: Single Instance

```bash
./gerarCrossCheck.sh --silent \
  --master master-server.domain.com \
  --user oracle \
  --type single \
  --home /oracle/app/product/19.0.0 \
  --sid ORCL \
  --client 192.168.1.10 \
  --method 1
```

---

### 3. Modo Silencioso com Arquivo de Configuração (`--config`)

Crie um arquivo `.conf` (por exemplo, `/tmp/crosscheck_rac.conf`):

```ini
NB_PRIMARY="master-server.domain.com"
DB_USER="oracle"
TOPOLOGIA="2"
DB_NAME="orcl"
DB_ID="1234567890"
SCAN_NAME="scan-cluster"
SERVICE_NAME="orcl"
SCAN_PORT="1521"
WALLET_PATH="/oracle/ORCL/wallet"
RAC_NODES="ORCL001:192.168.1.10:/oracle/app/product/19.0.0,ORCL002:192.168.1.11:/oracle/app/product/19.0.0"
```

Execute apontando para o arquivo:

```bash
./gerarCrossCheck.sh --silent --config /tmp/crosscheck_rac.conf
```

---

## 📋 Parâmetros Aceitos

| Opção | Descrição | Obrigatório em Silent? |
| :--- | :--- | :---: |
| `--silent` | Ativa o modo não-interativo | Sim (para silent) |
| `--config <arquivo>` | Carrega parâmetros de um arquivo `.conf` | Opcional |
| `--master <host>` | Servidor Primary / Master do NetBackup[cite: 1] | Sim |
| `--user <so_user>` | Usuário proprietário do Oracle no SO | Sim |
| `--type <single\|rac>` | Tipo de topologia (`single` ou `rac`) | Sim |
| `--home <path>` | `$ORACLE_HOME` (apenas Single Instance) | Condicional (Single) |
| `--sid <sid>` | `$ORACLE_SID` (apenas Single Instance) | Condicional (Single) |
| `--client <client>` | Hostname/IP do cliente no NetBackup (Single)[cite: 1] | Condicional (Single) |
| `--method <1\|2\|3>` | Conexão Single: 1=SO, 2=Wallet, 3=String | Opcional (Default: 1) |
| `--dbname <name>` | Database Name / Unique Name (RAC) | Condicional (RAC) |
| `--dbid <id>` | Database ID do Oracle (RAC) | Condicional (RAC) |
| `--scan <scan_host>` | Hostname SCAN do RAC | Condicional (RAC) |
| `--service <name>` | Service Name do RAC | Opcional (Default: dbname) |
| `--port <porta>` | Porta do Listener | Opcional (Default: 1521) |
| `--wallet <path>` | Caminho do Oracle Wallet (se Wallet/RAC) | Condicional |
| `--nodes "<lista>"` | Lista de nós: `"SID:IP:HOME,SID:IP:HOME"`[cite: 1] | Condicional (RAC Silent) |
| `-h`, `--help` | Exibe o menu de ajuda no console | Opcional |

---

## 📊 Visualização nos Detalhes do Job (NetBackup)

Quando executado a partir de uma política agendada no NetBackup, as mensagens impressas com `INF - ` são incorporadas aos detalhes do job:

```text
Info bphdb (pid=...) INF - ====================================================
Info bphdb (pid=...) INF -             RESUMO DO RMAN CROSSCHECK               
Info bphdb (pid=...) INF - ====================================================
Info bphdb (pid=...) INF - Total de objetos verificados : 3483
Info bphdb (pid=...) INF -   - Em status AVAILABLE      : 3483
Info bphdb (pid=...) INF -   - Em status EXPIRED        : 0
Info bphdb (pid=...) INF - ----------------------------------------------------
Info bphdb (pid=...) INF - Pecas efetivamente deletadas : 0
Info bphdb (pid=...) INF - ====================================================
Info bphdb (pid=...) done. status: 0: the requested operation was successfully completed
```

---

## 📌 Histórico de Versões

### v3.2
- Inclusão do modo não-interativo / silencioso (`--silent`) via argumentos de linha de comando.
- Suporte à leitura e carga de parâmetros via arquivo de configuração externo (`--config <arquivo>`).
- Suporte à definição de múltiplos nós RAC em formato compacto (`SID:CLIENT:HOME`).
- Prefixo `INF - ` nas saídas do launcher, viabilizando o encaminhamento automático do resumo analítico para o Activity Monitor e Web UI do NetBackup via processo `bphdb`.
- Menu de ajuda contextual via CLI (`-h` / `--help`) e exibição de resumo de parâmetros absorvidos em modo silencioso.

### v3.1
- Validação estrita e contínua do diretório da Oracle Wallet (impede prosseguir com caminhos inválidos ou sem permissão).
- Inclusão de sugestões inteligentes automáticas ao pressionar Enter:
  - Sugestão do `Service name` com o mesmo valor informado em `Database name`.
  - Sugestão da porta padrão do Listener (`[1521]`).
  - Sugestão sequencial de nomes de instâncias RAC (`<DBNAME>001`, `<DBNAME>002`...).
  - Sugestão de reaproveitamento do primeiro `ORACLE_HOME` para os demais nós do cluster.
- Inclusão de analisador `awk` compatível com AIX, Solaris e Linux no launcher para consolidação de objetos verificados, disponíveis e deletados.
- Atualização do método de download via `python3` com chamada isolada para sistemas legados/AIX.

### v3.0
- Reformulação completa da ferramenta, substituindo a passagem posicional manual por uma interface interativa em linha de comando.
- Suporte nativo completo a **Oracle RAC** com balanceamento e alocação de canais dedicados para todos os nós participantes.
- Ordem de coleta de dados no RAC alinhada à interface Web UI do NetBackup (*Edit database* e *Instances*).
- Montagem automática do parâmetro `NB_ORA_CATALOG_HOST` a partir de `Database Name` e `Database ID` (`<DB_NAME>_<DB_ID>`).
- Suporte a conexões via descritor SCAN inline com autenticação via Oracle Wallet, dispensando necessidade de arquivos `tnsnames.ora`.
- Validação contextual de permissões em diretórios (`ORACLE_HOME`, binário `rman` e Wallet) executada diretamente sob a identidade do usuário de banco (`$DB_USER`), evitando divergências ao executar como `root`.
- Limpeza automática de backups expirados com a instrução `DELETE NOPROMPT EXPIRED BACKUP`.

### v2.3
- Removido o parâmetro manual redundante de `NB_ORA_CLIENT` em favor do mapeamento nativo por canal.

### v2.2
- Adicionado suporte à sintaxe e alias `NBU_PRIMARY`.

### v2.1
- Adicionado suporte a múltiplos caminhos de Oracle Wallet.
- Suporte às sintaxes `SID:WALLET` e `SID:NONE`.

### v2.0
- Adicionado suporte a autenticação via Oracle Wallet e autenticação local (`NONE` via SO).
- Compatibilidade validada para Linux, Solaris e AIX.
- Correção de problemas de expansão de variáveis, interpolação de shell e quoting no AIX.

### v1.0
- Primeira versão do gerador de rotinas CrossCheck para Oracle RMAN integrado ao Veritas NetBackup.
