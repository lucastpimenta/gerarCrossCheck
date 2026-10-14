#!/bin/bash

###############################################################################
# Script : gerarCrossCheck.sh
# Execução : Como ROOT
# Objetivo : Gerador interativo de scripts RMAN e Launcher para CrossCheck
#            compatível com Veritas NetBackup (Single Instance e RAC).
###############################################################################

# Validação de execução como root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERRO: Este script gerador deve ser executado como root."
    exit 1
fi

# Mapeamento do SO para biblioteca SBT do NetBackup
case "$(uname -s)" in
    Linux)
        SBT_LIBRARY="/usr/openv/netbackup/bin/libobk.so64"
        BASH_BIN="/bin/bash"
        ;;
    SunOS)
        SBT_LIBRARY="/usr/openv/netbackup/bin/libobk.so64.1"
        BASH_BIN="/bin/bash"
        ;;
    AIX)
        SBT_LIBRARY="/usr/openv/netbackup/bin/libobk.a64(shr.o)"
        BASH_BIN="/usr/bin/bash"
        ;;
    *)
        echo "ERRO: Sistema Operacional '$(uname -s)' não suportado."
        exit 1
        ;;
esac

echo "============================================================"
echo "    GERADOR DE SCRIPTS RMAN CROSSCHECK (NETBACKUP)"
echo "============================================================"

# Usuário de banco no SO
while true; do
    read -p "Usuário do Banco no SO (ex: oracle): " DB_USER
    if id "$DB_USER" >/dev/null 2>&1; then
        break
    else
        echo "Usuário '$DB_USER' não encontrado no sistema. Tente novamente."
    fi
done

# ORACLE_HOME validado diretamente pelo usuário do banco
while true; do
    read -p "ORACLE_HOME (ex: /u01/app/oracle/product/19.0.0/dbhome_1): " DB_HOME
    
    su - "${DB_USER}" -c "[ -d '${DB_HOME}' ] && [ -x '${DB_HOME}/bin/rman' ]" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "-> ORACLE_HOME validado com sucesso para o usuário ${DB_USER}."
        break
    else
        echo "ERRO: O usuário ${DB_USER} não tem acesso ao diretório ou ao binário ${DB_HOME}/bin/rman."
    fi
done

read -p "Servidor Primário / Master do NetBackup: " NB_PRIMARY

# Obtém a pasta home do usuário
USER_HOME=$(su - "${DB_USER}" -c 'pwd')
SCRIPT_DIR="${USER_HOME}/script"

mkdir -p "${SCRIPT_DIR}"
chown "${DB_USER}" "${SCRIPT_DIR}"
chmod 750 "${SCRIPT_DIR}"

LAUNCHER="/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh"
mkdir -p "$(dirname "${LAUNCHER}")"

echo ""
echo "Selecione a topologia do banco de dados:"
echo "  1) Single Instance"
echo "  2) Oracle RAC"
read -p "Opção [1 ou 2]: " TOPOLOGIA

echo ""
echo "Método de autenticação / conexão no banco:"
if [ "$TOPOLOGIA" == "1" ]; then
    echo "  1) Autenticação SO (/ as sysdba)"
    echo "  2) TNS Alias (com ou sem Wallet)"
else
    echo "  1) Oracle Wallet SEM TNS (Connect Descriptor SCAN / Padrão NetBackup)"
    echo "  2) TNS Alias (utilizando tnsnames.ora existente)"
fi
read -p "Opção de conexão: " METODO_CONN

# Tratamento de Wallet
WALLET_PATH=""
TNS_ADMIN_EXPORT=""

if [ "$TOPOLOGIA" == "2" ] && [ "$METODO_CONN" == "1" ]; then
    USAR_WALLET="s"
else
    read -p "Utiliza Oracle Wallet para este banco? [s/n]: " USAR_WALLET
fi

if [[ "$USAR_WALLET" =~ ^[sS]$ ]]; then
    while true; do
        read -p "Caminho do diretório da Wallet: " WALLET_PATH
        su - "${DB_USER}" -c "[ -r '${WALLET_PATH}/cwallet.sso' -o -r '${WALLET_PATH}/ewallet.p12' ]" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "-> Credenciais de Wallet validadas para ${DB_USER}."
            TNS_ADMIN_EXPORT="export TNS_ADMIN=${WALLET_PATH};"
            break
        else
            echo "AVISO: O usuário ${DB_USER} não conseguiu ler o arquivo de wallet em '${WALLET_PATH}'."
            read -p "Deseja continuar com esse caminho mesmo assim? [s/n]: " FORCAR_W
            if [[ "$FORCAR_W" =~ ^[sS]$ ]]; then
                TNS_ADMIN_EXPORT="export TNS_ADMIN=${WALLET_PATH};"
                break
            fi
        fi
    done
fi

# Inicialização do script Launcher
cat > "${LAUNCHER}" <<EOF
#!${BASH_BIN}
# Launcher gerado para CrossCheck RMAN / NetBackup
EOF

if [ "$TOPOLOGIA" == "1" ]; then
    ###########################################################################
    # SINGLE INSTANCE
    ###########################################################################
    read -p "Informe o ORACLE_SID: " DB_SID
    read -p "Nome do Cliente no NetBackup (Hostname ou IP do nó): " NB_CLIENT

    RMAN_FILE="${SCRIPT_DIR}/crosscheck_${DB_SID}.rmn"
    LOG_FILE="${SCRIPT_DIR}/crosscheck_${DB_SID}.log"

    if [ "$METODO_CONN" == "1" ]; then
        CONNECT_CMD="CONNECT TARGET /;"
    else
        read -p "Alias TNS de conexão: " TNS_ALIAS
        CONNECT_CMD="CONNECT TARGET /@${TNS_ALIAS};"
    fi

    cat > "${RMAN_FILE}" <<EOF
${CONNECT_CMD}

RUN {
  ALLOCATE CHANNEL ch1 DEVICE TYPE SBT_TAPE
  PARMS 'SBT_LIBRARY=${SBT_LIBRARY},
  ENV=(
    NB_ORA_HOME=${DB_HOME},
    NB_ORA_SID=${DB_SID},
    NB_ORA_CLIENT=${NB_CLIENT}
  )';

  SEND 'NB_ORA_SERV=${NB_PRIMARY}';

  CROSSCHECK BACKUP;
  DELETE NOPROMPT EXPIRED BACKUP;

  RELEASE CHANNEL ch1;
}
EXIT;
EOF

    cat >> "${LAUNCHER}" <<EOF

echo "===================================================="
echo "CrossCheck Single Instance: ${DB_SID}"
echo "===================================================="
su - ${DB_USER} -c "${BASH_BIN} -c 'export ORACLE_HOME=${DB_HOME}; export ORACLE_SID=${DB_SID}; ${TNS_ADMIN_EXPORT} export PATH=\\\$ORACLE_HOME/bin:\\\$PATH; rman cmdfile=${RMAN_FILE} log=${LOG_FILE}'"
echo "Log gerado em: ${LOG_FILE}"

EOF

else
    ###########################################################################
    # ORACLE RAC
    ###########################################################################
    read -p "Database Name ou Unique Name: " DB_NAME
    read -p "Identificador de Catálogo no NetBackup (NB_ORA_CATALOG_HOST / deixe vazio se não houver): " NB_CAT_HOST
    read -p "Quantidade de nós/instâncias no RAC: " TOTAL_NODES

    declare -a ARR_SID
    declare -a ARR_CLIENT

    for (( i=1; i<=TOTAL_NODES; i++ ))
    do
        echo "--- Instância / Nó $i ---"
        read -p "  ORACLE_SID da instância $i: " NODE_SID
        read -p "  Nome do Cliente no NetBackup para o nó $i (Hostname ou IP): " NODE_CLIENT
        ARR_SID+=("$NODE_SID")
        ARR_CLIENT+=("$NODE_CLIENT")
    done

    FIRST_SID="${ARR_SID[0]}"
    RMAN_FILE="${SCRIPT_DIR}/crosscheck_rac_${DB_NAME}.rmn"
    LOG_FILE="${SCRIPT_DIR}/crosscheck_rac_${DB_NAME}.log"

    if [ "$METODO_CONN" == "1" ]; then
        read -p "Hostname ou FQDN do SCAN: " SCAN_HOST
        read -p "Porta do SCAN [Padrão 1521]: " SCAN_PORT
        SCAN_PORT=${SCAN_PORT:-1521}
        read -p "Service Name do banco: " SRV_NAME
        
        CONNECT_CMD="CONNECT TARGET '/@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${SCAN_HOST})(PORT=${SCAN_PORT}))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=${SRV_NAME})(INSTANCE_NAME=${FIRST_SID}))) as sysbackup';"
    else
        read -p "Alias TNS existente para conexão: " TNS_ALIAS
        CONNECT_CMD="CONNECT TARGET /@${TNS_ALIAS};"
    fi

    SEND_DIRECTIVE="NB_ORA_SERV=${NB_PRIMARY}"
    if [ -n "${NB_CAT_HOST}" ]; then
        SEND_DIRECTIVE="${SEND_DIRECTIVE},NB_ORA_CATALOG_HOST=${NB_CAT_HOST}"
    fi

    # Monta arquivo RMAN com um canal por nó do RAC
    {
        echo "${CONNECT_CMD}"
        echo ""
        echo "RUN {"
        
        for (( i=0; i<TOTAL_NODES; i++ ))
        do
            CH_NUM=$((i+1))
            CUR_SID="${ARR_SID[$i]}"
            CUR_CLIENT="${ARR_CLIENT[$i]}"
            
            echo "  ALLOCATE CHANNEL ch${CH_NUM} DEVICE TYPE SBT_TAPE"
            echo "  PARMS 'SBT_LIBRARY=${SBT_LIBRARY},"
            echo "  ENV=("
            echo "    NB_ORA_HOME=${DB_HOME},"
            echo "    NB_ORA_SID=${CUR_SID},"
            echo "    NB_ORA_CLIENT=${CUR_CLIENT}"
            echo "  )';"
        done

        echo ""
        echo "  SEND '${SEND_DIRECTIVE}';"
        echo ""
        echo "  CROSSCHECK BACKUP;"
        echo "  DELETE NOPROMPT EXPIRED BACKUP;"
        echo ""

        for (( i=0; i<TOTAL_NODES; i++ ))
        do
            CH_NUM=$((i+1))
            echo "  RELEASE CHANNEL ch${CH_NUM};"
        done

        echo "}"
        echo "EXIT;"
    } > "${RMAN_FILE}"

    cat >> "${LAUNCHER}" <<EOF

echo "===================================================="
echo "CrossCheck Oracle RAC: ${DB_NAME} (Nó Primário: ${FIRST_SID})"
echo "===================================================="
su - ${DB_USER} -c "${BASH_BIN} -c 'export ORACLE_HOME=${DB_HOME}; export ORACLE_SID=${FIRST_SID}; ${TNS_ADMIN_EXPORT} export PATH=\\\$ORACLE_HOME/bin:\\\$PATH; rman cmdfile=${RMAN_FILE} log=${LOG_FILE}'"
echo "Log gerado em: ${LOG_FILE}"

EOF

fi

# Ajuste seguro de permissões
chown "${DB_USER}" "${RMAN_FILE}"
chmod 640 "${RMAN_FILE}"
chmod 755 "${LAUNCHER}"

echo ""
echo "===================================================="
echo "Arquivos gerados com sucesso!"
echo "===================================================="
echo "Launcher:    ${LAUNCHER}"
echo "Script RMAN: ${RMAN_FILE}"
echo ""
echo "Para executar o crosscheck gerado, rode:"
echo "  ${LAUNCHER}"
