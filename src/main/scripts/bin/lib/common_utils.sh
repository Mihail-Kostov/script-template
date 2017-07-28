#!/bin/bash
#==================================================================================================
#
# 共通関数定義
# ※_で始まるfunctionは、パイプでの呼出しだけを想定しています。
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 実行OS判定
#--------------------------------------------------------------------------------------------------
function is_mac() {
  if [ "$(uname)" == 'Darwin' ]; then
    echo "true"
  else
    echo "false"
  fi
  return 0
}

function is_linux() {
  if [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
    echo "true"
  else
    echo "false"
  fi
  return 0
}

function is_cygwin() {
  if [ "$(expr substr $(uname -s) 1 10)" == 'MINGW32_NT' ]; then
    echo "true"
  else
    echo "false"
  fi
  return 0
}

#--------------------------------------------------------------------------------------------------
# 文字列操作
#--------------------------------------------------------------------------------------------------
function _trim() {
  cat -                                                                                            | # 標準入力から
  sed -e "s|^  *||g"                                                                               | # leftトリム
  sed -e "s|  *$||g"                                                                                 # rightトリム
  return 0
}

function _ltrim() {
  cat -                                                                                            | # 標準入力から
  sed -e "s|^  *||g"                                                                                 # leftトリム
  return 0
}

function _rtrim() {
  cat -                                                                                            | # 標準入力から
  sed -e "s|  *$||g"                                                                                 # rightトリム
  return 0
}

function _sp_multi2single() {
  cat -                                                                                            | # 標準入力から
  sed -E "s| +| |g"                                                                                  # 複数スペースを単一に置換
  return 0
}


#--------------------------------------------------------------------------------------------------
# 行操作
#--------------------------------------------------------------------------------------------------
function _except_comment_row() {
  cat -                                                                                            | # 標準入力から
  grep -v '^\s*#'                                                                                    # コメント行を除外
  return 0
}

function _except_empty_row() {
  cat -                                                                                            | # 標準入力から
  grep -v '^\s*$'                                                                                    # 空行を除外
  return 0
}


#--------------------------------------------------------------------------------------------------
# 暗号化・復号化
#--------------------------------------------------------------------------------------------------
function gen_encrypt_key() {
  # 設定チェック
  if [ "${PATH_ENCRYPT_KEY}" = "" ]; then
    echo "PATH_ENCRYPT_KEY が設定されていません。" >&2
    return 1
  fi
  if [ "${PATH_DECRYPT_KEY}" = "" ]; then
    echo "PATH_DECRYPT_KEY が設定されていません。" >&2
    return 1
  fi

  # 鍵作成
  echo "openssl req -x509 -nodes -newkey rsa:2048 -keyout \"${PATH_DECRYPT_KEY}\" -out \"${PATH_ENCRYPT_KEY}\" -subj '/'"
  openssl req -x509 -nodes -newkey rsa:2048 -keyout "${PATH_DECRYPT_KEY}" -out "${PATH_ENCRYPT_KEY}" -subj '/'
  return $?
}

function _encrypt() {
  # 設定チェック
  if [ "${PATH_ENCRYPT_KEY}" = "" ]; then
    echo "PATH_ENCRYPT_KEY が設定されていません。" >&2
    return 1
  fi

  # 暗号化
  cat -                                                                                            | # 標準入力（平文）を
  openssl smime -encrypt -aes256 -binary -outform PEM "${PATH_ENCRYPT_KEY}"                          # PATH_ENCRYPT_KEYで暗号化
  return 0
}

function _decrypt() {
  # 設定チェック
  if [ "${PATH_DECRYPT_KEY}" = "" ]; then
    echo "PATH_DECRYPT_KEY が設定されていません。" >&2
    return 1
  fi

  # 復号化
  cat -                                                                                            | # 標準入力（暗号化文字列）を
  openssl smime -decrypt -binary -inform PEM -inkey "${PATH_DECRYPT_KEY}"                            # PATH_DECRYPT_KEYで復号化
  return 0
}


#--------------------------------------------------------------------------------------------------
# SSH
#--------------------------------------------------------------------------------------------------
function gen_ssh_server_key() {
  local _USAGE="Usage: ${FUNCNAME[0]} IP"
  local _PATH_KNOWN_HOSTS=~/.ssh/known_hosts

  local _ip="$1"
  local _ret_code=0

  # 入力チェック
  if [ "${_ip}" = "" ]; then
    echo "IP が指定されていません。" >&2
    echo "${_USAGE}" >&2
    return 1
  fi

  # キーの存在チェック
  cat ${_PATH_KNOWN_HOSTS} | grep ${_ip} > /dev/null 2>&1
  _ret_code=$?
  if [ ${_ret_code} -eq 0 ]; then
    echo "${_ip} のSSHサーバキーは既に存在します。"
    return 0
  fi

  # サーバキー削除
  ssh-keygen -R ${_ip} > /dev/null 2>&1
  _ret_code=$?
  if [ ${_ret_code} -ne 0 ]; then
    echo "${_ip} のSSHサーバキー削除に失敗しました。コマンド: ssh-keygen -R ${_ip}、リターンコード: ${_ret_code}" >&2
    return 1
  fi

  # サーバキー追加
  ssh-keyscan ${_ip} >> ${_PATH_KNOWN_HOSTS} 2> /dev/null
  _ret_code=$?
  if [ ${_ret_code} -ne 0 ]; then
    echo "${_ip} のSSHサーバキー追加に失敗しました。コマンド: ssh-keyscan ${_ip} >> ${_PATH_KNOWN_HOSTS}、リターンコード: ${_ret_code}" >&2
    return 1
  fi

  echo "${_ip} のSSHサーバキーを追加しました。"
  return 0
}


#--------------------------------------------------------------------------------------------------
# USAGE
#--------------------------------------------------------------------------------------------------
function usage() {
  local _USAGE="Usage: ${FUNCNAME[0]} SCRIPTNAME"
  local _START_USAGE_PART='```usage'
  local _END_USAGE_PART='```'

  local _scriptname="$1"
  local _ret_code=0

  # 入力チェック
  if [ "${_scriptname}" = "" ]; then
    echo "スクリプト名 が指定されていません。" >&2
    echo "${_USAGE}" >&2
    return 1
  fi

  # 設定チェック
  if [ "${DIR_BIN}" = "" ]; then
    echo "DIR_BIN が設定されていません。" >&2
    return 1
  fi
  if [ "${DIR_DOCS}" = "" ]; then
    echo "DIR_DOCS が設定されていません。" >&2
    return 1
  fi

  # Markdown ファイルパス
  local _path_markdown=${DIR_DOCS}/${_scriptname}.md
  if [ ! -f ${_path_markdown} ]; then
    echo "Markdownファイル:${_path_markdown} が存在しません。" >&2
    return 1
  fi

  # Markdown ファイルから Usage を抽出し出力
  cat ${_path_markdown}                                                                            |
  sed -n -e '/'"${_START_USAGE_PART}"'/,/'"${_END_USAGE_PART}"'/p'                                 |
  sed -e '1d' -e '$d'

  return 0
}


#--------------------------------------------------------------------------------------------------
# STATUS
#--------------------------------------------------------------------------------------------------
function step_result.init() {
  local _USAGE="Usage: ${FUNCNAME[0]} PATH_STEP_RESULT STEP_LIST1 [STEP_LIST2 STEP_LIST3 ...]"

  # ステータスファイル
  local _path_step_result="$1"
  if [ ! -d $(dirname ${_path_step_result}) ]; then
    mkdir -p $(dirname ${_path_step_result})
  fi

  # 設定チェック
  if [ "${STATUS_NOT_EXECUTE}" = "" ]; then
    echo "STATUS_NOT_EXECUTE が設定されていません。" >&2
    return 1
  fi


  # 空ファイル作成
  touch ${_path_step_result}

  # ヘッダ出力
  echo "ORDER STEP_NAME STATUS"                                                                      >> ${_path_step_result}

  # ステップリストへシフト
  shift

  # ステップ分ループ
  local _step_count=1
  while [ $# -gt 0 ]; do
    # ステップ
    local _cur_step="$1"

    # 初期ステータス出力
    echo "${_step_count} ${_cur_step} ${STATUS_NOT_EXECUTE}"                                         >> ${_path_step_result}

    # ステップカウントアップ
    _step_count=$(( ${_step_count} + 1 ))

    # 次のステップへ
    shift
  done

  return 0
}


function step_result.update() {
  local _USAGE="Usage: ${FUNCNAME[0]} PATH_STEP_RESULT STEP_NAME UPDATE_STATUS"

  # ステータスファイル
  local _path_step_result="$1"
  if [ ! -f ${_path_step_result} ]; then
    echo "ステータスファイル:${_path_step_result} が存在しません。" >&2
    return 1
  fi

  # ステップ名
  local _step_name="$2"

  # 更新ステータス
  local _update_status="$3"


  # ステータスファイル退避
  mv -f ${_path_step_result} ${_path_step_result}.tmp

  # ステータス更新
  cat ${_path_step_result}.tmp                                                                     |
  sed -e "s| ${_step_name} ${STATUS_NOT_EXECUTE}| ${_step_name} ${_update_status}|g"                 > ${_path_step_result}

  # 一時ファイル削除
  rm -f ${_path_step_result}.tmp


  return 0
}


function step_result.show() {
  local _USAGE="Usage: ${FUNCNAME[0]} PATH_STEP_RESULT"

  # ステータスファイル
  local _path_step_result="$1"
  if [ ! -f ${_path_step_result} ]; then
    echo "ステータスファイル:${_path_step_result} が存在しません。" >&2
    return 1
  fi


  #------------------------------------------------------------------------------------------------
  # 本処理
  #------------------------------------------------------------------------------------------------
  # ステータス出力
  cat ${_path_step_result}                                                                         |
  ${DIR_BIN_LIB}/Tukubai/keta --                                                                     # 左寄せで桁揃え

  # ステータスファイル削除
  rm -f ${_path_step_result}


  return 0
}


#--------------------------------------------------------------------------------------------------
# 自ホストIPアドレス取得
#--------------------------------------------------------------------------------------------------
function get_ip() {
  # 自IPを標準出力
  echo $(                                                                                            \
    LANG=C /sbin/ifconfig                                                                          | \
    grep "inet addr"                                                                               | \
    grep -v 127.0.0.1                                                                              | \
    head -n 1                                                                                      | \
    awk '{print $2}'                                                                               | \
    cut -d ":" -f 2                                                                                  \
  )
  return 0
}


#--------------------------------------------------------------------------------------------------
# URLエンコード・デコード
#--------------------------------------------------------------------------------------------------
function _urlencode() {
  local _lf='\%0A'

  cat -                                                                                            | # 標準出力から
  python -c 'import sys, urllib ; print urllib.quote(sys.stdin.read());'                           | # URLエンコード
  sed "s|${_lf}$||g"                                                                                 # 末尾に改行コードが付与されるので除外

  return 0
}


function _urldecode() {
  cat -                                                                                            | # 標準出力から
  python -c 'import sys, urllib ; print urllib.unquote(sys.stdin.read());'

  return 0
}
