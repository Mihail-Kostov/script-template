#!/bin/bash
#set -eux
#==================================================================================================
# Redmineユーティリティ
#
# 前提
#   ・setenv.sh を事前に読み込んでいること
#       ・${REDMINE_URL}が事前に設定されていること
#       ・${REDMINE_APIKEY}が事前に設定されていること
#       ・${DIR_REDMINE_RETRY}が事前に設定されていること
#
# 定義リスト
#   ・redmine.add_ticket
#   ・redmine.add_ticket_tree
#   ・redmine.retry_add_ticket
#   ・redmine.get_ticket
#   ・redmine.get_status
#   ・redmine.is_same_status
#   ・redmine.update_ticket_status
#   ・redmine.remove_ticket
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 依存スクリプト読込み
#--------------------------------------------------------------------------------------------------
# ログ出力ユーティリティ
. ${DIR_BIN_LIB}/logging_utils.sh



#--------------------------------------------------------------------------------------------------
# 概要
#   指定XMLファイルの内容で、単一のチケットを発行します。
#
#   Redmineのメンテナンス中や、指定ファイルの記載内容不備などでチケット登録に失敗した場合は
#   リトライディレクトリに、指定XMLファイルをコピーします。
#
# 前提
#   ・配置されているxmlは、RedmineにREST APIで登録できるxmlのフォーマットになっていること
#
# 引数
#   ・1: RedmineプロジェクトID
#   ・2: チケット内容ファイルパス
#
# 標準出力
#   登録したチケットID
#
# 戻り値
#   0: チケット登録に成功した場合
#   6: チケット登録に失敗した場合
#
#--------------------------------------------------------------------------------------------------
function redmine.add_ticket() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_log "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} REDMINE_PROJECT_ID PATH_TARGET_FILE"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # RedmineプロジェクトID
  local _project_id="$1"

  # チケット内容ファイルパス
  local _path_ticket="$2"
  if [ ! -f ${_path_ticket} ]; then
    log.error_console "${_path_ticket} は存在しません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 対象ファイルからトラッカーIDを取得
  local _tracker_id=`                                                                               \
    cat ${_path_ticket}                                                                           | \
    ${DIR_BIN_LIB}/Parsrs/parsrx.sh                                                               | \
    grep "/issue/tracker/@id"                                                                     | \
    ${DIR_BIN_LIB}/Tukubai/self 2                                                                   \
  `

  # 登録用URL
  local _url="${REDMINE_URL}/projects/${_project_id}/issues.xml?key=${REDMINE_APIKEY}&tracker_id=${_tracker_id}"

  # リクエスト実行 ※登録したチケットIDを取得
  local _timestamp=`date '+%Y%m%d%H%M%S'`
  local _path_response="/tmp/`basename $0`_response_${_timestamp}_$$.xml"

  log.debug_log "curl -s -X POST ${_url} -H 'Content-type: application/xml' --data-binary \"@${_path_ticket}\" -o \"${_path_response}\" -w '%{http_code}'"
  local _response_code=`curl -s -X POST ${_url} -H 'Content-type: application/xml' --data-binary "@${_path_ticket}" -o "${_path_response}" -w '%{http_code}'`

  # レスポンスコードを確認
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1` -ne "2" ]; then
    # 200系以外の場合
    # リトライファイルを作成 ※対象ファイル名_タイムスタンプ_PID
    if [ ! -d ${DIR_REDMINE_RETRY} ]; then
      mkdir -p ${DIR_REDMINE_RETRY}
    fi

    log.error_console "response_code: ${_response_code}"
    log.error_console "response     : `echo ""; cat ${_path_response}`"
    log.error_console "request      : `echo ""; cat ${_path_ticket}`"
    log.error_console "cp -p ${_path_ticket} ${DIR_REDMINE_RETRY}/`basename ${_path_ticket} .xml`_${_timestamp}_$$.xml"
    cp -p ${_path_ticket} ${DIR_REDMINE_RETRY}/`basename ${_path_ticket} .xml`_${_timestamp}_$$.xml
    # エラー終了
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # レスポンスの内容から登録したチケットIDを取得
  local _registered_id=`                                                                            \
    cat ${_path_response}                                                                         | \
    ${DIR_BIN_LIB}/Parsrs/parsrx.sh                                                               | \
    grep "/issue/id"                                                                              | \
    ${DIR_BIN_LIB}/Tukubai/self 2                                                                   \
  `

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイルの削除
  rm -f ${_path_response}

  echo "${_registered_id}"
  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   指定ディレクトリの構成に従って、親子関係を考慮してチケットを発行します。
#
# 前提
#   ・下記のディレクトリ構成に従っていること
#     ・TargetDir/
#       ・100_ParentTicket.xml
#       ・100_ParentTicket/
#         ・110_ChildTicket1.xml
#         ・120_ChildTicket2.xml
#           ・120_ChildTicket2/
#             ・121_GrandsonTicket.xml
#   ・配置されているxmlは、RedmineにREST APIで登録できるxmlのフォーマットになっていること
#   ・配置されているxmlは、parent要素が存在しないこと
#
# 引数
#   ・1: RedmineプロジェクトID
#   ・2: 対象ディレクトリ
#
# 標準出力
#   ・レイアウト
#     相対レイアウトパス 登録チケットID
#
#--------------------------------------------------------------------------------------------------
function redmine.add_ticket_tree() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_log "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} REDMINE_PROJECT_ID DIR_TARGET"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # RedmineプロジェクトID
  local _project_id="$1"

  # 対象ディレクトリ
  local _dir_target="$2"
  if [ ! -d ${_dir_target} ]; then
    log.error_console "${_dir_target} は存在しません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 作業ディレクトリ
  local readonly _DIR_WORK="/tmp/redmine.add_ticket_tree_$$"
  # 登録チケット一覧
  local readonly _PATH_TMP_RESULT="${_DIR_WORK}/result.tmp"
  # 現在チケットリスト ※子階層での親チケット相当
  local readonly _PATH_CUR_ID_LIST="${_DIR_WORK}/cur_id.lst"
  # 親チケットリスト
  local readonly _PATH_PARENT_ID_LIST="${_DIR_WORK}/parent_id.lst"

  # 作業ディレクトリの作成
  mkdir -p ${_DIR_WORK}

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 1階層目直下のxmlファイルをループ
  for cur_filepath in `find "${_dir_target}" -mindepth 1 -maxdepth 1 -type f -name "*.xml" | sort`; do
    # 現在ファイルを対象にして、チケット登録
#log.warn_console "redmine.add_ticket ${_project_id} ${cur_filepath}"
    local _cur_ticket_id=`redmine.add_ticket "${_project_id}" "${cur_filepath}"`

    # 戻り値を確認
    local _cur_return_code=$?
    if [ ${_cur_return_code} -eq ${EXITCODE_SUCCESS} ]; then
      # 登録できた場合、現在ファイル名=取得したチケットID で親チケット一覧に登録
      echo "`basename ${cur_filepath} .xml`=${_cur_ticket_id}"                                    >> ${_PATH_PARENT_ID_LIST}
      # 現在ファイルパス 現在チケットID で結果一時ファイルに追記
      {
        echo -n `echo ${cur_filepath} | sed -e "s|${_dir_target}/||" | sed -e "s|\.xml$||"`
        echo -n " "
        echo -n "${_cur_ticket_id}"
        echo ""
      }                                                                                           >> ${_PATH_TMP_RESULT}
    else
      # 登録できなかった場合、後続の整合性が取れないため、エラー終了
      return ${EXITCODE_ERROR}
    fi
  done

  # 最大ディレクトリ深度を取得
  local _max_depth=`
    find "${_dir_target}" -type f -name "*.xml"                                                   | \
    sed -e "s|${_dir_target}/||"                                                                  | \
    awk '                                                                                           \
      BEGIN { maxDepth = 1; }                                                                       \
      {                                                                                             \
        curDepth = gsub(/\//, "_") + 1;                                                             \
        if ( curDepth > maxDepth ) {                                                                \
          maxDepth = curDepth;                                                                      \
        }                                                                                           \
      }                                                                                             \
      END { print maxDepth; }                                                                       \
    '                                                                                               \
  `

  # 2〜最大深度までループ
  for cur_depth in `seq 2 1 ${_max_depth}`; do
    # 現在深度直下のxmlファイルをループ
    for cur_filepath in `find "${_dir_target}" -mindepth ${cur_depth} -maxdepth ${cur_depth} -type f -name "*.xml" | sort`; do
      # 親ディレクトリ名を取得
      local _cur_parent_name=$(basename $(dirname ${cur_filepath}))

      # 親チケット一覧から、親チケットIDを取得
      local _cur_parent_id=`                                                                        \
        cat ${_PATH_PARENT_ID_LIST}                                                               | \
        grep "${_cur_parent_name}="                                                               | \
        cut -d "=" -f 2                                                                             \
      `

      # 親チケットIDが取得できない場合、後続の整合性が取れないため、エラー終了
      if [ "${_cur_parent_id}" = "" ]; then
        return ${EXITCODE_ERROR}
      fi

      # 現在ファイルに親チケットID要素を付与した一時ファイルを作成
      local _tmp_filepath="${_DIR_WORK}/`basename ${cur_filepath}`"
      cat ${cur_filepath}                                                                         |
      sed -e "s|<issue>|<issue><parent_issue_id>${_cur_parent_id}</parent_issue_id>|"             > ${_tmp_filepath}

      # 一時ファイルを対象にして、チケット登録
#log.warn_console "redmine.add_ticket ${_project_id} ${_tmp_filepath}"
      local _cur_ticket_id=`redmine.add_ticket "${_project_id}" "${_tmp_filepath}"`

      # 戻り値を確認
      local _cur_return_code=$?
      if [ ${_cur_return_code} -eq ${EXITCODE_SUCCESS} ]; then
        # 登録できた場合、現在ファイル名=取得したチケットID で、現在チケット一覧に登録
        echo "`basename ${cur_filepath} .xml`=${_cur_ticket_id}"                                  >> ${_PATH_CUR_ID_LIST}
        # 現在ファイルパス 現在チケットID で結果一時ファイルに追記
        {
          echo -n `echo ${cur_filepath} | sed -e "s|${_dir_target}/||" | sed -e "s|\.xml$||"`
          echo -n " "
          echo -n "${_cur_ticket_id}"
          echo ""
        }                                                                                         >> ${_PATH_TMP_RESULT}
      else
        # 登録できなかった場合、後続の整合性が取れないため、エラー終了
        return ${EXITCODE_ERROR}
      fi

    done # ファイルループ END

    # 現在チケット一覧 → 親チケット一覧 にリネーム
    rm -f ${_PATH_PARENT_ID_LIST}
    mv ${_PATH_CUR_ID_LIST} ${_PATH_PARENT_ID_LIST}

  done # 階層ループ END

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 結果の標準出力
  cat ${_PATH_TMP_RESULT}

  # 作業ディレクトリの削除
  rm -fr ${_DIR_WORK}

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   リトライディレクトリ直下のXMLファイルの内容でチケットを発行します。
#
# 前提
#   ・なし
#
# 引数
#   ・1: RedmineプロジェクトID
#
# 出力
#   なし
#
#--------------------------------------------------------------------------------------------------
function redmine.retry_add_ticket() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 1 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} REDMINE_PROJECT_ID"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # RedmineプロジェクトID
  local _project_id="$1"

  # リトライディレクトリ
  if [ ! -d ${DIR_REDMINE_RETRY} ]; then
    log.error_console "${DIR_REDMINE_RETRY} は存在しません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 戻り値
  local _return_code=${EXITCODE_SUCCESS}

  # リトライディレクトリ直下のxmlファイルをループ
  for cur_filepath in `find ${DIR_REDMINE_RETRY} -maxdepth 1 -type f -name "*.xml"`; do
    # 現在ファイルを対象にして、チケット登録
    redmine.add_ticket "${_project_id}" "${cur_filepath}"

    # 戻り値を更新
    local _cur_return_code=$?
    if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
      _return_code=${_cur_return_code}
    fi

    # 成功失敗にかかわらず、現在ファイルを削除 ※失敗時は、新たなリトライファイルが作成されているため
    rm -f "${cur_filepath}"
  done

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  log.remove_indent
  return ${_return_code}
}



#--------------------------------------------------------------------------------------------------
# 概要
#  指定チケットIDのデータを取得します。
#
# 前提
#   ・なし
#
# 引数
#   ・1: チケットID
#   ・2: レスポンス出力ファイルパス
#
# ファイル出力
#   ・引数で指定された出力ファイルパス
#
# 標準出力
#   ・httpレスポンスコード
#
# 戻り値
#   ・0: httpレスポンスコードが200番台の場合
#   ・6: 対象チケットが存在しない場合
#
#--------------------------------------------------------------------------------------------------
function redmine.get_ticket() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_log "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} TICKET_ID RESPONSE_OUTPUT_PATH"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # チケットID
  local _ticket_id="$1"

  # 出力ファイルパス
  local _path_out="$2"
  if [ ! -d `dirname ${_path_out}` ]; then
    mkdir -p `dirname ${_path_out}`
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 取得用URL
  local _url="${REDMINE_URL}/issues/${_ticket_id}.json?key=${REDMINE_APIKEY}"

  # リクエスト実行
  log.debug_log "curl -s -X GET ${_url} -o ${_path_out} -w '%{http_code}'"
  local _response_code=`curl -s -X GET ${_url} -o "${_path_out}" -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_log "response code: ${_response_code}"
  log.debug_log "return code  : ${_cur_return_code}"

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # httpレスポンスコードを表示
  echo "${_response_code}"

  # レスポンスコードを確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
    return ${EXITCODE_ERROR}
  fi

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   指定チケットIDのステータスを返します。
#
# 前提
#   ・なし
#
# 引数
#   ・1: チケットID
#
# 標準出力
#   チケットステータス
#
# 戻り値
#   ・0: ステータスが取得できた場合
#   ・6: 対象チケットが存在しない場合
#
#--------------------------------------------------------------------------------------------------
function redmine.get_status() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_log "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 1 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} TICKET_ID"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # チケットID
  local _ticket_id="$1"

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # チケットデータ取得
  local _timestamp=`date '+%Y%m%d%H%M%S'`
  local _path_response="/tmp/${FUNCNAME[0]}_response_${_timestamp}_$$.json"
  local _response_code=`redmine.get_ticket "${_ticket_id}" "${_path_response}"`
  local _cur_return_code=$?

  # 取得結果を確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # ステータスを確認
  local _ticket_status=`                                                                           \
    cat ${_path_response}                                                                        | \
    ${DIR_BIN_LIB}/jq .                                                                          | \
    ${DIR_BIN_LIB}/Parsrs/parsrj.sh --xpath                                                      | \
    grep "/issue/status/name"                                                                    | \
    ${DIR_BIN_LIB}/Tukubai/self 2                                                                  \
  `

  echo "${_ticket_status}"

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # レスポンスファイルの削除
  rm -f ${_path_response}

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   指定チケットIDのステータスが、指定ステータスと一致するか否かを返します。
#
# 前提
#   ・なし
#
# 引数
#   ・1: チケットID
#   ・2: 確認対象ステータス
#
# 標準出力
#   ・true : 一致した場合
#   ・false: 不一致の場合
#
# 戻り値
#   ・0: 一致した or 不一致の場合
#   ・6: 対象チケットが存在しない場合
#
#--------------------------------------------------------------------------------------------------
function redmine.is_same_status() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_log "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} TICKET_ID TARGET_STATUS"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # チケットID
  local _ticket_id="$1"

  # 確認対象ステータス
  local _target_status="$2"

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # チケットデータ取得
  local _ticket_status=`redmine.get_status "${_ticket_id}"`
  local _cur_return_code=$?

  # 取得結果を確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS}  ]; then
    # 200系以外の場合、エラー終了
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  if [ "${_target_status}" = "${_ticket_status}" ]; then
    echo "true"
  else
    echo "false"
  fi

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # レスポンスファイルの削除
  rm -f ${_path_response}

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   チケットのステータスを更新します。
#
# 前提
#   ・なし
#
# 引数
#   ・1: チケットID
#   ・2: 更新先ステータスID
#
# 標準出力
#   ・httpレスポンスコード
#
# 戻り値
#   ・0: 更新に成功した場合
#   ・6: 更新に失敗した場合
#
#--------------------------------------------------------------------------------------------------
function redmine.update_ticket_status() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_log "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: redmine.update_ticket_status TICKET_ID TARGET_STATUS_ID"
    return ${EXITCODE_ERROR}
  fi

  # チケットID
  local _ticket_id="$1"

  # 更新先ステータスID
  local _status_id="$2"

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 更新用URL
  local _url="${REDMINE_URL}/issues/${_ticket_id}.xml?key=${REDMINE_APIKEY}"

  # 更新用データ
  local _update_data="<issue><status_id>${_status_id}</status_id></issue>"

  # リクエスト実行
  log.debug_log "curl -s -X PUT ${_url} -H 'Content-type: application/xml' --data-binary ${_update_data} -o /dev/null -w '%{http_code}'"
  local _response_code=`curl -s -X PUT ${_url} -H 'Content-type: application/xml' --data-binary "${_update_data}" -o /dev/null -w '%{http_code}'`
  local _cur_return_code=$?
  log.add_indent
  log.debug_log "response code: ${_response_code}"
  log.debug_log "return code  : ${_cur_return_code}"
  log.remove_indent

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # httpレスポンスコードを表示
  echo "${_response_code}"

  # レスポンスコードを確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#  指定チケットを削除します。
#
# 前提
#   ・なし
#
# 引数
#   ・1: チケットID
#
# 標準出力
#   ・httpレスポンスコード
#
# 戻り値
#   ・0: 削除に成功した場合
#   ・6: 削除に失敗した場合
#
#--------------------------------------------------------------------------------------------------
function redmine.remove_ticket() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_log "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 1 ]; then
    log.error_console "Usage: redmine.remove_ticket TICKET_ID"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # チケットID
  local _ticket_id="$1"

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 削除用URL
  local _url="${REDMINE_URL}/issues/${_ticket_id}?key=${REDMINE_APIKEY}"

  # リクエスト実行
  log.debug_log "curl -s -X DELETE ${_url} -o /dev/null -w '%{http_code}'"
  local _response_code=`curl -s -X DELETE ${_url} -o /dev/null -w '%{http_code}'`
  local _cur_return_code=$?
  log.add_indent
  log.debug_log "response code: ${_response_code}"
  log.debug_log "return code  : ${_cur_return_code}"
  log.remove_indent

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # httpレスポンスコードを表示
  echo "${_response_code}"

  # レスポンスコードを確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_response_code}" != "302" ]; then
    # 302以外の場合、エラー終了
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}
