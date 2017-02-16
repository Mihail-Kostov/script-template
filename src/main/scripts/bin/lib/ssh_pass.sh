#!/bin/bash
#set -eux
#==================================================================================================
# openSSHのSSH_ASKPASSを利用して、ssh/scpコマンドにパスワードを渡します。
#==================================================================================================
if [ -n "$PASSWORD" ]; then
  cat <<< "$PASSWORD"
  exit 0
fi
read PASSWORD
export SSH_ASKPASS=$0
export PASSWORD
export DISPLAY=dummy$$:0
exec setsid "$@"

