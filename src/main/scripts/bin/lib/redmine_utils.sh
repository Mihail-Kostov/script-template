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
#       ・${REDMINE_CURL_OPT}が事前に設定されていること
#
# 定義リスト
#   ・redmine.access_check
#   ・redmine.add_ticket
#   ・redmine.add_ticket_tree
#   ・redmine.retry_add_ticket
#   ・redmine.get_ticket
#   ・redmine.get_status
#   ・redmine.get_child_ticket_id_list
#   ・redmine.get_field_value
#   ・redmine.is_same_status
#   ・redmine.update_ticket_status
#   ・redmine.remove_ticket
#   ・redmine.replace_ticket_content
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 依存スクリプト読込み
#--------------------------------------------------------------------------------------------------
# ログ出力ユーティリティ
. ${DIR_BIN_LIB}/logging_utils.sh


#--------------------------------------------------------------------------------------------------
# 変数
#--------------------------------------------------------------------------------------------------
REDMINE__TIMEOUT=60
REDMINE__LIMIT=100


#--------------------------------------------------------------------------------------------------
# 概要
#   Redmineにアクセス可能かチェックします。
#   認証情報の妥当性チェックに利用することを想定しています。
#   内部的には プロジェクト指定なしで1チケットをrest apiで取得しています。
#
# 前提
#   なし
#
# 引数
#   ・1: RedmineプロジェクトID
#
# 出力
#   なし
#
# 戻り値
#   0: チケット登録に成功した場合
#   6: チケット登録に失敗した場合
#
#--------------------------------------------------------------------------------------------------
function redmine.access_check() {
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
  if [ "${_project_id}" = "" ]; then
    log.error_console "RedmineプロジェクトIDが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 取得用URL
  local _url="${REDMINE_URL}/projects/${_project_id}/issues.xml?key=${REDMINE_APIKEY}&limit=1"

  # リクエスト実行 ※登録したチケットIDを取得
  local _timestamp=`date '+%Y%m%d%H%M%S'`
  local _path_response="/tmp/${FUNCNAME[0]}_response_${_timestamp}_$$.xml"

  log.debug_console "curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X GET ${_url} -o \"${_path_response}\" -w '%{http_code}'"
  local _response_code=`curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X GET ${_url} -o "${_path_response}" -w '%{http_code}'`

  # レスポンスコードを確認
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1` -ne "2" ]; then
    # 200系以外の場合
    log.error_console "response_code: ${_response_code}"
    log.error_console "response     : `echo ""; cat ${_path_response}`"
    # エラー終了
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイルの削除
  rm -f ${_path_response}

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



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
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} REDMINE_PROJECT_ID PATH_TARGET_FILE"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # RedmineプロジェクトID
  local _project_id="$1"
  if [ "${_project_id}" = "" ]; then
    log.error_console "RedmineプロジェクトIDが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

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

  log.debug_console "curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X POST ${_url} -H 'Content-type: application/xml' --data-binary \"@${_path_ticket}\" -o \"${_path_response}\" -w '%{http_code}'"
  local _response_code=`curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X POST ${_url} -H 'Content-type: application/xml' --data-binary "@${_path_ticket}" -o "${_path_response}" -w '%{http_code}'`

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
#   指定のチケットテンプレートに親チケットIDを設定します。
#
# 引数
#   ・1: 親チケットID
#   ・2: チケットテンプレートパス
#   ・3: 出力ファイルパス
#
#--------------------------------------------------------------------------------------------------
function redmine.local.set_parent_ticket_id {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} PARENT_TICKET_ID PATH_TICKET_TEMPLATE PATH_OUTPUT"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 親チケットID
  local _parent_ticket_id="$1"

  # チケットテンプレート
  local _path_ticket_template="$2"
  if [ ! -f ${_path_ticket_template} ]; then
    log.error_console "指定のチケットテンプレートは存在しません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 出力先パス
  local _path_output="$3"
  if [ ! -d `dirname ${_path_output}` ]; then
    mkdir -p `dirname ${_path_output}`
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  log.debug_console "cat ${_path_ticket_template} | sed -e \"s|<issue>|<issue><parent_issue_id>${_parent_ticket_id}</parent_issue_id>|\"               > ${_path_output}"
  cat ${_path_ticket_template}                                                                     |
  sed -e "s|<issue>|<issue><parent_issue_id>${_parent_ticket_id}</parent_issue_id>|"               > ${_path_output}
  local _ret_code=$?
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    log.error_console "親チケットIDの設定でエラーが発生しました。親チケットID：${_parent_ticket_id}、チケットテンプレート：${_path_ticket_template}"
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
#   指定ディレクトリの構成に従って、親子関係を考慮してチケットを発行します。
#
# 前提
#   ・下記のディレクトリ構成に従っていること
#     ・TargetDir/
#       ・100_ParentTicket.xml
#       ・100_ParentTicket/
#         ・110_ChildTicket1.xml
#         ・120_ChildTicket2.xml
#         ・120_ChildTicket2/
#           ・121_GrandsonTicket.xml
#   ・配置されているxmlは、RedmineにREST APIで登録できるxmlのフォーマットになっていること
#   ・配置されているxmlは、parent要素が存在しないこと
#
# 引数
#   ・1: RedmineプロジェクトID
#   ・2: 対象ディレクトリ
#
# オプション
#   ・-p | --parent PARENT_TICKET_ID
#     親チケットID指定オプション
#     指定の親チケットIDの子チケットツリーとして登録します。
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
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _opt_parent_id=""
  local _USAGE="Usage: ${FUNCNAME[0]} [-p|--parent] REDMINE_PROJECT_ID DIR_TARGET"

  # オプション解析
  while :; do
    case $1 in
      -p|--parent)
        _opt_parent_id="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        log.error_console "${_USAGE}"
        log.remove_indent
        return ${EXITCODE_ERROR}
        ;;
      *)
        break
        ;;
    esac
  done

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # RedmineプロジェクトID
  local _project_id="$1"
  if [ "${_project_id}" = "" ]; then
    log.error_console "RedmineプロジェクトIDが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

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
    # 親チケットID設定
    if [ -n "${_opt_parent_id}" ]; then
      # オプションで親チケットIDが指定されている場合
      local _tmp_set_parent_id_filepath="${_DIR_WORK}/`basename ${cur_filepath}`"
      redmine.local.set_parent_ticket_id ${_opt_parent_id} ${cur_filepath} ${_tmp_set_parent_id_filepath}
      local _ret_code=$?
      if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
        return ${EXITCODE_ERROR}
      fi

      # ファイルパスを上書き
      cur_filepath=${_tmp_set_parent_id_filepath}
    fi

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
        echo -n `echo ${cur_filepath} | sed -e "s|${_dir_target}/||" | sed -e "s|${_DIR_WORK}/||" | sed -e "s|\.xml$||"`
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
      redmine.local.set_parent_ticket_id ${_cur_parent_id} ${cur_filepath} ${_tmp_filepath}
      local _cur_return_code=$?
      if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
        return ${EXITCODE_ERROR}
      fi

      # 一時ファイルを対象にして、チケット登録
#log.warn_console "redmine.add_ticket ${_project_id} ${_tmp_filepath}"
      local _cur_ticket_id=`redmine.add_ticket "${_project_id}" "${_tmp_filepath}"`

      # 戻り値を確認
      _cur_return_code=$?
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
  if [ "${_project_id}" = "" ]; then
    log.error_console "RedmineプロジェクトIDが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

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
#   ・3: 対象チケットが存在しない場合
#   ・6: エラーが発生した場合
#          ※レスポンス出力ファイルパスは作成されません。
#            リターンコードを利用できない場合は、ファイルの存在でエラーを判定できます。
#
#--------------------------------------------------------------------------------------------------
function redmine.get_ticket() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} TICKET_ID RESPONSE_OUTPUT_PATH"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # チケットID
  local _ticket_id="$1"
  if [ "${_ticket_id}" = "" ]; then
    log.error_console "チケットIDが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 出力ファイルパス
  local _path_out="$2"
  if [ "${_path_out}" = "" ]; then
    log.error_console "レスポンス出力ファイルパスが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  if [ ! -d `dirname ${_path_out}` ]; then
    mkdir -p `dirname ${_path_out}`
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 取得用URL
  local _url="${REDMINE_URL}/issues/${_ticket_id}.json?key=${REDMINE_APIKEY}"

  # リクエスト実行
  log.debug_console "curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X GET ${_url} -o ${_path_out} -w '%{http_code}'"
  local _response_code=`curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X GET ${_url} -o "${_path_out}" -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # httpレスポンスコードを表示
  echo "${_response_code}"

  log.remove_indent

  # レスポンスコードを確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" = "5" ]; then
    # curlエラーの場合 または 500系の場合、エラー終了
    rm -f "${_path_out}"
    return ${EXITCODE_ERROR}

  elif [ `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、警告終了
    return ${EXITCODE_WARN}
  fi
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
#   ・3: 対象チケットが存在しない場合
#   ・6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function redmine.get_status() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 1 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} TICKET_ID"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # チケットID
  local _ticket_id="$1"
  if [ "${_ticket_id}" = "" ]; then
    log.error_console "チケットIDが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # チケットデータ取得
  local _timestamp=`date '+%Y%m%d%H%M%S'`
  local _path_response="/tmp/redmine.get_status_response_${_timestamp}_$$.json"
  local _response_code=`redmine.get_ticket "${_ticket_id}" "${_path_response}"`
  if [ ! -f ${_path_response} ]; then
    # レスポンスファイルが存在しない場合、エラー
    return ${EXITCODE_ERROR}
  fi

  # ステータスを確認
  local _ticket_status=`                                                                            \
    cat ${_path_response}                                                                         | \
    ${DIR_BIN_LIB}/jq .                                                                           | \
    ${DIR_BIN_LIB}/Parsrs/parsrj.sh --xpath                                                       | \
    grep "/issue/status/name"                                                                     | \
    ${DIR_BIN_LIB}/Tukubai/self 2                                                                   \
  `

  echo "${_ticket_status}"

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # レスポンスファイルの削除
  rm -f ${_path_response}

  log.remove_indent

  if [ "${_ticket_status}" = "" ]; then
    return ${EXITCODE_WARN}
  fi
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#  指定の親チケットIDと紐付く子チケットのIDを全取得します。
#
# 前提
#   ・なし
#
# 引数
#   ・1: 親チケットID
#
# 標準出力
#   チケットID
#
# 戻り値
#   ・0: 正常終了の場合
#   ・6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function redmine.get_child_ticket_id_list() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 1 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} PARENT_TICKET_ID"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 親チケットID
  local _parent_ticket_id="$1"
  if [ "${_parent_ticket_id}" = "" ]; then
    log.error_console "親チケットIDが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  # 一時ディレクトリ
  local _dir_tmp="/tmp/${FUNCNAME[0]}_$$"
  mkdir -p ${_dir_tmp}

  # API取得結果ディレクトリ
  local _dir_response=${_dir_tmp}/response
  mkdir -p ${_dir_response}

  # チケットIDファイル
  local _path_ticket_id_list=${_dir_tmp}/ticket_id_list
  echo -n ""                                                                                       > ${_path_ticket_id_list}


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  #------------------------------------
  # チケット情報取得
  #------------------------------------
  # 取得用ベースURL ※ 実行時は末尾にページ番号付与
  local _base_url="${REDMINE_URL}/issues.json?key=${REDMINE_APIKEY}&set_filter=1&f\[\]=status_id&op\[status_id\]=*&v\[status_id\]\[\]=1&f\[\]=root_id&op\[root_id\]=%3D&v\[root_id\]\[\]=${_parent_ticket_id}&f\[\]=&limit=${REDMINE__LIMIT}"

  #--------------------------
  # 1ページ目のデータ取得
  #--------------------------
  local _cur_page=1
  # 1ページ目取得URL
  local _cur_url="${_base_url}&page=${_cur_page}"
  # 1ページ目の取得結果ファイル
  local _cur_path_output=${_dir_response}/page_${_cur_page}

  log.debug_console "ページ: ${_cur_page}"
  log.add_indent

  # リクエスト実行
  log.debug_console "curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X GET ${_cur_url} -o ${_cur_path_output} -w '%{http_code}'"
  local _cur_response_code=`curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X GET ${_cur_url} -o "${_cur_path_output}" -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_console "response code: ${_cur_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"

  # レスポンスコードを確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_cur_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
    rm -rf ${_dir_tmp}
    log.remove_indent 2
    return ${EXITCODE_ERROR}
  fi

  log.remove_indent

  # total_count取得
  local _total_count=`cat ${_cur_path_output} | ${DIR_BIN_LIB}/jq .total_count`

  # ページ数算出
  local _max_page=""
  if [ `expr ${_total_count} % ${REDMINE__LIMIT}` -eq 0 ]; then
    # 余り無しの場合
    _max_page=`expr ${_total_count} / ${REDMINE__LIMIT}`
  else
    # 余り有りの場合
    _max_page=`expr ${_total_count} / ${REDMINE__LIMIT} + 1`
  fi

  #--------------------------
  # 2ページ目以降のデータ取得
  #--------------------------
  _cur_page=2
  while [ ${_cur_page} -le ${_max_page} ]; do
    # 取得URL
    _cur_url="${_base_url}&page=${_cur_page}"
    # 取得結果ファイル
    _cur_path_output=${_dir_response}/page_${_cur_page}

    log.debug_console "ページ: ${_cur_page}"
    log.add_indent

    # リクエスト実行
    log.debug_console "curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X GET ${_cur_url} -o ${_cur_path_output} -w '%{http_code}'"
    _cur_response_code=`curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X GET ${_cur_url} -o "${_cur_path_output}" -w '%{http_code}'`
    _cur_return_code=$?
    log.debug_console "response code: ${_cur_response_code}"
    log.debug_console "return code  : ${_cur_return_code}"

    # レスポンスコードを確認
    if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_cur_response_code} | cut -c 1`"" != "2" ]; then
      # 200系以外の場合、エラー終了
      rm -rf ${_dir_tmp}
      log.remove_indent 2
      return ${EXITCODE_ERROR}
    fi

    log.remove_indent

    # 次のページへ
    _cur_page=`expr ${_cur_page} + 1`
  done

  #--------------------------
  # チケットID抽出
  #--------------------------
  for _cur_response_file in `find ${_dir_response} -type f | sort`; do
    # チケットIDを抽出
    cat ${_cur_response_file}                                                                      |
    ${DIR_BIN_LIB}/jq .                                                                            |
    ${DIR_BIN_LIB}/Parsrs/parsrj.sh --xpath                                                        |
    grep "^/issues\[[0-9]*\]/id"                                                                   |
    ${DIR_BIN_LIB}/Tukubai/self 2                                                                  >> ${_path_ticket_id_list}
  done

  # 結果出力
  cat ${_path_ticket_id_list}


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ディレクトリ削除
  rm -rf ${_dir_tmp}

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   対象のJsonファイルから指定フィールドの値を取得します。
#
# 前提
#   ・なし
#
# 引数
#   ・1: Jsonファイル ※ redmine.get_ticket で出力したファイルを指定して下さい
#   ・2: フィールド   ※ xpath 形式で指定して下さい
#
# 標準出力
#   フィールド値
#
# 戻り値
#   ・0: 正常終了の場合
#   ・6: 異常終了の場合
#
#--------------------------------------------------------------------------------------------------
function redmine.get_field_value() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} PATH_JSON TARGET_FIELD"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # Jsonパス
  local _path_json="$1"
  if [ ! -f ${_path_json} ]; then
    log.error_console "Jsonファイルが存在しません。Jsonファイル：${_path_json}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 抽出フィールド
  local _target_field="$2"

  # 改行コード
  local _lf=$'\\\x0A'


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # フィールド値取得
  local _value=`                                                                                     \
    cat ${_path_json}                                                                              | \
    ${DIR_BIN_LIB}/jq .                                                                            | \
    ${DIR_BIN_LIB}/Parsrs/parsrj.sh --xpath                                                        | \
    grep -F "${_target_field}"                                                                     | \
    head -n 1                                                                                      | \
    ${DIR_BIN_LIB}/Tukubai/self 2                                                                    \
  `

  # 出力 ※ 改行コードを考慮
  echo "${_value}" | sed 's|\\r\\n|'"${_lf}"'|g'


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
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
#   ・3: 対象チケットが存在しない場合
#   ・6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function redmine.is_same_status() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} TICKET_ID TARGET_STATUS"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # チケットID
  local _ticket_id="$1"
  if [ "${_ticket_id}" = "" ]; then
    log.error_console "チケットIDが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 確認対象ステータス
  local _target_status="$2"
  if [ "${_target_status}" = "" ]; then
    log.error_console "確認対象ステータスが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # チケットデータ取得
  local _ticket_status=`redmine.get_status "${_ticket_id}"`
  local _cur_return_code=$?

  # 取得結果を確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # チケット情報が取得できない場合、そのままのリターンコードを返す
    log.remove_indent
    return ${_cur_return_code}
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
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} TICKET_ID TARGET_STATUS_ID"
    return ${EXITCODE_ERROR}
  fi

  # チケットID
  local _ticket_id="$1"
  if [ "${_ticket_id}" = "" ]; then
    log.error_console "チケットIDが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 更新先ステータスID
  local _status_id="$2"
  if [ "${_status_id}" = "" ]; then
    log.error_console "TARGET_STATUS_ID が指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 更新用URL
  local _url="${REDMINE_URL}/issues/${_ticket_id}.xml?key=${REDMINE_APIKEY}"

  # 更新用データ
  local _update_data="<issue><status_id>${_status_id}</status_id></issue>"

  # リクエスト実行
  log.debug_console "curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X PUT ${_url} -H 'Content-type: application/xml' --data-binary ${_update_data} -o /dev/null -w '%{http_code}'"
  local _response_code=`curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X PUT ${_url} -H 'Content-type: application/xml' --data-binary "${_update_data}" -o /dev/null -w '%{http_code}'`
  local _cur_return_code=$?
  log.add_indent
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
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
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 1 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} TICKET_ID"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # チケットID
  local _ticket_id="$1"
  if [ "${_ticket_id}" = "" ]; then
    log.error_console "チケットIDが指定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 削除用URL
  local _url="${REDMINE_URL}/issues/${_ticket_id}?key=${REDMINE_APIKEY}"

  # リクエスト実行
  log.debug_console "curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X DELETE ${_url} -o /dev/null -w '%{http_code}'"
  local _response_code=`curl ${REDMINE_CURL_OPT} -s -m ${REDMINE__TIMEOUT} -X DELETE ${_url} -o /dev/null -w '%{http_code}'`
  local _cur_return_code=$?
  log.add_indent
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
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



#--------------------------------------------------------------------------------------------------
# 概要
#   指定のディレクトリに含まれるチケット内容ファイルを
#   共通置換定義・個別置換定義に従って置換します。
#
# 前提
#   下記のディレクトリ構成になっていること
#
#   - config/ticket_template
#     - replace.properties ※ 共通置換定義
#     - 置換対象ディレクトリ
#       - 100_ParentTicket.xml
#       - 100_ParentTicket/
#         - 110_ChildTicket1.xml
#         - 120_ChildTicket2.xml
#         - 120_ChildTicket2/
#           - 121_GrandsonTicket.xml
#       - replace.properties ※ 個別置換定義
#
# 引数
#   ・1: 置換対象ディレクトリ
#   ・2: 置換結果ディレクトリ
#   ・3: 動的置換定義          ※ 任意 個別置換定義と結合して置換を実施します。
#
# 標準出力
#   ・置換後のテンプレート
#
# 戻り値
#   ・0: 削除に成功した場合
#   ・6: 削除に失敗した場合
#
#--------------------------------------------------------------------------------------------------
function redmine.replace_ticket_content() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -lt 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} DIR_REPLACE_TARGET DIR_REPLACE_RESULT [PATH_DYNAMIC_REPLACE_PROPERTIES]"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 置換対象ディレクトリ
  local _dir_replace_target="$1"
  if [ ! -d ${_dir_replace_target} ]; then
    log.error_console "置換対象ディレクトリが存在しません。置換対象ディレクトリ：${_dir_replace_target}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 置換後ディレクトリ
  local _dir_replace_result="$2"

  # 動的置換定義
  local _path_dynamic_replace_properties=""
  if [ $# -eq 3 ]; then
    # 指定がある場合
    _path_dynamic_replace_properties="$3"
    if [ ! -f ${_path_dynamic_replace_properties} ]; then
      log.error_console "動的置換定義が存在しません。動的置換定義：${_path_dynamic_replace_propertie}"
      log.remove_indent
      return ${EXITCODE_ERROR}
    fi
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  #------------------------------------
  # 置換対象ディレクトリコピー
  #------------------------------------
  log.debug_console "置換対象ディレクトリコピー"
  log.add_indent

  if [ -d ${_dir_replace_result} ]; then
    # 既にコピー先ディレクトリが存在してる場合
    rm -rf ${_dir_replace_result}
  fi

  log.debug_console "cp -rf ${_dir_replace_target} ${_dir_replace_result}"
  cp -rf ${_dir_replace_target} ${_dir_replace_result}
  local _ret_code=$?
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    log.error_console "置換対象ディレクトリのコピーでエラーが発生しました。リターンコード$：{_ret_code}"
    log.remove_indent 2
    return ${EXITCODE_ERROR}
  fi

  log.remove_indent

  #------------------------------------
  # 文字列置換
  #------------------------------------
  log.debug_console "文字列置換"
  log.add_indent

  log.debug_console "動的置換定義 + 個別置換定義"
  log.add_indent

  # 個別置換定義
  local _path_individual_replace_properties=${_dir_replace_result}/replace.properties

  if [ -f "${_path_individual_replace_properties}" -o -n "${_path_dynamic_replace_properties}" ]; then
    # 個別置換定義、動的置換定義どちらかが存在する場合

    # 置換定義リスト
    local _properties_list=()
    if [ -n "${_path_dynamic_replace_properties}" ]; then
      # 動的置換定義追加
      _properties_list+=( ${_path_dynamic_replace_properties} )
    fi
    if [ -f "${_path_individual_replace_properties}" ]; then
      # 個別置換定義追加
      _properties_list+=( ${_path_individual_replace_properties} )
    fi

    # 置換定義分ループ
    log.debug_console "cat ${_properties_list[@]}"
    log.add_indent
    for _cur_replace_setting in `cat ${_properties_list[@]}`; do
      # 置換文字列
      local _cur_replace_string=${PLACEHOLDER_ENCLOSE}`echo ${_cur_replace_setting} | cut -d '=' -f 1`${PLACEHOLDER_ENCLOSE}
      # 置換値
      local _cur_replace_value=`echo ${_cur_replace_setting} | cut -d '=' -f 2`

      log.debug_console "replace: ${_cur_replace_string} to ${_cur_replace_value}"

      # ファイル分ループ
      for _cur_file_path in `find ${_dir_replace_result} -type f -name *.xml | sort`; do
        # 一時的に退避
        cp -f ${_cur_file_path} ${_cur_file_path}.tmp
        # 置換
        cat ${_cur_file_path}.tmp | sed -e "s|${_cur_replace_string}|${_cur_replace_value}|g"          > ${_cur_file_path}
        # 退避ファイル削除
        rm -f ${_cur_file_path}.tmp
      done
    done
    log.remove_indent

  else
    # 個別置換定義、動的置換定義どちらも存在しない場合
    log.debug_console "スキップしました。"
  fi

  log.remove_indent

  log.debug_console "共通置換定義"
  log.add_indent

  # 共通置換定義
  local _path_common_replace_properties=${DIR_TICKET_TEMPLATE_ROOT}/replace.properties

  if [ -f "${_path_common_replace_properties}" ]; then
    # 共通置換定義が存在する場合

    # 置換定義分ループ
    log.debug_console "cat ${_path_common_replace_properties}"
    log.add_indent
    for _cur_replace_setting in `cat ${_path_common_replace_properties}`; do
      # 置換文字列
      local _cur_replace_string=${PLACEHOLDER_ENCLOSE}`echo ${_cur_replace_setting} | cut -d '=' -f 1`${PLACEHOLDER_ENCLOSE}
      # 置換値
      local _cur_replace_value=`echo ${_cur_replace_setting} | cut -d '=' -f 2`

      log.debug_console "replace: ${_cur_replace_string} to ${_cur_replace_value}"

      # ファイル分ループ
      for _cur_file_path in `find ${_dir_replace_result} -type f -name *.xml | sort`; do
        # 一時的に退避
        cp -f ${_cur_file_path} ${_cur_file_path}.tmp
        # 置換
        cat ${_cur_file_path}.tmp | sed -e "s|${_cur_replace_string}|${_cur_replace_value}|g"          > ${_cur_file_path}
        # 退避ファイル削除
        rm -f ${_cur_file_path}.tmp
      done
    done
    log.remove_indent

  else
    # 共通置換定義が存在しない場合
    log.debug_console "スキップしました。"
  fi

  log.remove_indent 2


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  log.remove_indent
  return ${EXITCODE_SUCCESS}
}
