#!/bin/bash
#set -eux
#==================================================================================================
# Jenkinsユーティリティ
#
# 前提
#   ・setenv.sh を事前に読み込んでいること
#       ・${GITLAB_URL}が事前に設定されていること
#       ・${JENKINS_USER}が事前に設定されていること
#       ・${JENKINS_PASS}が事前に設定されていること
#
# 定義リスト
#   ・jenkins.copy_job
#   ・jenkins.get_job_config
#   ・jenkins.update_job_config
#   ・jenkins.get_view_job_list
#   ・jenkins.get_latest_build_id
#   ・jenkins.get_latest_build_result
#   ・jenkins.sync_build
#   ・jenkins.async_build
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 依存スクリプト読込み
#--------------------------------------------------------------------------------------------------
# ログ出力ユーティリティ
. ${DIR_BIN_LIB}/logging_utils.sh


#--------------------------------------------------------------------------------------------------
# 概要
#   ジョブをコピーします。
#
# 引数
#   ・1 : コピー元ジョブ
#   ・2 : コピー先ジョブ
#
# 標準出力
#   なし
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function jenkins.copy_job() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: jenkins.copy_job FROM_JOB TO_JOB"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # コピー元ジョブ
  local _from_job="$1"

  # コピー先ジョブ
  local _to_job="$2"


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # ジョブコピー実行URL
  local readonly _url="${JENKINS_URL}/createItem?name=${_to_job}&mode=copy&from=${_from_job}"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_console "curl -s -X POST --user \"${JENKINS_USER}:${JENKINS_PASS}\" -H 'Content-type: application/xml' \"${_url}\" -o \"${_path_response}\" -w '%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X POST --user "${JENKINS_USER}:${JENKINS_PASS}" "${_url}" -H 'Content-type: application/xml' -o "${_path_response}" -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "3" ]; then
    # 300系以外の場合、エラー終了 ※ コピー成功時は、コピー先ジョブへの転送処理が発生するため302で返される
    log.error_console "ジョブのコピーでエラーが発生しました。コピー元ジョブ：${_from_job}、コピー先ジョブ：${_to_job}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response}                                                                          > /dev/null 2>&1

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   ジョブの詳細設定をファイル出力します。
#
# 引数
#   ・1 : ジョブ
#   ・2 : 詳細設定出力パス
#
# 標準出力
#   apiの標準出力
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function jenkins.get_job_config() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: jenkins.get_job_config JOB PATH_OUTPUT_SETTING"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # ジョブ
  local _job="$1"

  # 詳細設定出力パス
  local _path_output_config="$2"
  if [ ! -d `dirname ${_path_output_config}` ]; then
    mkdir -p `dirname ${_path_output_config}`
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # ジョブ詳細設定取得URL
  local readonly _url="${JENKINS_URL}/job/${_job}/config.xml"

  # リクエスト実行
  log.debug_console "curl -s -X GET --user \"${JENKINS_USER}:${JENKINS_PASS}\" \"${_url}\" -o \"${_path_output_config}\" -w '%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X GET --user "${JENKINS_USER}:${JENKINS_PASS}" "${_url}" -o "${_path_output_config}" -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

  # 取得結果出力
  log.trace_console "${_path_output_config}:"
  log.add_indent
  cat ${_path_output_config}                                                                      |
  log.trace_console
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
    log.error_console "ジョブの詳細設定取得でエラーが発生しました。ジョブ：${_job}、レスポンスファイル：${_path_output_config}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   ジョブの詳細設定を更新します。
#
# 引数
#   ・1 : ジョブ
#   ・2 : 詳細設定ファイルパス
#
# 標準出力
#   なし
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function jenkins.update_job_config() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: jenkins.update_job_config JOB PATH_SETTING_FILE"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # ジョブ
  local _job="$1"

  # 詳細設定ファイルパス
  local _path_config_file="$2"
  if [ ! -f ${_path_config_file} ]; then
    log.error_console "詳細設定ファイルが存在しません。詳細設定ファイルパス：${_path_config_file}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # ジョブ詳細設定更新URL
  local readonly _url="${JENKINS_URL}/job/${_job}/config.xml"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_console "curl -s -X POST --data-binary @${_path_config_file} --user \"${JENKINS_USER}:${JENKINS_PASS}\" \"${_url}\" -o \"${_path_output_config}\" -w '%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X POST --data-binary @${_path_config_file} --user "${JENKINS_USER}:${JENKINS_PASS}" "${_url}" -o "${_path_output_config}" -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
    log.error_console "ジョブの詳細設定更新でエラーが発生しました。ジョブ：${_job}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response}                                                                          > /dev/null 2>&1

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   ビューに含まれているジョブのリストを出力します。
#
# 引数
#   ・1 : ビュー
#   ・2 : 出力ファイルパス
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function jenkins.get_view_job_list() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: jenkins.get_view_job_list VIEW PATH_OUTPUT"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # ビュー
  local _view="$1"

  # 結果出力パス
  local _path_output="$2"
  if [ ! -d `dirname ${_path_output}` ]; then
    mkdir -p `dirname ${_path_output}`
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # ジョブリスト設定取得URL
  local readonly _url="${JENKINS_URL}/view/${_view}/api/json?tree=jobs\[name\]"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_console "curl -s -X GET --user \"${JENKINS_USER}:${JENKINS_PASS}\" \"${_url}\" -o \"${_path_response}\" -w '%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X GET --user "${JENKINS_USER}:${JENKINS_PASS}" "${_url}" -o "${_path_response}" -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

  # 取得結果出力
  log.trace_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                              |
  log.trace_console
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
    log.error_console "ジョブ一覧取得でエラーが発生しました。ビュー：${_view}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 一覧に変換
  log.debug_console "cat ${_path_response} | ${DIR_BIN_LIB}/jq . | ${DIR_BIN_LIB}/parsrj.sh | ${DIR_BIN_LIB}/Tukubai/self 2"
  cat ${_path_response} | ${DIR_BIN_LIB}/jq . | ${DIR_BIN_LIB}/Parsrs/parsrj.sh | ${DIR_BIN_LIB}/Tukubai/self 2        > ${_path_output}
  log.add_indent
  log.trace_console "${_path_output}: "
  cat ${_path_output}                                                                              |
  log.trace_console
  log.remove_indent


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response}                                                                          > /dev/null 2>&1

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   ジョブの最新ビルドIDを取得します。
#
# 引数
#   ・1 : ジョブ
#
# 標準出力
#   ビルドID
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function jenkins.get_latest_build_id() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_log "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 1 ]; then
    log.error_log "Usage: jenkins.get_latest_build_id JOB"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # ジョブ
  local _job="$1"


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # ジョブリスト設定取得URL
  local readonly _url="${JENKINS_URL}/job/${_job}/lastBuild/api/json"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_log "curl -s -X GET --user \"${JENKINS_USER}:${JENKINS_PASS}\" \"${_url}\" -o \"${_path_response}\" -w '%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X GET --user "${JENKINS_USER}:${JENKINS_PASS}" "${_url}" -o "${_path_response}" -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_log "response code: ${_response_code}"
  log.debug_log "return code  : ${_cur_return_code}"
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -eq ${EXITCODE_SUCCESS} -a `echo ${_response_code} | cut -c 1`"" = "2" ]; then
    # 200系の場合、正常終了
    cat ${_path_response} | ${DIR_BIN_LIB}/jq .id | sed -e 's|"||g'
  else
    # 200系以外の場合、エラー終了
    echo "NOT-EXIST"
    log.error_log "最新ビルドIDの取得でエラーが発生しました。ジョブ：${_job}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response}                                                                          > /dev/null 2>&1

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   ジョブの最新ビルド結果を取得します。
#
# 引数
#   ・1 : ジョブ
#
# 標準出力
#   ビルド結果
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function jenkins.get_latest_build_result() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_log "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 1 ]; then
    log.error_log "Usage: jenkins.get_latest_build_result JOB"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # ジョブ
  local _job="$1"


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # ジョブリスト設定取得URL
  local readonly _url="${JENKINS_URL}/job/${_job}/lastBuild/api/json"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_log "curl -s -X GET --user \"${JENKINS_USER}:${JENKINS_PASS}\" \"${_url}\" -o \"${_path_response}\" -w '%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X GET --user "${JENKINS_USER}:${JENKINS_PASS}" "${_url}" -o "${_path_response}" -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_log "response code: ${_response_code}"
  log.debug_log "return code  : ${_cur_return_code}"
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -eq ${EXITCODE_SUCCESS} -a `echo ${_response_code} | cut -c 1`"" = "2" ]; then
    # 200系の場合、正常終了
    cat ${_path_response} | ${DIR_BIN_LIB}/jq .result | sed 's|"||g'
  else
    # 200系以外の場合、エラー終了
    echo "NOT-EXIST"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response}                                                                          > /dev/null 2>&1

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   ジョブを実行します。
#
# 引数
#   ・1 : ジョブ
#   ・2 : ビルドパラメータ ※ 任意 クエリストリング形式(パラメータ1=値1&パラメータ2=値2 ...)
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function jenkins.local.execute_build() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -lt 1 ]; then
    log.error_console "Usage: jenkins.execute_async_build JOB [BUILD_PARAMETERS]"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # ジョブ
  local _job="$1"

  # パラメータ
  local _build_param=""
  if [ $# -eq 2 ]; then
    _build_param="$2"
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # ビルド実行URL
  if [ -n "${_build_param}" ]; then
    # ビルドパラメータの指定がある場合
    local readonly _url="${JENKINS_URL}/job/${_job}/buildWithParameters?${_build_param}"
  else
    # ビルドパラメータの指定がない場合
    local readonly _url="${JENKINS_URL}/job/${_job}/build"
  fi

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_console "curl -s -X POST --user \"${JENKINS_USER}:${JENKINS_PASS}\" \"${_url}\" -o \"${_path_response}\" -w '%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X POST --user "${JENKINS_USER}:${JENKINS_PASS}" "${_url}" -o "${_path_response}" -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -eq ${EXITCODE_SUCCESS} -a `echo ${_response_code} | cut -c 1`"" = "2" ]; then
    # 200系の場合、正常終了
    local _ret_code=${EXITCODE_SUCCESS}
  elif [ ${_cur_return_code} -eq ${EXITCODE_SUCCESS} -a `echo ${_response_code} | cut -c 1`"" = "4" ]; then
    # 400系の場合、パラメータジョブの場合パラメータで実行すると 400 で返される
    log.error_console "${_job} にはパラメータが必要です。"
    local _ret_code=${EXITCODE_ERROR}
  elif [ ${_cur_return_code} -eq ${EXITCODE_SUCCESS} -a `echo ${_response_code} | cut -c 1`"" = "5" ]; then
    # 500系の場合、パラメータジョブではない場合パラメータ指定で実行すると 500 で返される
    log.error_console "${_job} にはパラメータを指定できません。"
    local _ret_code=${EXITCODE_ERROR}
  else
    # エラー終了
    log.error_console "${_job} は存在しません。"
    local _ret_code=${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response}                                                                          > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   ジョブを同期実行します。
#
# 引数
#   ・1 : ジョブ
#   ・2 : ビルドパラメータ      ※ 任意 クエリストリング形式(パラメータ1=値1&パラメータ2=値2 ...)
#   ・3 : 監視インターバル      ※ 秒単位
#   ・4 : 起動待ちタイムアウト  ※ 秒単位
#   ・5 : 終了待ちタイムアウト  ※ 秒単位
#
# 戻り値
#   0: 正常終了の場合
#   3: 不安定で終了した場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function jenkins.sync_build() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -lt 4 ]; then
    log.error_console "Usage: jenkins.sync_build JOB [BUILD_PARAMETERS] INTERVAL TIMEOUT_START TIMEOUT_END"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # ジョブ
  local _job="$1"

  # ビルドパラメータ
  local _build_param=""
  if [ $# -eq 5 ]; then
    _build_param="$2"
    shift
  fi

  # インターバル
  local _interval="$2"

  # 起動待ちタイムアウト
  local _timeout_start="$3"

  # 終了待ちタイムアウト
  local _timeout_end="$4"


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 最新のビルド結果から前回ビルドID取得
  local _before_build_id=`jenkins.get_latest_build_id ${_job}`

  #------------------------------------
  # ジョブ実行
  #------------------------------------
  log.debug_console "ジョブ実行"
  log.add_indent

  jenkins.local.execute_build "${_job}" "${_build_param}"
  local _cur_ret_code=$?
  if [ ${_cur_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  log.remove_indent

  #------------------------------------
  # 起動待機
  #------------------------------------
  log.debug_console "起動待機"
  log.add_indent

  # タイムアウト時刻(秒形式)を算出 ※ OSを考慮し date ではなく expr で加算
  local _sec_timeout_start=$(expr `date '+%s'` + ${_timeout_start})

  while :; do
    # 最新のビルドID取得
    local _cur_latest_build_id=`jenkins.get_latest_build_id ${_job}`

    # ビルドIDチェック
    if [ "${_cur_latest_build_id}" != "${_before_build_id}" ]; then
      # 前回ビルドIDと異なる場合 ※ ジョブ実行待機 → ジョブ実行中 に変わった場合
      log.debug_console "ジョブが起動されました。"
      break
    else
      # 前回ビルドIDと同じ場合 ※ ジョブ実行待機中
      log.debug_console "待機中..."
    fi

    # タイムアウトチェック
    if [ `date '+%s'` -ge ${_sec_timeout_start} ]; then
      log.error_console "ジョブ起動待機中にタイムアウトしました。"
      log.remove_indent 2
      return ${EXITCODE_ERROR}
    fi

    sleep ${_interval}
  done

  log.remove_indent

  #------------------------------------
  # 終了待機
  #------------------------------------
  log.debug_console "終了待機"
  log.add_indent

  # タイムアウト時刻(秒形式)を算出 ※ OSを考慮し date ではなく expr で加算
  local _sec_timeout_end=$(expr `date '+%s'` + ${_timeout_end})

  local _ret_code=${EXITCODE_SUCCESS}
  while :; do
    # 最新のビルド結果取得
    local _cur_latest_build_result=`jenkins.get_latest_build_result ${_job}`

    # 結果チェック
    if [ "${_cur_latest_build_result}" = "null" ]; then
      # nullの場合 ※実行中
      log.debug_console "実行中..."
    elif [ "${_cur_latest_build_result}" = "SUCCESS" ]; then
      # SUCCESSの場合
      log.debug_console "実行結果：成功(${_cur_latest_build_result})"
      _ret_code=${EXITCODE_SUCCESS}
      break
    elif [ "${_cur_latest_build_result}" = "UNSTABLE" ]; then
      # UNSTABLEの場合
      log.debug_console "実行結果：不安定(${_cur_latest_build_result})"
      _ret_code=${EXITCODE_WARN}
      break
    else
      # FAILUREの場合
      log.debug_console "実行結果：失敗(${_cur_latest_build_result})"
      _ret_code=${EXITCODE_ERROR}
      break
    fi

    # タイムアウトチェック
    if [ `date '+%s'` -ge ${_sec_timeout_end} ]; then
      log.error_console "ジョブ終了待機中にタイムアウトしました。"
      log.remove_indent 2
      return ${EXITCODE_ERROR}
    fi

    sleep ${_interval}
  done

  log.remove_indent


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  log.remove_indent
  return ${_ret_code}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   ジョブを非同期実行します。
#   ※ ジョブがキューに溜まっている状態から起動されるまでは待機します。
#
# 引数
#   ・1 : ジョブ
#   ・2 : ビルドパラメータ      ※ 任意 クエリストリング形式(パラメータ1=値1&パラメータ2=値2 ...)
#   ・3 : 監視インターバル      ※ 秒単位
#   ・4 : 起動待ちタイムアウト  ※ 秒単位
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function jenkins.async_build() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -lt 3 ]; then
    log.error_console "Usage: jenkins.sync_build JOB [BUILD_PARAMETERS] INTERVAL TIMEOUT_START"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # ジョブ
  local _job="$1"

  # ビルドパラメータ
  local _build_param=""
  if [ $# -eq 4 ]; then
    _build_param="$2"
    shift
  fi

  # インターバル
  local _interval="$2"

  # 起動待ちタイムアウト
  local _timeout_start="$3"


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 最新のビルド結果から前回ビルドID取得
  local _before_build_id=`jenkins.get_latest_build_id ${_job}`

  #------------------------------------
  # ジョブ実行
  #------------------------------------
  log.debug_console "ジョブ実行"
  log.add_indent

  jenkins.local.execute_build "${_job}" "${_build_param}"
  local _cur_ret_code=$?
  if [ ${_cur_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  log.remove_indent

  #------------------------------------
  # 起動待機
  #------------------------------------
  log.debug_console "起動待機"
  log.add_indent

  # タイムアウト時刻(秒形式)を算出 ※ OSを考慮し date ではなく expr で加算
  local _sec_timeout_start=$(expr `date '+%s'` + ${_timeout_start})

  while :; do
    # 最新のビルドID取得
    local _cur_latest_build_id=`jenkins.get_latest_build_id ${_job}`

    # ビルドIDチェック
    if [ "${_cur_latest_build_id}" != "${_before_build_id}" ]; then
      # 前回ビルドIDと異なる場合 ※ ジョブ実行待機 → ジョブ実行中 に変わった場合
      log.debug_console "ジョブが起動されました。"
      break
    else
      # 前回ビルドIDと同じ場合 ※ ジョブ実行待機中
      log.debug_console "待機中..."
    fi

    # タイムアウトチェック
    if [ `date '+%s'` -ge ${_sec_timeout_start} ]; then
      log.error_console "ジョブ起動待機中にタイムアウトしました。"
      log.remove_indent 2
      return ${EXITCODE_ERROR}
    fi

    sleep ${_interval}
  done

  log.remove_indent


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  log.remove_indent
  return ${_ret_code}
}
