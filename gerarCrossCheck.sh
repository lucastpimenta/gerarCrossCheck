#!/bin/bash

###############################################################################
# Script   : gerarCrossCheck.sh
# Versao   : 3.1
# Execucao : Como ROOT
# Objetivo : Gerador interativo de scripts RMAN e Launcher para CrossCheck
#            compativel com Veritas NetBackup (Single Instance e RAC).
###############################################################################

# Validacao de execucao como root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERRO: Este script deve ser executado como root."
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
        echo "ERRO: Sistema Operacional '$(uname -s)' nao suportado."
        exit 1
        ;;
esac

echo "============================================================"
echo "    GERADOR DE SCRIPTS RMAN CROSSCHECK (NETBACKUP) v3.1"
echo "============================================================"

# 1. Servidor Primario / Master do NetBackup
read -p "Servidor Primario / Master do NetBackup: " NB_PRIMARY

# 2. Usuario Oracle no SO
while true; do
    read -p "Usuario Oracle no SO: " DB_USER
    if id "$DB_USER" >/dev/null 2>&1; then
        break
    else
        echo "Usuario '$DB_USER' nao existe. Tente novamente."
    fi
done

USER_HOME=$(su - "${DB_USER}" -c 'pwd')
SCRIPT_DIR="${USER_HOME}/script"

mkdir -p "${SCRIPT_DIR}"
chown "${DB_USER}" "${SCRIPT_DIR}"
chmod 750 "${SCRIPT_DIR}"

LAUNCHER="/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh"
mkdir -p "$(dirname "${LAUNCHER}")"

# 3. Topologia do Banco de Dados
echo ""
echo "Topologia do banco de dados:"
echo "  1) Single Instance"
echo "  2) Oracle RAC"
read -p "Opcao: " TOPOLOGIA

# Inicializacao do Launcher
cat > "${LAUNCHER}" <<EOF
#!${BASH_BIN}
# Launcher gerado para CrossCheck RMAN / NetBackup
EOF

if [ "$TOPOLOGIA" == "1" ]; then
    ###########################################################################
    # SINGLE INSTANCE
    ###########################################################################
    while true; do
        read -p "ORACLE_HOME: " DB_HOME
        su - "${DB_USER}" -c "[ -d '${DB_HOME}' ] && [ -x '${DB_HOME}/bin/rman' ]" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            break
        else
            echo "ORACLE_HOME invalido ou binario rman inacessivel para '${DB_USER}'."
        fi
    done

    read -p "ORACLE_SID: " DB_SID
    read -p "Client name no NetBackup: " NB_CLIENT

    echo ""
    echo "Metodo de conexao:"
    echo "  1) Autenticacao SO (/ as sysdba)"
    echo "  2) TNS Alias com Wallet"
    echo "  3) TNS Alias sem Wallet"
    read -p "Opcao: " METODO_CONN

    WALLET_PATH=""
    TNS_ADMIN_EXPORT=""
    if [ "$METODO_CONN" == "2" ]; then
        while true; do
            read -p "Oracle Wallet path: " WALLET_PATH
            su - "${DB_USER}" -c "[ -r '${WALLET_PATH}/cwallet.sso' -o -r '${WALLET_PATH}/ewallet.p12' ]" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                TNS_ADMIN_EXPORT="export TNS_ADMIN=${WALLET_PATH};"
                break
            else
                echo "ERRO: Arquivos da Wallet (cwallet.sso ou ewallet.p12) nao encontrados ou sem permissao de leitura em '${WALLET_PATH}' para o usuario '${DB_USER}'. Tente novamente."
            fi
        done
        read -p "TNS alias: " TNS_ALIAS
        CONNECT_CMD="CONNECT TARGET /@${TNS_ALIAS};"
    elif [ "$METODO_CONN" == "3" ]; then
        read -p "String de conexao: " USER_CONN
        CONNECT_CMD="CONNECT TARGET ${USER_CONN};"
    else
        CONNECT_CMD="CONNECT TARGET /;"
    fi

    RMAN_FILE="${SCRIPT_DIR}/crosscheck_${DB_SID}.rmn"
    LOG_FILE="${SCRIPT_DIR}/crosscheck_${DB_SID}.log"

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

echo "INF - ===================================================="
echo "INF - CrossCheck Single Instance: ${DB_SID}"
echo "INF - ===================================================="
su - ${DB_USER} -c "${BASH_BIN} -c 'export ORACLE_HOME=${DB_HOME}; export ORACLE_SID=${DB_SID}; ${TNS_ADMIN_EXPORT} export PATH=\\\$ORACLE_HOME/bin:\\\$PATH; rman cmdfile=${RMAN_FILE} log=${LOG_FILE}'"
echo "INF - Log gerado em: ${LOG_FILE}"

awk '
/crosschecked backup piece: found to be/ {
    match(\$0, /found to be '\''[A-Z]+'\''/)
    status = substr(\$0, RSTART + 13, RLENGTH - 14)
    total++
    status_count[status]++
}
/deleted backup piece/ { deleted++ }
/Crosschecked [0-9]+ objects/ {
    for(i=1; i<=NF; i++) { if (\$i ~ /^[0-9]+$/) rman_total = \$i }
}
END {
    print "INF - ===================================================="
    print "INF -             RESUMO DO RMAN CROSSCHECK               "
    print "INF - ===================================================="
    printf "INF - Total de objetos verificados : %d\n", (rman_total ? rman_total : total)
    printf "INF -   - Em status AVAILABLE      : %d\n", (status_count["AVAILABLE"] ? status_count["AVAILABLE"] : 0)
    printf "INF -   - Em status EXPIRED        : %d\n", (status_count["EXPIRED"] ? status_count["EXPIRED"] : 0)
    print "INF - ----------------------------------------------------"
    printf "INF - Pecas efetivamente deletadas : %d\n", (deleted ? deleted : 0)
    print "INF - ===================================================="
}
' "${LOG_FILE}"

EOF

else
    ###########################################################################
    # ORACLE RAC - ORDEM DAS TELAS NETBACKUP
    ###########################################################################

    # --- Tela 1: Edit database ---
    read -p "Enter database name / Database unique name: " DB_NAME
    read -p "Database ID: " DB_ID
    
    # Montagem automatica do catalogo
    NB_ORA_CATALOG_HOST="${DB_NAME}_${DB_ID}"

    read -p "Scan name: " SCAN_NAME

    # Leitura do Service name sugerindo o proprio DB_NAME
    read -p "Service name [${DB_NAME}]: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-$DB_NAME}

    # Leitura da porta com fallback para 1521
    read -p "Port [1521]: " SCAN_PORT
    SCAN_PORT=${SCAN_PORT:-1521}

    # Loop de validacao estrita do caminho da Wallet
    while true; do
        read -p "Oracle Wallet path: " WALLET_PATH
        su - "${DB_USER}" -c "[ -r '${WALLET_PATH}/cwallet.sso' -o -r '${WALLET_PATH}/ewallet.p12' ]" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            TNS_ADMIN_EXPORT="export TNS_ADMIN=${WALLET_PATH};"
            break
        else
            echo "ERRO: Arquivos da Wallet (cwallet.sso ou ewallet.p12) nao encontrados ou sem permissao de leitura em '${WALLET_PATH}' para o usuario '${DB_USER}'. Tente novamente."
        fi
    done

    # --- Tela 2: Instances ---
    read -p "Quantidade de instancias do RAC: " TOTAL_NODES

    declare -a ARR_SID
    declare -a ARR_CLIENT
    declare -a ARR_HOME

    DB_NAME_UPPER=$(echo "${DB_NAME}" | tr '[:lower:]' '[:upper:]')
    PREV_HOME=""

    for (( i=1; i<=TOTAL_NODES; i++ ))
    do
        echo "--- Instancia $i ---"

        DEFAULT_SID=$(printf "%s%03d" "${DB_NAME_UPPER}" "$i")
        read -p "Instance name [${DEFAULT_SID}]: " NODE_SID
        NODE_SID=${NODE_SID:-$DEFAULT_SID}

        read -p "Client name: " NODE_CLIENT

        if [ $i -eq 1 ]; then
            read -p "Oracle home: " NODE_HOME
            PREV_HOME="${NODE_HOME}"
        else
            read -p "Oracle home [${PREV_HOME}]: " NODE_HOME
            NODE_HOME=${NODE_HOME:-$PREV_HOME}
            PREV_HOME="${NODE_HOME}"
        fi
        
        ARR_SID+=("$NODE_SID")
        ARR_CLIENT+=("$NODE_CLIENT")
        ARR_HOME+=("$NODE_HOME")
    done

    LOCAL_HOME="${ARR_HOME[0]}"
    su - "${DB_USER}" -c "[ -d '${LOCAL_HOME}' ] && [ -x '${LOCAL_HOME}/bin/rman' ]" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "AVISO: ORACLE_HOME local '${LOCAL_HOME}' nao encontrado ou binario rman inacessivel para '${DB_USER}'."
    fi

    FIRST_SID="${ARR_SID[0]}"
    RMAN_FILE="${SCRIPT_DIR}/crosscheck_rac_${DB_NAME}.rmn"
    LOG_FILE="${SCRIPT_DIR}/crosscheck_rac_${DB_NAME}.log"

    # Monta a conexao utilizando o descritor SCAN
    CONNECT_CMD="CONNECT TARGET '/@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${SCAN_NAME})(PORT=${SCAN_PORT}))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=${SERVICE_NAME})(INSTANCE_NAME=${FIRST_SID}))) as sysbackup';"

    # Montagem do script RMAN
    {
        echo "${CONNECT_CMD}"
        echo ""
        echo "RUN {"
        
        for (( i=0; i<TOTAL_NODES; i++ ))
        do
            CH_NUM=$((i+1))
            CUR_SID="${ARR_SID[$i]}"
            CUR_CLIENT="${ARR_CLIENT[$i]}"
            CUR_HOME="${ARR_HOME[$i]}"
            
            echo "  ALLOCATE CHANNEL ch${CH_NUM} DEVICE TYPE SBT_TAPE"
            echo "  PARMS 'SBT_LIBRARY=${SBT_LIBRARY},"
            echo "  ENV=("
            echo "    NB_ORA_HOME=${CUR_HOME},"
            echo "    NB_ORA_SID=${CUR_SID},"
            echo "    NB_ORA_CLIENT=${CUR_CLIENT}"
            echo "  )';"
        done

        echo ""
        echo "  SEND 'NB_ORA_SERV=${NB_PRIMARY},NB_ORA_CATALOG_HOST=${NB_ORA_CATALOG_HOST}';"
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

echo "INF - ===================================================="
echo "INF - CrossCheck Oracle RAC: ${DB_NAME} (No Primario: ${FIRST_SID})"
echo "INF - ===================================================="
su - ${DB_USER} -c "${BASH_BIN} -c 'export ORACLE_HOME=${LOCAL_HOME}; export ORACLE_SID=${FIRST_SID}; ${TNS_ADMIN_EXPORT} export PATH=\\\$ORACLE_HOME/bin:\\\$PATH; rman cmdfile=${RMAN_FILE} log=${LOG_FILE}'"
echo "INF - Log gerado em: ${LOG_FILE}"

awk '
/crosschecked backup piece: found to be/ {
    match(\$0, /found to be '\''[A-Z]+'\''/)
    status = substr(\$0, RSTART + 13, RLENGTH - 14)
    total++
    status_count[status]++
}
/deleted backup piece/ { deleted++ }
/Crosschecked [0-9]+ objects/ {
    for(i=1; i<=NF; i++) { if (\$i ~ /^[0-9]+$/) rman_total = \$i }
}
END {
    print "INF - ===================================================="
    print "INF -             RESUMO DO RMAN CROSSCHECK               "
    print "INF - ===================================================="
    printf "INF - Total de objetos verificados : %d\n", (rman_total ? rman_total : total)
    printf "INF -   - Em status AVAILABLE      : %d\n", (status_count["AVAILABLE"] ? status_count["AVAILABLE"] : 0)
    printf "INF -   - Em status EXPIRED        : %d\n", (status_count["EXPIRED"] ? status_count["EXPIRED"] : 0)
    print "INF - ----------------------------------------------------"
    printf "INF - Pecas efetivamente deletadas : %d\n", (deleted ? deleted : 0)
    print "INF - ===================================================="
}
' "${LOG_FILE}"

EOF

fi

# Ajuste seguro de permissoes
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
