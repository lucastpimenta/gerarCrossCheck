#!/bin/bash

###############################################################################
# Script   : gerarCrossCheck.sh
# Versao   : 3.2
# Execucao : Como ROOT
# Objetivo : Gerador de scripts RMAN e Launcher para CrossCheck (NetBackup).
# Suporte  : Interativo e Nao-Interativo (--silent / --config).
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

# Valores padrao
SILENT=0
CONFIG_FILE=""
SCAN_PORT="1521"
TOPOLOGIA=""
METODO_CONN="1"

# Funcao de exibicao de ajuda
usage() {
    cat <<EOF
Uso: $0 [OPCOES]

Modos:
  Sem opcoes: Execucao interativa completa

Opcoes para Modo Silencioso:
  --silent                     Ativa o modo nao-interativo
  --config <arquivo>           Carrega parametros a partir de um arquivo .conf
  --master <servidor>          Primary / Master Server do NetBackup
  --user <usuario>             Usuario Oracle no SO (ex: oracle)
  --type <single|rac>          Tipo de banco de dados
  --home <caminho>             ORACLE_HOME (apenas Single Instance)
  --sid <sid>                  ORACLE_SID (apenas Single Instance)
  --client <nome_client>       Client name no NetBackup (apenas Single Instance)
  --method <1|2|3>             Metodo de conexao Single: 1=SO, 2=Wallet, 3=String
  --dbname <nome>              Database Name / Unique Name (apenas RAC)
  --dbid <id>                  Database ID (apenas RAC)
  --scan <scan_name>           SCAN host do RAC
  --service <service_name>     Service Name do RAC (padrao: dbname)
  --port <porta>               Porta do Listener (padrao: 1521)
  --wallet <caminho>           Diretorio do Oracle Wallet (se metodo 2 ou RAC)
  --alias <tns_alias>          TNS alias (se metodo 2 em Single Instance)
  --conn-str <string>          String de conexao (se metodo 3 em Single Instance)
  --nodes "<lista_nos>"        Lista de nos do RAC separados por virgula:
                               Formato: "SID:CLIENT:HOME,SID:CLIENT:HOME"
                               Exemplo: "BWP001:10.27.241.210:/oracle/BWP/19.0.0,BWP002:10.27.241.215:/oracle/BWP/19.0.0"
  -h, --help                   Exibe esta ajuda

EOF
    exit 1
}

# Leitura dos argumentos de linha de comando
while [ $# -gt 0 ]; do
    case "$1" in
        --silent) SILENT=1; shift ;;
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --master) NB_PRIMARY="$2"; shift 2 ;;
        --user) DB_USER="$2"; shift 2 ;;
        --type)
            case "$(echo "$2" | tr '[:upper:]' '[:lower:]')" in
                single|1) TOPOLOGIA="1" ;;
                rac|2) TOPOLOGIA="2" ;;
                *) echo "ERRO: Tipo invalido '$2'. Use 'single' ou 'rac'."; exit 1 ;;
            esac
            shift 2 ;;
        --home) DB_HOME="$2"; shift 2 ;;
        --sid) DB_SID="$2"; shift 2 ;;
        --client) NB_CLIENT="$2"; shift 2 ;;
        --method) METODO_CONN="$2"; shift 2 ;;
        --dbname) DB_NAME="$2"; shift 2 ;;
        --dbid) DB_ID="$2"; shift 2 ;;
        --scan) SCAN_NAME="$2"; shift 2 ;;
        --service) SERVICE_NAME="$2"; shift 2 ;;
        --port) SCAN_PORT="$2"; shift 2 ;;
        --wallet) WALLET_PATH="$2"; shift 2 ;;
        --alias) TNS_ALIAS="$2"; shift 2 ;;
        --conn-str) USER_CONN="$2"; shift 2 ;;
        --nodes) RAC_NODES="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Parametro desconhecido: $1"; usage ;;
    esac
done

# Carrega parametros de arquivo de configuracao se informado
if [ -n "$CONFIG_FILE" ]; then
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
        SILENT=1
    else
        echo "ERRO: Arquivo de configuracao '$CONFIG_FILE' nao encontrado."
        exit 1
    fi
fi

echo "============================================================"
echo "    GERADOR DE SCRIPTS RMAN CROSSCHECK (NETBACKUP) v3.2"
echo "============================================================"

# 1. Master Server
if [ $SILENT -eq 1 ]; then
    [ -z "$NB_PRIMARY" ] && { echo "ERRO: --master e obrigatorio em modo silent."; exit 1; }
else
    read -p "Servidor Primario / Master do NetBackup: " NB_PRIMARY
fi

# 2. Usuario Oracle no SO
if [ $SILENT -eq 1 ]; then
    [ -z "$DB_USER" ] && { echo "ERRO: --user e obrigatorio em modo silent."; exit 1; }
    if ! id "$DB_USER" >/dev/null 2>&1; then
        echo "ERRO: Usuario '$DB_USER' nao existe no SO."
        exit 1
    fi
else
    while true; do
        read -p "Usuario Oracle no SO: " DB_USER
        if id "$DB_USER" >/dev/null 2>&1; then
            break
        else
            echo "Usuario '$DB_USER' nao existe. Tente novamente."
        fi
    done
fi

USER_HOME=$(su - "${DB_USER}" -c 'pwd')
SCRIPT_DIR="${USER_HOME}/script"

mkdir -p "${SCRIPT_DIR}"
chown "${DB_USER}" "${SCRIPT_DIR}"
chmod 750 "${SCRIPT_DIR}"

LAUNCHER="/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh"
mkdir -p "$(dirname "${LAUNCHER}")"

# 3. Topologia do Banco de Dados
if [ $SILENT -eq 0 ]; then
    echo ""
    echo "Topologia do banco de dados:"
    echo "  1) Single Instance"
    echo "  2) Oracle RAC"
    read -p "Opcao: " TOPOLOGIA
fi

[ -z "$TOPOLOGIA" ] && { echo "ERRO: Topologia (--type) nao informada."; exit 1; }

# Inicializacao do Launcher
cat > "${LAUNCHER}" <<EOF
#!${BASH_BIN}
# Launcher gerado para CrossCheck RMAN / NetBackup
EOF

if [ "$TOPOLOGIA" == "1" ]; then
    ###########################################################################
    # SINGLE INSTANCE
    ###########################################################################
    if [ $SILENT -eq 1 ]; then
        [ -z "$DB_HOME" ] && { echo "ERRO: --home e obrigatorio para Single Instance."; exit 1; }
        [ -z "$DB_SID" ] && { echo "ERRO: --sid e obrigatorio para Single Instance."; exit 1; }
        [ -z "$NB_CLIENT" ] && { echo "ERRO: --client e obrigatorio para Single Instance."; exit 1; }
        
        su - "${DB_USER}" -c "[ -d '${DB_HOME}' ] && [ -x '${DB_HOME}/bin/rman' ]" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "ERRO: ORACLE_HOME invalido ou binario rman inacessivel para '${DB_USER}'."
            exit 1
        fi
    else
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
    fi

    TNS_ADMIN_EXPORT=""
    if [ "$METODO_CONN" == "2" ]; then
        if [ $SILENT -eq 1 ]; then
            [ -z "$WALLET_PATH" ] && { echo "ERRO: --wallet e obrigatorio para metodo 2."; exit 1; }
            [ -z "$TNS_ALIAS" ] && { echo "ERRO: --alias e obrigatorio para metodo 2."; exit 1; }
            su - "${DB_USER}" -c "[ -r '${WALLET_PATH}/cwallet.sso' -o -r '${WALLET_PATH}/ewallet.p12' ]" >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo "ERRO: Arquivos da Wallet nao encontrados ou sem permissao em '${WALLET_PATH}'."
                exit 1
            fi
        else
            while true; do
                read -p "Oracle Wallet path: " WALLET_PATH
                su - "${DB_USER}" -c "[ -r '${WALLET_PATH}/cwallet.sso' -o -r '${WALLET_PATH}/ewallet.p12' ]" >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    break
                else
                    echo "ERRO: Arquivos da Wallet nao encontrados ou sem permissao em '${WALLET_PATH}'. Tente novamente."
                fi
            done
            read -p "TNS alias: " TNS_ALIAS
        fi
        TNS_ADMIN_EXPORT="export TNS_ADMIN=${WALLET_PATH};"
        CONNECT_CMD="CONNECT TARGET /@${TNS_ALIAS};"
    elif [ "$METODO_CONN" == "3" ]; then
        if [ $SILENT -eq 1 ]; then
            [ -z "$USER_CONN" ] && { echo "ERRO: --conn-str e obrigatorio para metodo 3."; exit 1; }
        else
            read -p "String de conexao: " USER_CONN
        fi
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
    # ORACLE RAC
    ###########################################################################
    if [ $SILENT -eq 1 ]; then
        [ -z "$DB_NAME" ] && { echo "ERRO: --dbname e obrigatorio para RAC."; exit 1; }
        [ -z "$DB_ID" ] && { echo "ERRO: --dbid e obrigatorio para RAC."; exit 1; }
        [ -z "$SCAN_NAME" ] && { echo "ERRO: --scan e obrigatorio para RAC."; exit 1; }
        [ -z "$WALLET_PATH" ] && { echo "ERRO: --wallet e obrigatorio para RAC."; exit 1; }
        [ -z "$RAC_NODES" ] && { echo "ERRO: --nodes e obrigatorio em silent para RAC."; exit 1; }

        SERVICE_NAME=${SERVICE_NAME:-$DB_NAME}
        SCAN_PORT=${SCAN_PORT:-1521}

        su - "${DB_USER}" -c "[ -r '${WALLET_PATH}/cwallet.sso' -o -r '${WALLET_PATH}/ewallet.p12' ]" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "ERRO: Arquivos da Wallet nao encontrados ou sem permissao em '${WALLET_PATH}'."
            exit 1
        fi
    else
        read -p "Enter database name / Database unique name: " DB_NAME
        read -p "Database ID: " DB_ID
        read -p "Scan name: " SCAN_NAME
        read -p "Service name [${DB_NAME}]: " SERVICE_NAME
        SERVICE_NAME=${SERVICE_NAME:-$DB_NAME}
        read -p "Port [1521]: " SCAN_PORT
        SCAN_PORT=${SCAN_PORT:-1521}

        while true; do
            read -p "Oracle Wallet path: " WALLET_PATH
            su - "${DB_USER}" -c "[ -r '${WALLET_PATH}/cwallet.sso' -o -r '${WALLET_PATH}/ewallet.p12' ]" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                break
            else
                echo "ERRO: Arquivos da Wallet nao encontrados em '${WALLET_PATH}' para o usuario '${DB_USER}'. Tente novamente."
            fi
        done
    fi

    NB_ORA_CATALOG_HOST="${DB_NAME}_${DB_ID}"
    TNS_ADMIN_EXPORT="export TNS_ADMIN=${WALLET_PATH};"

    declare -a ARR_SID
    declare -a ARR_CLIENT
    declare -a ARR_HOME

    DB_NAME_UPPER=$(echo "${DB_NAME}" | tr '[:lower:]' '[:upper:]')

    if [ $SILENT -eq 1 ]; then
        # Parse da string de nós (ex: "BWP001:10.27.241.210:/oracle/BWP/19.0.0,BWP002:10.27.241.215:/oracle/BWP/19.0.0")
        IFS=',' read -r -a NODE_LIST <<< "$RAC_NODES"
        TOTAL_NODES=${#NODE_LIST[@]}
        idx=1
        for node_item in "${NODE_LIST[@]}"; do
            IFS=':' read -r p1 p2 p3 <<< "$node_item"
            if [ -n "$p3" ]; then
                ARR_SID+=("$p1")
                ARR_CLIENT+=("$p2")
                ARR_HOME+=("$p3")
            else
                # Se passou apenas CLIENT:HOME, calcula o SID sequencial
                DEFAULT_SID=$(printf "%s%03d" "${DB_NAME_UPPER}" "$idx")
                ARR_SID+=("$DEFAULT_SID")
                ARR_CLIENT+=("$p1")
                ARR_HOME+=("$p2")
            fi
            ((idx++))
        done
    else
        read -p "Quantidade de instancias do RAC: " TOTAL_NODES
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
    fi

    LOCAL_HOME="${ARR_HOME[0]}"
    su - "${DB_USER}" -c "[ -d '${LOCAL_HOME}' ] && [ -x '${LOCAL_HOME}/bin/rman' ]" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "AVISO: ORACLE_HOME local '${LOCAL_HOME}' nao encontrado ou binario rman inacessivel para '${DB_USER}'."
    fi

    FIRST_SID="${ARR_SID[0]}"
    RMAN_FILE="${SCRIPT_DIR}/crosscheck_rac_${DB_NAME}.rmn"
    LOG_FILE="${SCRIPT_DIR}/crosscheck_rac_${DB_NAME}.log"

    CONNECT_CMD="CONNECT TARGET '/@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${SCAN_NAME})(PORT=${SCAN_PORT}))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=${SERVICE_NAME})(INSTANCE_NAME=${FIRST_SID}))) as sysbackup';"

    # Montagem do arquivo RMAN
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
