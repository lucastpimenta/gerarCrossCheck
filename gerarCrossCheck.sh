#!/bin/bash

###############################################################################
# Script: gerarCrossCheck.sh
#
# Objetivo:
#   Gerar scripts RMAN de CrossCheck para NetBackup.
#
# Formatos aceitos:
#
#   SID
#   SID:WALLET
#   SID:TNS_ALIAS:WALLET
#
# Exemplos:
#
#   BWP001
#   BWP001:/oracle/BWP/wallet
#   sesabdb1:sesabdbg:/oracle/wallet
#
###############################################################################

if [ "$#" -lt 4 ]; then
    echo "Uso:"
    echo "$0 <NB_PRIMARY> <USUARIO_ORACLE> <ORACLE_HOME> <SID|SID:WALLET|SID:TNS_ALIAS:WALLET> [...]"
    exit 1
fi

NB_PRIMARY="$1"
USUARIO_ORACLE="$2"
ORACLE_HOME="$3"

shift 3

###############################################################################
# Sistema Operacional
###############################################################################

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
        echo "Sistema Operacional não suportado."
        exit 1
        ;;
esac

###############################################################################
# Diretórios
###############################################################################

ORACLE_USER_HOME=$(su - "${USUARIO_ORACLE}" -c 'pwd')

SCRIPT_DIR="${ORACLE_USER_HOME}/script"
LAUNCHER="/usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh"

mkdir -p "${SCRIPT_DIR}"
chown "${USUARIO_ORACLE}" "${SCRIPT_DIR}"

###############################################################################
# Cria launcher
###############################################################################

cat > "${LAUNCHER}" <<EOF
#!${BASH_BIN}

EOF

###############################################################################
# Processa cada banco
###############################################################################

for ITEM in "$@"
do

    OLDIFS="$IFS"
    IFS=':'
    set -- $ITEM
    IFS="$OLDIFS"

    ORACLE_SID="$1"
    PARAM2="$2"
    PARAM3="$3"

    if [ -z "${ORACLE_SID}" ]; then
        echo "Entrada inválida: ${ITEM}"
        continue
    fi

    ###########################################################################
    # Interpretação dos parâmetros
    ###########################################################################

    if [ -z "${PARAM2}" ]; then

        # SID
        TNS_ALIAS=""
        WALLET_PATH=""

    elif [ -z "${PARAM3}" ]; then

        # SID:WALLET
        TNS_ALIAS="${ORACLE_SID}"
        WALLET_PATH="${PARAM2}"

    else

        # SID:TNS_ALIAS:WALLET
        TNS_ALIAS="${PARAM2}"
        WALLET_PATH="${PARAM3}"

    fi

    RMAN_FILE="${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.rmn"
    LOG_FILE="${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.log"

    ###########################################################################
    # Conexão Oracle
    ###########################################################################

    if [ -z "${TNS_ALIAS}" ]; then

        CONNECT_CMD="CONNECT TARGET '/';"
        TNS_ADMIN_EXPORT=""

    else

        CONNECT_CMD="CONNECT TARGET '/@${TNS_ALIAS} AS SYSBACKUP';"

        if [ -n "${WALLET_PATH}" ]; then
            TNS_ADMIN_EXPORT="export TNS_ADMIN=${WALLET_PATH};"
        else
            TNS_ADMIN_EXPORT=""
        fi

    fi

    ###########################################################################
    # Launcher
    ###########################################################################

    cat >> "${LAUNCHER}" <<EOF

echo
echo "===================================================="
echo "CrossCheck Oracle SID : ${ORACLE_SID}"
echo "===================================================="

su - ${USUARIO_ORACLE} -c "${BASH_BIN} -c 'export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${ORACLE_SID}; ${TNS_ADMIN_EXPORT} export PATH=\\\$ORACLE_HOME/bin:\\\$PATH; rman cmdfile=${RMAN_FILE} log=${LOG_FILE}'"

echo
echo "Log gerado em:"
echo "${LOG_FILE}"

EOF

    ###########################################################################
    # RMAN
    ###########################################################################

    cat > "${RMAN_FILE}" <<EOF
${CONNECT_CMD}

RUN {

ALLOCATE CHANNEL ch1 DEVICE TYPE SBT_TAPE
PARMS 'SBT_LIBRARY=${SBT_LIBRARY},
ENV=(
NB_ORA_HOME=${ORACLE_HOME},
NB_ORA_SID=${ORACLE_SID}
)';

SEND 'NB_ORA_SERV=${NB_PRIMARY}';

CROSSCHECK BACKUP;

DELETE EXPIRED BACKUP;

RELEASE CHANNEL ch1;

}

EXIT;
EOF

    chown "${USUARIO_ORACLE}" "${RMAN_FILE}"

done

chmod 755 "${LAUNCHER}"

###############################################################################
# Resumo
###############################################################################

echo
echo "===================================================="
echo "Arquivos criados"
echo "===================================================="
echo

echo "Launcher:"
echo "  ${LAUNCHER}"

echo
echo "Arquivos RMAN:"

for ITEM in "$@"
do
    ORACLE_SID=$(echo "$ITEM" | cut -d: -f1)
    echo "  ${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.rmn"
done

echo
echo "Concluído."
