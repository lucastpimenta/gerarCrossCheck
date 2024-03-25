#!/bin/bash

# Verifica se pelo menos 4 argumentos foram fornecidos
if [ "$#" -lt 4 ]; then
  echo "Uso: $0 <USUARIO_ORACLE> <NB_ORA_CLIENT> <ORACLE_HOME> <ORACLE_SID_1> [<ORACLE_SID_2> ...]"
  exit 1
fi

USUARIO_ORACLE=$1
NB_ORA_CLIENT=$2
ORACLE_HOME=$3

# Remove os 3 primeiros argumentos da lista, deixando apenas os ORACLE_SID
shift 3

# Determina o sistema operacional e ajusta SBT_LIBRARY conforme necessário
OS_NAME=$(uname -s)
if [ "$OS_NAME" = "SunOS" ]; then
  SBT_LIBRARY="/usr/openv/netbackup/bin/libobk.so64.1"
else
  SBT_LIBRARY="/usr/openv/netbackup/bin/libobk.so64"
fi

# Cria o script crosscheck.sh
echo "#!/bin/bash" > /usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh

for ORACLE_SID in "$@"; do
    echo "su - $USUARIO_ORACLE -c \"bash -c '" >> /usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
    echo "export ORACLE_HOME=${ORACLE_HOME} && " >> /usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
    echo "export ORACLE_SID=${ORACLE_SID} && " >> /usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
    echo "export PATH=\${ORACLE_HOME}/bin:\${PATH} && " >> /usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
    echo "rman target / @~/script/crosscheck.rmn log=~/script/crosscheck_${ORACLE_SID}.log'" >> /usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
    echo "\"" >> /usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh
done

# Dá permissão de execução para o script crosscheck.sh
chmod +x /usr/openv/netbackup/ext/db_ext/oracle/crosscheck.sh

# Cria ou substitui o arquivo crosscheck.rmn
su - $USUARIO_ORACLE -c "mkdir -p ~/script && cat > ~/script/crosscheck.rmn <<EOF
allocate channel for maintenance type 'sbt_tape' parms 'SBT_LIBRARY=${SBT_LIBRARY}';
SEND 'NB_ORA_SERV=NB_PRIMARY,NB_ORA_CLIENT=${NB_ORA_CLIENT}';
CROSSCHECK BACKUP;
DELETE EXPIRED BACKUP;
EOF"
