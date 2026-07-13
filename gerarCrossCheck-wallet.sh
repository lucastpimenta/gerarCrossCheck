#!/bin/bash

###############################################################################
# Script: gerarCrossCheck-wallet.sh
# Objetivo:
#   Gerar script de CrossCheck Oracle RMAN utilizando Oracle Wallet
#   compatível com Linux, Solaris e AIX.
###############################################################################

if [ "$#" -lt 5 ]; then
    echo "Uso:"
    echo "$0 <USUARIO_ORACLE> <NB_ORA_CLIENT> <ORACLE_HOME> <WALLET_PATH> <ORACLE_SID_1> [SID2 ...]"
    exit 1
fi

USUARIO_ORACLE="$1"
NB_ORA_CLIENT="$2"
ORACLE_HOME="$3"
WALLET_PATH="$4"

shift 4

###############################################################################
# Detecta Sistema Operacional
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
# Gera launcher por SID
###############################################################################

for ORACLE_SID in "$@"
do

cat >> "${LAUNCHER}" <<EOF

echo
echo "===================================================="
echo "CrossCheck Oracle SID : ${ORACLE_SID}"
echo "===================================================="

su - ${USUARIO_ORACLE} -c "${BASH_BIN} -c 'export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${ORACLE_SID}; export TNS_ADMIN=${WALLET_PATH}; export PATH=\\\$ORACLE_HOME/bin:\\\$PATH; rman cmdfile=${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.rmn log=${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.log'"

EOF

done

chmod 755 "${LAUNCHER}"

###############################################################################
# Gera RMAN por SID
###############################################################################

for ORACLE_SID in "$@"
do

cat > "${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.rmn" <<EOF
CONNECT TARGET '/@${ORACLE_SID} AS SYSBACKUP';

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

# CROSSCHECK ARCHIVELOG ALL;

# DELETE EXPIRED BACKUP;
# DELETE EXPIRED ARCHIVELOG ALL;

RELEASE CHANNEL ch1;

}

EXIT;
EOF

chown "${USUARIO_ORACLE}" "${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.rmn"

done

###############################################################################
# Resumo
###############################################################################

echo
echo "Arquivos criados:"
echo
echo "Launcher:"
echo "  ${LAUNCHER}"
echo
echo "Scripts RMAN:"

for ORACLE_SID in "$@"
do
    echo "  ${SCRIPT_DIR}/crosscheck_${ORACLE_SID}.rmn"
done

echo
echo "Concluído."
