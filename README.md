# gerarCrossCheck.sh
Este script é destinado a automatizar a criação de um script para executar rotinas de CrossCheck em ambientes Oracle, facilitando a manutenção de backups Oracle com o NetBackup.

## 📦 O que o Script Faz
Verifica se pelo menos 4 argumentos foram fornecidos.
Determina o sistema operacional para ajustar a variável SBT_LIBRARY adequadamente.
Cria o script crosscheck.sh no diretório /usr/openv/netbackup/ext/db_ext/oracle/, que executará a rotina CrossCheck para cada ORACLE_SID fornecido.
Cria o arquivo crosscheck.rmn no diretório do usuário Oracle, que contém os comandos RMAN necessários para a rotina CrossCheck.

## 🛠️ Construído com
Bash - Shell Unix e linguagem de script

Oracle RMAN - Oracle Recovery Manager

## 🚀 Como Usar
Para executar este script, você precisa passar pelo menos 4 argumentos: `USUARIO_ORACLE`, `NB_ORA_CLIENT`, `ORACLE_HOME`, e um ou mais `ORACLE_SID`.
```bash
sudo sh gerarCrossCheck.sh <USUARIO_ORACLE> <NB_ORA_CLIENT> <ORACLE_HOME> <ORACLE_SID_1> [<ORACLE_SID_2> ...]
```
## 📁 Arquivos Gerados
Script Bash (crosscheck.sh): Executa o RMAN crosscheck para cada instância Oracle especificada.
Script RMAN (crosscheck.rmn): Contém comandos RMAN para realizar o crosscheck e deletar backups expirados.
Logs: Um arquivo de log separado para cada SID Oracle, seguindo o padrão crosscheck_<ORACLE_SID>.log.

## 🤖 Automatização
Este script foi criado para ser usado em jobs do NetBackup para executar rotinas de CrossCheck regularmente sem intervenção manual.

## 📝 Sistema Operacional Suportado
Este script foi testado em ambientes Solaris e Linux.

## 🆘 Suporte
Para suporte, comece verificando se você seguiu todas as instruções corretamente. Se o problema persistir, considere consultar a documentação do Oracle e do NetBackup para configurações adicionais.

## 🌟 Contribuições
Contribuições são sempre bem-vindas! Se você tem uma sugestão para melhorar este script, sinta-se à vontade para criar um pull request.

## ✒️ Autor
[Lucas Pimenta](https://github.com/lucastpimenta) - Trabalho Inicial
