#set -eux
#==================================================================================================
#
# 接続情報暗号化
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 環境設定
#--------------------------------------------------------------------------------------------------
# カレントディレクトリの移動
cd $(cd $(dirname $0); pwd)

# 共通設定
readonly DIR_BASE=$(cd ..; pwd)
. ./setenv.sh

# スクリプト名
readonly SCRIPTNAME=`basename $0 .sh`
# ログファイルパス
PATH_LOG=${DIR_LOG}/${SCRIPTNAME}.log


# ログ出力ユーティリティ
. ${DIR_BIN_LIB}/logging_utils.sh
# セマフォユーティリティ
. ${DIR_BIN_LIB}/semaphore_utils.sh
# バックグラウンドプロセス管理
. ${DIR_BIN_LIB}/bg_proc_control.sh


#--------------------------------------------------------------------------------------------------
# 関数定義
#--------------------------------------------------------------------------------------------------
#--------------------------------------------------------------------------------
# usage
#--------------------------------------------------------------------------------
function usage() {
  cat <<_EOT_
    Usage:
      `basename $0`

    Description:
      ${PATH_ACCESS_INFO_RAW}に記載された接続情報を暗号化します。

    OPTIONS:
      なし

    Args:
      なし

    Sample:
      `basename $0`

    Output:
      ${PATH_ACCESS_INFO}

    ReturnCode:
      ${EXITCODE_SUCCESS}: 正常終了
      ${EXITCODE_ERROR}: エラー発生時

_EOT_
  exit ${EXITCODE_ERROR}
}

#--------------------------------------------------------------------------------
# exit
#--------------------------------------------------------------------------------
function exit_script() {
  log.restore_indent
  log.add_indent

  #------------------------------------------------------------------------------
  # スクリプト個別処理
  #------------------------------------------------------------------------------
  # なし

  #------------------------------------------------------------------------------
  # 共通処理
  #------------------------------------------------------------------------------
  # エラーの場合、子プロセス群をkill
  if [ ${proc_exit_code} -eq ${EXITCODE_ERROR} ]; then
    . ${DIR_BIN_LIB}/bg_proc_control.sh
    bg_proc_control.kill_children
  fi

  # 排他ロック解除
  semaphore.unlock
  log.remove_indent

  # 終了ログ
  if [ ${proc_exit_code} -eq ${EXITCODE_SUCCESS} ]; then
    log.info_teelog "${proc_exit_msg}"
    log.info_teelog "ExitCode:${proc_exit_code}"
    log.info_teelog "END   `basename $0` $*"
  elif [ ${proc_exit_code} -eq ${EXITCODE_WARN} ]; then
    log.warn_teelog "${proc_exit_msg}"
    log.warn_teelog "ExitCode:${proc_exit_code}"
    log.warn_teelog "END   `basename $0` $*"
  else
    log.error_teelog "${proc_exit_msg}"
    log.error_teelog "ExitCode:${proc_exit_code}"
    log.error_teelog "END   `basename $0` $*"
  fi

  # ログローテーション（日次） ※先頭行判断
  log.rotatelog_by_day_first

  # 終了
  exit ${proc_exit_code}
}


#--------------------------------------------------------------------------------------------------
# 事前処理
#--------------------------------------------------------------------------------------------------
log.info_teelog "START `basename $0` $*"

proc_exit_msg=${EXITMSG_SUCCESS}
proc_exit_code=${EXITCODE_SUCCESS}

#--------------------------------------------------------------------------------
# オプション解析
#--------------------------------------------------------------------------------
while :; do
  case $1 in
    --)
      shift
      break
      ;;
    -*)
      usage
      ;;
    *)
      break
      ;;
  esac
done

#--------------------------------------------------------------------------------
# 引数取得
#--------------------------------------------------------------------------------
# 引数チェック
if [ $# -ne 0 ]; then
  usage
fi

#--------------------------------------------------------------------------------
# ロック開始
#--------------------------------------------------------------------------------
log.save_indent
log.add_indent

# 排他ロック
semaphore.lock `basename $0`

# 強制終了トラップ
trap "                                                                                             \
proc_exit_msg='強制終了を検知したため処理を終了します。';                                          \
proc_exit_code=${EXITCODE_ERROR};                                                                  \
exit_script" SIGHUP SIGINT SIGQUIT SIGTERM

# 接続情報暗号化前ファイルの存在チェック
if [ ! -f ${PATH_ACCESS_INFO_RAW} ]; then
  log.error_teelog "${PATH_ACCESS_INFO_RAW} が存在しません。"
  proc_exit_msg=${EXITMSG_ERROR}
  proc_exit_code=${EXITCODE_ERROR}
  exit_script
fi


#--------------------------------------------------------------------------------------------------
# 本処理
#--------------------------------------------------------------------------------------------------
#------------------------------------------------------------------------------
# 暗号化
#------------------------------------------------------------------------------
log.info_teelog "暗号化"
log.add_indent

# 接続情報
log.debug_teelog "openssl smime -encrypt -aes256 -in \"${PATH_ACCESS_INFO_RAW}\" -binary -outform PEM -out \"${PATH_ACCESS_INFO}\" \"${PATH_ENCRYPT_KEY}\""
openssl smime -encrypt -aes256 -in "${PATH_ACCESS_INFO_RAW}" -binary -outform PEM -out "${PATH_ACCESS_INFO}" "${PATH_ENCRYPT_KEY}"
ret_code=$?
if [ ${ret_code} -ne ${EXITCODE_SUCCESS} ]; then
  log.error_teelog "暗号化に失敗しました。対象ファイル: ${PATH_ACCESS_INFO_RAW}、リターンコード：${ret_code}"
  proc_exit_msg=${EXITMSG_ERROR}
  proc_exit_code=${EXITCODE_ERROR}
  exit_script
fi

log.remove_indent


#------------------------------------------------------------------------------
# 暗号化前ファイルの削除
#------------------------------------------------------------------------------
log.info_teelog "暗号化前ファイルの削除"
log.add_indent

# 接続情報
log.debug_teelog "rm -f \"${PATH_ACCESS_INFO_RAW}\""
rm -f "${PATH_ACCESS_INFO_RAW}"
ret_code=$?
if [ ${ret_code} -ne ${EXITCODE_SUCCESS} ]; then
  log.error_teelog "暗号化前ファイルの削除に失敗しました。対象ファイル: ${PATH_ACCESS_INFO_RAW}"
  proc_exit_msg=${EXITMSG_ERROR}
  proc_exit_code=${EXITCODE_ERROR}
fi

log.remove_indent


#--------------------------------------------------------------------------------------------------
# 事後処理
#--------------------------------------------------------------------------------------------------
exit_script
