#!/bin/bash
#==================================================================================================
# システム設定
#
# 前提
#   ・${DIR_BASE} が事前に設定されていること
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 定数
#--------------------------------------------------------------------------------------------------
# 終了コード
readonly EXITCODE_SUCCESS=0
readonly EXITCODE_WARN=3
readonly EXITCODE_ERROR=6

# 終了メッセージ
readonly EXITMSG_SUCCESS="NORMAL END."
readonly EXITMSG_WARN="PROCESS END with WARNNING."
readonly EXITMSG_ERROR="ABNORMAL END."

# ログレベル
readonly LOGLEVEL_TRACE="TRACE"
readonly LOGLEVEL_DEBUG="DEBUG"
readonly LOGLEVEL_INFO="INFO "
readonly LOGLEVEL_WARN="WARN "
readonly LOGLEVEL_ERROR="ERROR"

# ステータス文言
readonly STATUS_SUCCESS="SUCCESS"
readonly STATUS_WARN="WARN   "
readonly STATUS_ERROR="ERROR  "
readonly STATUS_SKIP="SKIP   "

# プレースホルダ括り文字
readonly PLACEHOLDER_ENCLOSE="@"

# ディレクトリ
readonly DIR_BIN=${DIR_BASE}/bin
readonly DIR_BIN_LIB=${DIR_BIN}/lib
readonly DIR_LOG=${DIR_BASE}/log

readonly DIR_CONFIG=${DIR_BASE}/config
readonly DIR_DATA=${DIR_BASE}/data

# バージョンファイル
readonly PATH_VERSION=${DIR_BASE}/version.txt

# プロセスファイル
readonly PATH_PID=${DIR_DATA}/pid

# 暗号化キーファイル
readonly PATH_ENCRYPT_KEY="${DIR_BIN_LIB}/encrypt/id_rsa.pub"
# 複合化キーファイル
readonly PATH_DECRYPT_KEY="${DIR_BIN_LIB}/encrypt/id_rsa"
# 接続情報 暗号化前ファイル
readonly PATH_ACCESS_INFO_RAW="${DIR_CONFIG}/access_info"
# 接続情報 暗号化後ファイル
readonly PATH_ACCESS_INFO="${DIR_CONFIG}/access_info.enc"
# プロジェクト毎の上書き設定ファイル
readonly PATH_PROJECT_ENV="${DIR_CONFIG}/project.properties"


#--------------------------------------------------------------------------------------------------
# 共通関数読込み
#--------------------------------------------------------------------------------------------------
. ${DIR_BIN_LIB}/common_utils.sh


#--------------------------------------------------------------------------------------------------
# 変数
#
# ここでの変数定義はデフォルト値です。
# PATH_PROJECT_ENV、PATH_ACCESS_INFO で自プロジェクト向けの設定に上書きして下さい。
#
#--------------------------------------------------------------------------------------------------
# ログレベル
LOGLEVEL=${LOGLEVEL_TRACE}

# プロセス並走数の上限
MAX_PROCESS_COMMON=4

# Redmine情報
REDMINE_URL="http://127.0.0.1/redmine"
DIR_REDMINE_RETRY="${DIR_DATA}/redmine.add_ticket.retry"
REDMINE_APIKEY="dummy"

# GitLab情報
GITLAB_URL="http://127.0.0.1/gitlab"
GITLAB_APIKEY="dummy"

# Jenkind情報
JENKINS_URL="http://127.0.0.1/jenkins"
JENKINS_APIKEY="dummy"


#--------------------------------------------------------------------------------------------------
# 接続情報の上書き設定読込み
#--------------------------------------------------------------------------------------------------
if [ -f ${PATH_ACCESS_INFO} ]; then
    while read line; do
# debug用
#      echo "READ ${line}"
      eval "${line}"
    done <<__END__
`openssl smime -decrypt -in ${PATH_ACCESS_INFO} -binary -inform PEM -inkey ${PATH_DECRYPT_KEY}`
__END__

else
  echo "WARN  ${PATH_ACCESS_INFO} が存在しないため、読込みをスキップしました。"
fi


#--------------------------------------------------------------------------------------------------
# プロジェクト毎の上書き設定読込み
#--------------------------------------------------------------------------------------------------
if [ -f ${PATH_PROJECT_ENV} ]; then
  . ${PATH_PROJECT_ENV}
else
  echo "ERROR ${PATH_PROJECT_ENV} が存在しません。デプロイ結果が正しいか確認して下さい。" >&2
  exit 1
fi
