# gerarCrossCheck.sh

Script interativo para automatizar a geração de rotinas RMAN CrossCheck em ambientes Oracle integrados ao Veritas NetBackup.

O objetivo é simplificar a validação e a limpeza de backups expirados registrados no repositório do RMAN, suportando ambientes **Single Instance** e **Oracle RAC** com autenticação via Oracle Wallet (com ou sem TNS) ou autenticação local do sistema operacional.

---

## 📦 O que o Script Faz

- Detecta automaticamente o sistema operacional (**Linux**, **Solaris** ou **AIX**).
- Configura dinamicamente a biblioteca SBT (`libobk`) adequada para cada plataforma[cite: 7]:
  - Linux: `/usr/openv/netbackup/bin/libobk.so64`
  - Solaris: `/usr/openv/netbackup/bin/libobk.so64.1`
  - AIX: `/usr/openv/netbackup/bin/libobk.a64(shr.o)`[cite: 7]
- Executa validações de permissões diretamente com o usuário Oracle informado (`$DB_USER`), mesmo sendo disparado como `root`.
- Desativa automaticamente traces excessivos de diagnóstico do cliente ADR e Net8 (`DIAG_ADR_ENABLED=OFF` e `TRACE_LEVEL_CLIENT=OFF`), evitando consumo descontrolado de espaço na partição `/oracle`.
- Gera o inicializador executável (launcher):

```text
/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
```

- Gera o arquivo de comandos RMAN com permissões restritas (640):
  - **Single Instance:** `~/script/crosscheck_<SID>.rmn`
  - **Oracle RAC:** `~/script/crosscheck_rac_<DB_NAME>.rmn`
- No **Oracle RAC**, aloca canais simultâneos para todos os nós participantes com seus respectivos `NB_ORA_CLIENT`[cite: 7], evitando falsos positivos de peças expiradas geradas por outros nós.
- Monta automaticamente a diretiva `NB_ORA_CATALOG_HOST` com base no `Database Name` e `Database ID` (`<DB_NAME>_<DB_ID>`), integrando-se nativamente à Web UI do NetBackup[cite: 4].
- Executa as instruções:

```rman
CROSSCHECK BACKUP;
DELETE NOPROMPT EXPIRED BACKUP;
```

- Exibe automaticamente na tela um resumo consolidado ao término da execução, computando o total de objetos checados, peças em status `AVAILABLE`, peças em status `EXPIRED` e peças removidas.
- Direciona os logs detalhados para o diretório `~/script/`.

---

## 🛠️ Construído com

- Bash
- Oracle RMAN
- Veritas NetBackup (10.x / 9.x)[cite: 7]

---

## 🔧 Instalação

Como o script deve ser executado como `root`, baixe diretamente no servidor desejado.

### Via Python 3 (Validado no IBM AIX)

```bash
python3 -c "import urllib.request; urllib.request.urlretrieve('[https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh','gerarCrossCheck.sh](https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh','gerarCrossCheck.sh)')"
chmod 755 gerarCrossCheck.sh
```

### Via cURL (Linux / ambientes com curl)

```bash
curl -sSL [https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh](https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh) -o gerarCrossCheck.sh
chmod 755 gerarCrossCheck.sh
```

### Via Python 2 (ambientes legados)

```bash
python -c "import urllib2, ssl; ctx = ssl._create_unverified_context(); open('gerarCrossCheck.sh', 'w').write(urllib2.urlopen('[https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh](https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh)', context=ctx).read())"
chmod 755 gerarCrossCheck.sh
```

---

## 🚀 Como Usar

Execute o gerador como `root`:

```bash
./gerarCrossCheck.sh
```

O script é totalmente interativo e conduz o preenchimento de acordo com a topologia escolhida.

### Fluxo para Oracle RAC (Alinhado à Web UI do NetBackup)

As perguntas são organizadas na ordem visual exata das telas de administração do NetBackup:

1. **Informações Gerais:**
   - Servidor Primário / Master do NetBackup[cite: 7]
   - Usuário Oracle no SO (valida se o usuário existe)
   - Topologia: selecionar `2) Oracle RAC`
2. **Tela "Edit database" (Configurações Gerais):**[cite: 4]
   - Enter database name / Database unique name[cite: 4]
   - Database ID *(o script concatena `<DB_NAME>_<DB_ID>` para o catálogo)*[cite: 4]
   - Scan name[cite: 4]
   - Service name[cite: 4]
   - Port[cite: 4]
   - Oracle Wallet path *(validação de leitura das credenciais pelo usuário Oracle)*[cite: 4]
3. **Tela "Instances" (Tabela de Nós do RAC):**[cite: 5]
   - Quantidade de instâncias (linhas da tabela)[cite: 5]
   - Para cada nó:[cite: 5]
     - Instance name[cite: 5]
     - Client name (IP ou Hostname registrado no NetBackup)[cite: 5]
     - Oracle home[cite: 5]

---

## 📁 Arquivos Gerados

### Launcher

```text
/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
```

Script responsável por exportar as variáveis de ambiente necessárias (`ORACLE_HOME`, `ORACLE_SID`, `TNS_ADMIN`, `DIAG_ADR_ENABLED=OFF`, `TRACE_LEVEL_CLIENT=OFF`, `ADR_BASE=/tmp`, `PATH`) sob a identidade do usuário do banco, chamar o binário `rman` e processar o resumo consolidado de status.

### Scripts RMAN

- **Single Instance:** `~/script/crosscheck_<SID>.rmn`
- **Oracle RAC:** `~/script/crosscheck_rac_<DB_NAME>.rmn`

### Logs de Execução

- **Single Instance:** `~/script/crosscheck_<SID>.log`
- **Oracle RAC:** `~/script/crosscheck_rac_<DB_NAME>.log`

---

## 📊 Exemplo de Saída do Resumo

Ao disparar o launcher gerado, após a execução do RMAN, o resumo analítico é exibido no terminal:

```text
====================================================
            RESUMO DO RMAN CROSSCHECK               
====================================================
Total de objetos verificados : 3465
  - Em status AVAILABLE      : 3465
  - Em status EXPIRED        : 0
----------------------------------------------------
Peças efetivamente deletadas : 0
====================================================
```

---

## 🤖 Automatização

O launcher gerado em `/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh` pode ser chamado diretamente por:

- Jobs agendados no NetBackup (Application Backup / User Directed)
- Agendador do sistema operacional (`crontab`)
- Ferramentas corporativas de automação (Control-M, Rundeck, Ansible)

---

## ✅ Sistemas Operacionais Suportados

- IBM AIX (64-bit)
- Linux (RHEL, SLES, Oracle Linux)[cite: 7]
- Oracle Solaris (SunOS)[cite: 7]

---

## 📚 Requisitos

- Oracle Database 19c ou superior
- Oracle RMAN
- Agente Veritas NetBackup instalado e configurado
- Usuário proprietário do Oracle configurado no sistema operacional
- Oracle Wallet configurada (quando aplicável)[cite: 4]

---

## 🌟 Contribuições

Contribuições são sempre bem-vindas. Sinta-se à vontade para abrir Issues ou Pull Requests com sugestões, melhorias e correções.

---

## ✒️ Autor

**Lucas Pimenta**  
GitHub: [https://github.com/lucastpimenta](https://github.com/lucastpimenta)

---

## 📌 Histórico de Versões

### v3.1

- Desativação do tracing excessivo do cliente Oracle ADR (`DIAG_ADR_ENABLED=OFF` e `TRACE_LEVEL_CLIENT=OFF`), impedindo crescimento de arquivos `.trc` na partição `/oracle`.
- Redirecionamento de diagnósticos residuais para `/tmp` (`ADR_BASE=/tmp`).
- Adição de bloco analisador `awk` compatível com AIX/Linux no launcher para exibição automática de resumo de peças avaliadas, disponíveis e deletadas.
- Atualização do método de download via `python3` com `urllib.request.urlretrieve` validado para IBM AIX.

### v3.0

- Reformulação completa da ferramenta, substituindo passagem manual de parâmetros por interface interativa em linha de comando.
- Suporte nativo completo a **Oracle RAC** com balanceamento e alocação de canais para todos os nós participantes.
- Ordem dos prompts no RAC alinhada à interface Web UI do NetBackup (*Edit database* e *Instances*)[cite: 4, 5].
- Montagem automática do parâmetro `NB_ORA_CATALOG_HOST` a partir do `Database Name` e `Database ID`[cite: 4].
- Suporte a conexões via **Oracle Wallet Connect Descriptors (SCAN)** sem necessidade de arquivo `tnsnames.ora`[cite: 4, 6].
- Validação contextual de permissões em diretórios (`ORACLE_HOME`, `rman` e Wallet) executada diretamente sob a identidade do usuário Oracle, evitando inconsistências ao rodar como `root`.
- Limpeza automática de backups expirados com `DELETE NOPROMPT EXPIRED BACKUP`.

### v2.3

- Removido o parâmetro `NB_ORA_CLIENT`[cite: 7].

### v2.2

- Adicionado suporte à sintaxe `NBU_PRIMARY`.

### v2.1

- Adicionado suporte a múltiplos Oracle Wallets.
- Suporte à sintaxe `SID:WALLET` e `SID:NONE`.

### v2.0

- Adicionado suporte a Oracle Wallet e autenticação local (`NONE`).
- Compatibilidade validada para Linux, Solaris e AIX[cite: 7].
- Correção de problemas de shell e quoting no AIX.

### v1.0

- Primeira versão do gerador de rotinas CrossCheck para Oracle RMAN.
