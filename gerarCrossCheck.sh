#!/bin/bash

###############################################################################
# Script: gerarCrossCheck.sh
# Objetivo:
#   Gerar script RMAN CrossCheck para NetBackup.
#
# Uso com Wallet:
#   gerarCrossCheck.sh oracle CLIENTE ORACLE_HOME WALLET_PATH SID1 [SID2...]
#
# Uso sem Wallet:
#   gerarCrossCheck.sh oracle CLIENTE ORACLE_HOME NONE SID1 [SID2...]
###############################################################################

if [ "$#" -lt 5 ]; then
    echo "Uso:"
    echo "$0 <USUARIO_ORACLE> <NB_ORA_CLIENT> <ORACLE_HOME> <WALLET_PATH|NONE> <SID1> [SID2 ...]"
    exit 1
fi

USUARIO_ORACLE="$1"
NB_ORA_CLIENT="$2"
ORACLE_HOME="$3"
WALLET_PATH="$4"

shift 4

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
# Processa cada SID
###############################################################################

for ORACLE_SID in "$@"
do

    RMAN_FILE="${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.rmn"
    LOG_FILE="${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.log"

    ###########################################################################
    # Wallet ou autenticação local
    ###########################################################################

    if [ "$(echo "${WALLET_PATH}" | tr '[:lower:]' '[:upper:]')" = "NONE" ]; then
        CONNECT_CMD="CONNECT TARGET '/';"
        TNS_ADMIN_EXPORT=""
    else
        CONNECT_CMD="CONNECT TARGET '/@${ORACLE_SID} AS SYSBACKUP';"
        TNS_ADMIN_EXPORT="export TNS_ADMIN=${WALLET_PATH};"
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
NB_ORA_SID=${ORACLE_SID},
NB_ORA_CLIENT=${NB_ORA_CLIENT}
)';

SEND 'NB_ORA_SERV=netbackupmasterlinux.datacenter.prodeb';

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

for ORACLE_SID in "$@"
do
    echo "  ${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.rmn"
done

echo
echo "Concluído."
