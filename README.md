# gerarCrossCheck.sh

Script para automatizar a criação de rotinas RMAN CrossCheck em ambientes Oracle integrados ao Veritas NetBackup.

O objetivo é simplificar a validação e limpeza de backups expirados registrados no RMAN, utilizando autenticação por Oracle Wallet ou autenticação local do sistema operacional.

---

## 📦 O que o Script Faz

- Detecta automaticamente o sistema operacional (Linux, Solaris ou AIX).
- Configura automaticamente a biblioteca SBT (`libobk`) adequada para o NetBackup.
- Gera o launcher:

```text
/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
```

- Gera um arquivo RMAN para cada SID informado:

```text
~/script/crosscheck_<SID>.rmn
```

- Configura automaticamente as variáveis de ambiente Oracle durante a execução.
- Suporta autenticação:
  - Oracle Wallet por banco
  - Local OS Authentication (`CONNECT TARGET '/'`)
- Permite utilizar múltiplos bancos com wallets diferentes na mesma execução.
- Executa as rotinas:

```rman
CROSSCHECK BACKUP;

DELETE EXPIRED BACKUP;
```

- Gera um log separado para cada banco Oracle.

---

## 🛠️ Construído com

- Bash
- Oracle RMAN
- Veritas NetBackup

---

## 🔧 Instalação

### Download do Script

```bash
curl -O https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh
```

---

## 🚀 Como Usar

### Sintaxe

```bash
sudo bash gerarCrossCheck.sh \
<USUARIO_ORACLE> \
<NB_ORA_CLIENT> \
<ORACLE_HOME> \
<SID1:WALLET|NONE> \
[SID2:WALLET|NONE] ...
```

### Exemplo com Oracle Wallet

```bash
sudo bash gerarCrossCheck.sh \
oracle \
cliente-netbackup \
/u01/app/oracle/product/19.0.0/dbhome_1 \
PRD:/u01/wallets/prd \
HML:/u01/wallets/hml
```

### Exemplo sem Oracle Wallet

```bash
sudo bash gerarCrossCheck.sh \
oracle \
cliente-netbackup \
/u01/app/oracle/product/19.0.0/dbhome_1 \
PRD:NONE \
DEV:NONE
```

### Exemplo misto

```bash
sudo bash gerarCrossCheck.sh \
oracle \
cliente-netbackup \
/u01/app/oracle/product/19.0.0/dbhome_1 \
PRD:/u01/wallets/prd \
HML:/u01/wallets/hml \
DEV:NONE
```

---

## 📋 Parâmetros

| Parâmetro | Descrição |
|-----------|-----------|
| `USUARIO_ORACLE` | Usuário proprietário do Oracle |
| `NB_ORA_CLIENT` | Cliente NetBackup utilizado pelo RMAN |
| `ORACLE_HOME` | Oracle Home da instância |
| `SID:WALLET` | SID Oracle seguido do caminho do Wallet |
| `SID:NONE` | Utiliza autenticação local do sistema operacional para o SID informado |

---

## 📁 Arquivos Gerados

### Launcher

```text
/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
```

Responsável por executar o RMAN para todos os bancos informados.

### Scripts RMAN

```text
~/script/crosscheck_<SID>.rmn
```

### Logs

```text
~/script/crosscheck_<SID>.log
```

---

## 🤖 Automatização

O script foi projetado para ser utilizado em:

- Jobs do NetBackup
- Cron Jobs
- Agendadores corporativos
- Rotinas periódicas de manutenção RMAN

---

## ✅ Sistemas Operacionais Suportados

- Linux
- Solaris
- AIX

---

## 📚 Requisitos

- Oracle Database 19c ou superior
- Oracle RMAN
- Veritas NetBackup
- Usuário Oracle configurado
- Oracle Wallet configurado (opcional)

---

## 📝 Observações

### Oracle Wallet

Para um SID configurado com Wallet:

```bash
PRD:/u01/wallets/prd
```

o script utilizará:

```rman
CONNECT TARGET '/@PRD AS SYSBACKUP';
```

e exportará automaticamente:

```bash
export TNS_ADMIN=/u01/wallets/prd
```

### Autenticação Local

Para um SID configurado com:

```bash
PRD:NONE
```

o script utilizará:

```rman
CONNECT TARGET '/';
```

sem necessidade de Oracle Wallet.

### Suporte a Ambientes Heterogêneos

É possível executar múltiplos bancos na mesma chamada utilizando métodos de autenticação diferentes:

```text
PRD:/wallet/prd
HML:/wallet/hml
DEV:NONE
```

Cada SID terá seu próprio arquivo RMAN, variáveis de ambiente e método de conexão.

---

## 🆘 Suporte

Antes de abrir uma issue ou solicitar suporte, valide:

- ORACLE_HOME configurado corretamente
- Oracle Wallet funcional (quando utilizado)
- Biblioteca NetBackup (`libobk`) disponível
- Conectividade RMAN com a instância Oracle
- Permissões do usuário Oracle

Os logs são gravados em:

```text
~/script/crosscheck_<SID>.log
```

---

## 🌟 Contribuições

Contribuições são sempre bem-vindas.

Sinta-se à vontade para abrir Issues ou Pull Requests com melhorias, correções ou novas funcionalidades.

---

## ✒️ Autor

**Lucas Pimenta**

GitHub: <https://github.com/lucastpimenta>

---

## 📌 Histórico Recente

### v2.1

- Adicionado suporte a múltiplos Oracle Wallets.
- Cada SID pode utilizar um Wallet diferente.
- Adicionado suporte à sintaxe `SID:WALLET`.
- Adicionado suporte à sintaxe `SID:NONE`.
- Possibilidade de misturar autenticação por Wallet e autenticação local na mesma execução.

### v2.0

- Adicionado suporte a Oracle Wallet.
- Adicionado suporte a autenticação local (`NONE`).
- Compatibilidade validada para Linux, Solaris e AIX.
- Correção da sintaxe RMAN para Oracle 19c.
- Correção de problemas de execução em AIX relacionados a shell e quoting.
- Inclusão da rotina:

```rman
CROSSCHECK BACKUP;

DELETE EXPIRED BACKUP;
```

### v1.0

- Primeira versão do gerador de rotinas CrossCheck para Oracle RMAN.
