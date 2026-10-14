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
- Gera o inicializador executável (launcher):

```text
/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
```

- Gera o arquivo de comandos RMAN com permissões restritas (640):
  - **Single Instance:** `~/script/crosscheck_<SID>.rmn`
  - **Oracle RAC:** `~/script/crosscheck_rac_<DB_NAME>.rmn`
- No **Oracle RAC**, aloca canais simultâneos para todos os nós participantes com seus respectivos `NB_ORA_CLIENT`, evitando falsos positivos de peças expiradas geradas por outros nós.
- Monta automaticamente a diretiva `NB_ORA_CATALOG_HOST` com base no `Database Name` e `Database ID` (`<DB_NAME>_<DB_ID>`), integrando-se nativamente à Web UI do NetBackup.
- Executa as instruções:

```rman
CROSSCHECK BACKUP;
DELETE NOPROMPT EXPIRED BACKUP;
```

- Direciona as saídas para logs dedicados no diretório `~/script/`.

---

## 🛠️ Construído com

- Bash
- Oracle RMAN
- Veritas NetBackup (10.x / 9.x)

---

## 🔧 Instalação

Como o script deve ser executado como `root`, baixe diretamente no servidor desejado.

### Via cURL (se disponível)

```bash
curl -sSL [https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh](https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh) -o /gerarCrossCheck.sh
chmod 755 /gerarCrossCheck.sh
```

### Via Python 3 (alternativa para AIX sem curl/wget)

```bash
python3 -c "import urllib.request, ssl; ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE; open('/gerarCrossCheck.sh', 'wb').write(urllib.request.urlopen('[https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh](https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh)', context=ctx).read())"
chmod 755 /gerarCrossCheck.sh
```

### Via Python 2 (ambientes legados)

```bash
python -c "import urllib2, ssl; ctx = ssl._create_unverified_context(); open('/gerarCrossCheck.sh', 'w').write(urllib2.urlopen('[https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh](https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh)', context=ctx).read())"
chmod 755 /gerarCrossCheck.sh
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
   - Service name
   - Port
   - Oracle Wallet path *(validação de leitura das credenciais pelo usuário Oracle)*
3. **Tela "Instances" (Tabela de Nós do RAC):**
   - Quantidade de instâncias
   - Para cada nó:
     - Instance name
     - Client name (IP ou Hostname registrado no NetBackup)
     - Oracle home

---

## 📁 Arquivos Gerados

### Launcher

```text
/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
```

Script responsável por exportar as variáveis de ambiente necessárias (`ORACLE_HOME`, `ORACLE_SID`, `TNS_ADMIN`, `PATH`) sob a identidade do usuário do banco e chamar o binário `rman`.

### Scripts RMAN

- **Single Instance:** `~/script/crosscheck_<SID>.rmn`
- **Oracle RAC:** `~/script/crosscheck_rac_<DB_NAME>.rmn`

### Logs de Execução

- **Single Instance:** `~/script/crosscheck_<SID>.log`
- **Oracle RAC:** `~/script/crosscheck_rac_<DB_NAME>.log`

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
