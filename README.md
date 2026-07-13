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
  - Oracle Wallet
  - Local OS Authentication (`CONNECT TARGET '/'`)
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

### 1. Download do Script

```bash
curl -O https://raw.githubusercontent.com/lucastpimenta/gerarCrossCheck/main/gerarCrossCheck.sh
```

---

## 🚀 Como Usar

### Utilizando Oracle Wallet

```bash
sudo bash gerarCrossCheck.sh <USUARIO_ORACLE> <NB_ORA_CLIENT> <ORACLE_HOME> <ORACLE_WALLET> <ORACLE_SID_1> [<ORACLE_SID_2> ...]​‌
```

### Utilizando Autenticação Local (Sem Wallet)

Informe `NONE` no parâmetro do Wallet:

```bash
sudo bash gerarCrossCheck.sh <USUARIO_ORACLE> <NB_ORA_CLIENT> <ORACLE_HOME> NONE <ORACLE_SID_1> [<ORACLE_SID_2> ...]
```

---

## 📋 Parâmetros

| Parâmetro | Descrição |
|-----------|-----------|
| `USUARIO_ORACLE` | Usuário proprietário do Oracle |
| `NB_ORA_CLIENT` | Cliente NetBackup utilizado pelo RMAN |
| `ORACLE_HOME` | Oracle Home da instância |
| `WALLET_PATH` | Caminho do Oracle Wallet ou `NONE` |
| `SID` | Um ou mais Oracle SID |

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

Ao informar um caminho válido para o Wallet, o script utilizará:

```rman
CONNECT TARGET '/@<SID> AS SYSBACKUP';
```

### Autenticação Local

Ao informar `NONE` (maiúsculo ou minúsculo), o script utilizará:

```rman
CONNECT TARGET '/';
```

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
