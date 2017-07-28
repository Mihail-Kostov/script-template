#!/bin/bash
#set -eux
#==================================================================================================
# SonarQubeユーティリティ
#
# 前提
#   ・setenv.sh を事前に読み込んでいること
#       ・${SONARQUBE_URL}が事前に設定されていること
#
# 定義リスト
#   ・sonarqube.is_passed_qualitygates
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 依存スクリプト読込み
#--------------------------------------------------------------------------------------------------
# ログ出力ユーティリティ
. ${DIR_BIN_LIB}/logging_utils.sh


#--------------------------------------------------------------------------------------------------
# 定数
#--------------------------------------------------------------------------------------------------
SONARQUBE__STATUS_OK="OK"
SONARQUBE__STATUS_ERROR="ERROR"


#--------------------------------------------------------------------------------------------------
# 概要
#   （Util Private）SONARQUBE API 実行処理
#
# 前提
#   なし
#
# 引数
#   ・1: リクエストURL
#   ・2: レスポンスファイルパス
#
# 出力
#   レスポンスファイル
#
#--------------------------------------------------------------------------------------------------
function sonarqube.local.execute_api() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} REQUEST_URL PATH_RESPONSE"
    log.restore_indent
    return ${EXITCODE_ERROR}
  fi

  # リクエストURL
  local _request_url="$1"
  # レスポンスファイルパス
  local _path_response="$2"
  if [ ! -d `dirname ${_path_response}` ]; then
    mkdir -p `dirname ${_path_response}`
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  log.debug_console "リクエスト実行"
  log.add_indent

  # リクエスト実行
  log.debug_console "curl -s ${_request_url}"
  curl -s ${_request_url}                                                                          |
  tee > ${_path_response}
  local _ret_code=${PIPESTATUS[0]}
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    log.error_console "リクエスト実行でエラーが発生しました。リターンコード：${_ret_code}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  log.remove_indent


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  log.remove_indent
  return ${EXITCODE_SUCCESS}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   （Util Private）グループID取得
#
# 前提
#   なし
#
# 引数
#   ・1: pom.xml ファイルパス
#
# 標準出力
#   グループID
#
#--------------------------------------------------------------------------------------------------
function sonarqube.local.get_group_id() {
  # 親グループID
  local _group_id=$(                                                                                 \
    cat $1                                                                                         | \
    ${DIR_BIN_LIB}/Parsrs/parsrx.sh                                                                | \
    grep "project/parent/groupId"                                                                  | \
    ${DIR_BIN_LIB}/Tukubai/self 2                                                                    \
  )

  if [ "${_group_id}" = "" ]; then
    # 親グループIDが存在しない場合 ※ 自身のグループIDを取得
    _group_id=$(                                                                                     \
      cat $1                                                                                       | \
      ${DIR_BIN_LIB}/Parsrs/parsrx.sh                                                              | \
      grep "project/groupId"                                                                       | \
      ${DIR_BIN_LIB}/Tukubai/self 2                                                                  \
    )
  fi
  
  echo ${_group_id}

  return ${EXITCODE_SUCCESS}

}


#--------------------------------------------------------------------------------------------------
# 概要
#   （Util Private）アーティファクトID取得
#
# 前提
#   なし
#
# 引数
#   ・1: pom.xml ファイルパス
#
# 標準出力
#   アーティファクトID
#
#--------------------------------------------------------------------------------------------------
function sonarqube.local.get_artifact_id() {
  # アーティファクトID
  local _artifact_id=$(                                                                              \
    cat $1                                                                                         | \
    ${DIR_BIN_LIB}/Parsrs/parsrx.sh                                                                | \
    grep "project/artifactId"                                                                      | \
    ${DIR_BIN_LIB}/Tukubai/self 2                                                                    \
   )

  echo ${_artifact_id}

  return ${EXITCODE_SUCCESS}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   QualityGate通過判定
#
# 前提
#   なし
#
# 引数
#   ・1: MVN プロジェクトディレクトリ
#
# 標準出力
#   なし
#
# 戻り値
#   0: 通過できた場合
#   3: 通過できなかった場合
#   6: 異常終了の場合
#
#--------------------------------------------------------------------------------------------------
function sonarqube.is_passed_qualitygates() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 1 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} DIR_MAVEN_PROJ"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # プロジェクトディレクトリ名
  local _dir_mvn_proj="$1"
  if [ ! -d ${_dir_mvn_proj} ]; then
    log.error_console "指定のプロジェクトディレクトリは存在していません。プロジェクトディレクトリ：${_dir_mvn_proj}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # pom.xml パス
  local _path_pom=${_dir_mvn_proj}/pom.xml
  if [ ! -f ${_path_pom} ]; then
    log.error_console "指定のプロジェクトディレクトリ直下に pom.xml が存在していません。プロジェクトディレクトリ：${_dir_mvn_proj}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # グループID取得
  local _group_id=$(sonarqube.local.get_group_id "${_path_pom}")
  # アーティファクトID取得
  local _artifact_id=$(sonarqube.local.get_artifact_id "${_path_pom}")
  # プロジェクトキー
  local _project_key="${_group_id}:${_artifact_id}"

  # プロジェクト情報
  log.debug_console "プロジェクト情報"
  log.add_indent
  log.debug_console "グループID         : ${_group_id}"
  log.debug_console "アーティファクトID : ${_artifact_id}"
  log.debug_console "プロジェクトキー   : ${_project_key}"
  log.remove_indent

  # ステータス取得URL
  local _url=${SONARQUBE_URL}/api/qualitygates/project_status?projectKey=${_project_key}

  # レスポンスパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  sonarqube.local.execute_api "${_url}" "${_path_response}"
  local _ret_code=$?
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 取得結果出力
  log.debug_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_console
  log.remove_indent

  # ステータス
  local _status=$(                                                                                   \
    cat ${_path_response}                                                                          | \
    ${DIR_BIN_LIB}/jq .projectStatus.status                                                        | \
    sed -e 's|^"||'                                                                                | \
    sed -e 's|"$||'                                                                                  \
  )

  # 結果判定
  if [ "${_status}" = "${SONARQUBE__STATUS_OK}" ]; then
    # OK の場合
    log.info_console "QualityGateを通過しました。"
    _ret_code=${EXITCODE_SUCCESS}
  elif [ "${_status}" = "${SONARQUBE__STATUS_ERROR}" ]; then
    # ERROR の場
    log.warn_console "QualityGateを通過できませんでした。"

    # ピリオド
    local _periods=$(                                                                                \
      cat ${_path_response}                                                                        | \
      ${DIR_BIN_LIB}/jq .projectStatus.periods                                                       \
    )

    # 条件
    local _conditions=$(                                                                             \
      cat ${_path_response}                                                                        | \
      ${DIR_BIN_LIB}/jq .projectStatus.conditions                                                    \
    )

    # ステータス情報
    log.warn_console "ステータス情報"
    log.add_indent
    log.warn_console "periods   : ${_periods}"
    log.warn_console "conditions: ${_conditions}"
    log.remove_indent

    _ret_code=${EXITCODE_WARN}

  else
    # リクエスト実行エラーの場合
    log.error_console "QualityGateステータス取得に失敗しました。"
    _ret_code=${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # レスポンスファイル削除
  rm -f ${_path_response} > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}
