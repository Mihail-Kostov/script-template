#!/bin/bash
#set -eux
if [ "$(whoami)" = "root" ]; then
  echo "rootユーザでは実行できません。" >&2
  exit 1
fi

#==================================================================================================
# Macの場合、デフォルトでインストールさている様子なので、expectで対応しています。
#==================================================================================================
if [ "$(uname)" == 'Darwin' ]; then
  read PASSWORD
  if [ "$1" = "ssh" ]; then
    # 想定する呼出し
    #   echo PASSWORD | ssh_pass.sh ssh -l USER IP "COMMANDs"
    #   echo PASSWORD | ssh_pass.sh ssh USER@IP "COMMANDs"
    expect -c "
      set timeout -1
      # sshコマンドの最後の引数に「リモートで実行するコマンド」が、1つの引数として渡される
      spawn ${@:1:($#-1)} \"${@:($#):($#)}\"
      expect :
      send \"$PASSWORD\n\"
      expect {
        Password: {
          # パスワード入力プロンプトが再出力された場合、エラー
          send_user \"\nERROR Invalid access-info.\n\"
          exit 1
        }
        eof {
          # EOFが出力された場合、最後のコマンドのリターンコードで終了
          catch wait result
          exit [lindex \$result 3]
        }
      }
    "

  elif [ "$1" = "scp" ]; then
    # 想定する呼出し
    #   echo PASSWORD | ssh_pass.sh scp FROM_PATH USER@IP:TO_PATH
    #   echo PASSWORD | ssh_pass.sh scp -r USER@IP:FROM_PATH TO_PATH
    expect -c "
      set timeout -1
      spawn $@
      expect :
      send \"$PASSWORD\n\"
      expect {
        Password: {
          # パスワード入力プロンプトが再出力された場合、エラー
          send_user \"\nERROR Invalid access-info.\n\"
          exit 1
        }
        eof {
          # EOFが出力された場合、最後のコマンドのリターンコードで終了
          catch wait result
          exit [lindex \$result 3]
        }
      }
    "

  else
    echo "$1 コマンドの呼出しには対応していません。引数：$@" >&2
    exit 1
  fi

  exit $?
fi

#==================================================================================================
# その他の場合、openSSHのSSH_ASKPASSを利用して、ssh/scpコマンドにパスワードを渡します。
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
