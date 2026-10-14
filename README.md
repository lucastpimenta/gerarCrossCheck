# gerarCrossCheck.sh

Script interativo para automatizar a geração de rotinas RMAN CrossCheck em ambientes Oracle integrados ao Veritas NetBackup.

O objetivo é simplificar a validação e a limpeza de backups expirados registrados no repositório do RMAN, suportando ambientes **Single Instance** e **Oracle RAC** com autenticação via Oracle Wallet (com ou sem TNS) ou autenticação local do sistema operacional.

---

## 📦 O que o Script Faz

- Detecta automaticamente o sistema operacional (**Linux**, **Solaris** ou **AIX**).
- Configura dinamicamente a biblioteca SBT (`libobk`) adequada para cada plataforma:
  - Linux: `/usr/openv/netbackup/bin/libobk.so64`
  - Solaris: `/usr/openv/netbackup/bin/libobk.so64.1`
  - AIX: `/usr/openv/netbackup/bin/libobk.a64(shr.o)`
- Executa validações de permissões diretamente com o usuário Oracle informado (`$DB_USER`), mesmo sendo disparado como `root`.
- Desativa automaticamente traces excessivos de diagnóstico do cliente ADR e Net8 (`DIAG_ADR_ENABLED=OFF` e `TRACE_LEVEL_CLIENT=OFF`), evitando consumo descontrolado de espaço na partição `/oracle`.
- Redireciona eventuais diagnósticos residuais para `/tmp` (`ADR_BASE=/tmp`).
- Gera o inicializador executável (launcher):

```text
/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
```

- Gera o arquivo de comandos RMAN com permissões restritas (640):
  - **Single Instance:** `~/script/crosscheck_<SID>.rmn`
  - **Oracle RAC:** `~/script/crosscheck_rac_<DB_NAME>.rmn`
- No **Oracle RAC**, aloca canais simultâneos para todos os nós participantes com seus respectivos `NB_ORA_CLIENT`, evitando falsos positivos de peças expiradas geradas por outros nós.
- Monta automaticamente a diretiva `NB_ORA_CATALOG_HOST` com base no `Database Name` e `Database ID` (`<DB_NAME>_<DB_ID>`), integrando-se nativamente à Web UI do NetBackup.
- Preenche sugestões automáticas baseadas nas telas do NetBackup:
  - Sugere o `Service name` com o mesmo valor do `Database Name`.
  - Sugere o `Instance name` sequencial formatado (`<DBNAME>001`, `<DBNAME>002`, etc.).
  - Sugere a porta padrão `[1521]` ao pressionar Enter.
  - Reutiliza o primeiro `ORACLE_HOME` digitado como sugestão para os nós seguintes.
- Validação estrita do caminho da Oracle Wallet, bloqueando o avanço enquanto os arquivos (`cwallet.sso` ou `ewallet.p12`) não forem encontrados com permissão de leitura para o usuário Oracle.
- Executa as instruções:

```rman
CROSSCHECK BACKUP;
DELETE NOPROMPT EXPIRED BACKUP;
```

- Exibe automaticamente na tela um resumo consolidado ao término da execução via `awk`, computando o total de objetos checados, peças em status `AVAILABLE`, peças em status `EXPIRED` e peças removidas.
- Direciona os logs detalhados para o diretório `~/script/`.

---

## 🛠️ Construído com

- Bash
- Oracle RMAN
- Veritas NetBackup (10.x / 9.x)

---

## 🔧 Instalação

Execute como `root` no servidor desejado.

### Método Recomendado (Python 3 - IBM AIX)

```text
python3 -c "import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh','gerarCrossCheck.sh')"
```

```text
chmod 755 gerarCrossCheck.sh
```

### Método Alternativo (cURL - Linux)

```text
curl -sSL https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh -o gerarCrossCheck.sh
```

```text
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
   - Servidor Primário / Master do NetBackup
   - Usuário Oracle no SO (valida se o usuário existe)
   - Topologia: selecionar `2) Oracle RAC`
2. **Tela "Edit database" (Configurações Gerais):**
   - Enter database name / Database unique name
   - Database ID *(o script concatena `<DB_NAME>_<DB_ID>` para o catálogo)*
   - Scan name
   - Service name *(sugere o Database Name informado)*
   - Port [1521] *(sugere 1521 ao pressionar Enter)*
   - Oracle Wallet path *(validação estrita em loop pelo usuário Oracle)*
3. **Tela "Instances" (Tabela de Nós do RAC):**
   - Quantidade de instâncias do RAC
   - Para cada nó:
     - Instance name *(sugestão em maiúsculas: DBNAME001, DBNAME002, etc.)*
     - Client name (IP ou Hostname registrado no NetBackup)
     - Oracle home *(a partir do nó 2, sugere o valor do nó anterior)*

---

## 📁 Arquivos Gerados

### Launcher

```text
/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
```

Script responsável por exportar as variáveis de ambiente necessárias (`ORACLE_HOME`, `ORACLE_SID`, `TNS_ADMIN`, `DIAG_ADR_ENABLED=OFF`, `TRACE_LEVEL_CLIENT=OFF`, `ADR_BASE=/tmp`, `PATH`) sob a identidade do usuário do banco, chamar o binário `rman` e processar o resumo consolidado de status via `awk`.

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
- Linux (RHEL, SLES, Oracle Linux)
- Oracle Solaris (SunOS)

---

## 📚 Requisitos

- Oracle Database 19c ou superior
- Oracle RMAN
- Agente Veritas NetBackup instalado e configurado
- Usuário proprietário do Oracle configurado no sistema operacional
- Oracle Wallet configurada (quando aplicável)

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
- Validação estrita em loop para o caminho da Oracle Wallet (impede prosseguir com caminho inválido).
- Sugestões inteligentes ao pressionar Enter:
  - Sugestão do `Service name` com base no `Database name`.
  - Sugestão da porta padrão `[1521]`.
  - Sugestão de `Instance name` formatado sequencialmente (`DBNAME001`, `DBNAME002`...).
  - Sugestão de reaproveitamento do `Oracle home` entre os nós do RAC.
- Atualização do método de download via `python3` com comando isolado para IBM AIX.

### v3.0

- Reformulação completa da ferramenta, substituindo passagem manual de parâmetros por interface interativa em linha de comando.
- Suporte nativo completo a **Oracle RAC** com balanceamento e alocação de canais para todos os nós participantes.
- Ordem dos prompts no RAC alinhada à interface Web UI do NetBackup (*Edit database* e *Instances*).
- Montagem automática do parâmetro `NB_ORA_CATALOG_HOST` a partir do `Database Name` e `Database ID`.
- Suporte a conexões via **Oracle Wallet Connect Descriptors (SCAN)** sem necessidade de arquivo `tnsnames.ora`.
- Validação contextual de permissões em diretórios (`ORACLE_HOME`, `rman` e Wallet) executada diretamente sob a identidade do usuário Oracle, evitando inconsistências ao rodar como `root`.
- Limpeza automática de backups expirados com `DELETE NOPROMPT EXPIRED BACKUP`.

### v2.3

- Removido o parâmetro `NB_ORA_CLIENT`.

### v2.2

- Adicionado suporte à sintaxe `NBU_PRIMARY`.

### v2.1

- Adicionado suporte a múltiplos Oracle Wallets.
- Suporte à sintaxe `SID:WALLET` e `SID:NONE`.

### v2.0

- Adicionado suporte a Oracle Wallet e autenticação local (`NONE`).
- Compatibilidade validada para Linux, Solaris e AIX.
- Correção de problemas de shell e quoting no AIX.

### v1.0

- Primeira versão do gerador de rotinas CrossCheck para Oracle RMAN.
