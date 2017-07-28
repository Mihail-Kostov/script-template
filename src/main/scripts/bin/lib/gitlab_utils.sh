#!/bin/bash
#set -eux
#==================================================================================================
# GitLabユーティリティ
#
# 前提
#   ・setenv.sh を事前に読み込んでいること
#       ・${GITLAB_URL}が事前に設定されていること
#       ・${GITLAB_APIKEY}が事前に設定されていること
#
# 定義リスト
#   ・gitlab.is_protected_branch
#   ・gitlab.protect_branch
#   ・gitlab.unprotect_branch
#   ・gitlab.get_merge_request
#   ・gitlab.has_merge_request
#   ・gitlab.create_merge_request
#   ・gitlab.update_merge_request
#   ・gitlab.delete_merge_request
#   ・gitlab.get_merge_request_comment
#   ・gitlab.create_merge_request_comment
#   ・gitlab.update_merge_request_comment
#   ・gitlab.delete_merge_request_comment
#   ・gitlab.upload_file
#   ・gitlab.is_exist_tag_release
#   ・gitlab.update_tag_release
#   ・gitlab.attachment_archive
#   ・gitlab.get_project_member
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
GITLAB__REQ_PERPAGE=${GITLAB_REQ_PERPAGE:-100}
GITLAB__TIMEOUT_SEC=${GITLAB_TIMEOUT_SEC:-300}
GITLAB__MAX_RETRY_COUNT=${GITLAB_MAX_RETRY_COUNT:-2}
GITLAB__RETRY_INTERVAL=${GITLAB_RETRY_INTERVAL:-10}


#--------------------------------------------------------------------------------------------------
# 概要
#   （Util Private）GITLAB API 実行処理
#
# 前提
#   なし
#
# オプション
#   ・-f | --form PRAM
#     curl コマンド実行時に -F オプション指定して実行します。
#   ・-db | --data-binary DATA
#     curl コマンド実行時に --data-binary オプション指定して実行します。
#
# 引数
#   ・1: HTTPメソッド           ※ GET | POST | PUT | DELETE
#   ・2: リクエストURL          ※ GETの場合、 per_page,page は処理内で考慮するため指定しないで下さい。
#   ・3: レスポンスファイルパス
#
# 出力
#   レスポンスファイル
#   ※ GETの場合はページング分を結合して出力します。
#
#--------------------------------------------------------------------------------------------------
function gitlab.local.execute_api() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.save_indent
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _option=""
  local _USAGE="Usage: ${FUNCNAME[0]} [-f PARAM] HTTP_METHOD REQUEST_URL PATH_RESPONSE"

  # オプション解析
  while :; do
    case $1 in
      -f|--form)
        _option="-f $2"
        shift 2
        ;;
      -db | --data-binary)
        _option="-db $2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        log.error_console "${_USAGE}"
        log.restore_indent
        return ${EXITCODE_ERROR}
        ;;
      *)
        break
        ;;
    esac
  done

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "${_USAGE}"
    log.restore_indent
    return ${EXITCODE_ERROR}
  fi

  # HTTPメソッド
  local _http_method="$1"
  if [ "${_http_method}" != "GET" -a "${_http_method}" != "POST" -a "${_http_method}" != "PUT" -a "${_http_method}" != "DELETE" ]; then
    log.error_console "HTTPメソッドには GET / POST / PUT / DELETE のいずれかを指定して下さい。HTTPメソッド：${_http_method}"
    log.restore_indent
    return ${EXITCODE_ERROR}
  fi

  # リクエストURL
  local _request_url="$2"

  # レスポンスファイルパス
  local _path_response="$3"


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # HTTPメソッド判定
  if [ "${_http_method}" = "GET" ]; then
    # GET の場合
    gitlab.local.execute_api.get ${_option} "${_http_method}" "${_request_url}" "${_path_response}"
    local _ret_code=$?
  else
    # GET 以外の場合
    gitlab.local.execute_api.other ${_option} "${_http_method}" "${_request_url}" "${_path_response}"
    local _ret_code=$?
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  log.restore_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   （Util Private）GITLAB API の GET 処理
#    ※ このFunctionを直接実行するのではなく gitlab.local.execute_api を実行して下さい。
#
# 前提
#   なし
#
# オプション
#   ・-f | --form PRAM
#     curl コマンド実行時に -F オプション指定して実行します。
#
# 引数
#   ・1: HTTPメソッド           ※ GETのみ
#   ・2: リクエストURL          ※ per_page,page は処理内で考慮するため指定しないで下さい。
#   ・3: レスポンスファイルパス
#
# 出力
#   レスポンスファイル
#   ※ ページング分を結合して出力します。
#
#--------------------------------------------------------------------------------------------------
function gitlab.local.execute_api.get() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _is_form_param=false
  local _form_param=""
  local _USAGE="Usage: ${FUNCNAME[0]} [-f PARAM] HTTP_METHOD REQUEST_URL PATH_RESPONSE"

  # オプション解析
  while :; do
    case $1 in
      -f|--form)
        _is_form_param=true
        _form_param="$2"
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
  if [ $# -ne 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # HTTPメソッド
  local _http_method="$1"
  if [ "${_http_method}" != "GET"  ]; then
    log.error_console "HTTPメソッドに GET 以外が指定されています。HTTPメソッド：${_http_method}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # リクエストURL
  local _request_url="$2"

  # レスポンスファイルパス
  local _path_response="$3"
  if [ ! -d  `dirname ${_path_response}` ]; then
    mkdir -p `dirname ${_path_response}`
  fi
  echo -n ""                                                                                       > ${_path_response}

  # 作業ディレクトリ
  local _dir_work=/tmp/${FUNCNAME[0]}_$$
  mkdir -p ${_dir_work}


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  #------------------------------------
  # リクエスト実行
  #------------------------------------
  log.debug_console "リクエスト実行"
  log.add_indent

  # ページ分ループ
  local _cur_page=1
  local _page_count=0
  while :; do
    # レスポンスファイル - ヘッダ
    local _cur_path_res_header=${_dir_work}/res_header_${_cur_page}
    # レスポンスファイル - ボディ
    local _cur_path_res_body=${_dir_work}/res_body_${_cur_page}
    # リクエストURLにページ番号付与
    local _cur_request_url=""
    if [ "`echo ${_request_url} | grep "?"`" != "" ]; then
      # クエリストリングが含まれている場合
      _cur_request_url="${_request_url}&per_page=${GITLAB__REQ_PERPAGE}&page=${_cur_page}"
    else
      # クエリストリングが含まれてない場合
      _cur_request_url="${_request_url}?per_page=${GITLAB__REQ_PERPAGE}&page=${_cur_page}"
    fi

    log.debug_console "ページ: ${_cur_page}"
    log.add_indent

    # リクエスト実行
    if [ "${_is_form_param}" = "true" ]; then
      # フォームパラメータが指定されている場合
      log.debug_console "curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" ${_cur_request_url} -F \"${_form_param}\" -o ${_cur_path_res_body} --dump-header ${_cur_path_res_header} -w '%{http_code}'"
      log.add_indent
      local _cur_response_code=`curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_cur_request_url} -F "${_form_param}" -o ${_cur_path_res_body} --dump-header ${_cur_path_res_header} -w '%{http_code}'`
      local _cur_ret_code=$?
    else
      # フォームパラメータが指定されていない場合
      log.debug_console "curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" ${_cur_request_url} -o ${_cur_path_res_body} --dump-header ${_cur_path_res_header} -w '%{http_code}'"
      log.add_indent
      local _cur_response_code=`curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_cur_request_url} -o ${_cur_path_res_body} --dump-header ${_cur_path_res_header} -w '%{http_code}'`
      local _cur_ret_code=$?
    fi

    log.debug_console "response code: ${_cur_response_code}"
    log.debug_console "return code  : ${_cur_ret_code}"
    log.remove_indent

    # 実行結果チェック
    if [ `echo ${_cur_response_code} | cut -c 1` = "0" ]; then
      # 000系の場合、タイムアウト ※ リトライ
      log.warn_console "リクエスト実行がタイムアウトしました。リクエストURL:${_cur_request_url}、レスポンスコード：${_cur_response_code}、リターンコード：${_cur_ret_code}"
      log.add_indent

      local _retry_count=0
      while :; do
        # リトライ回数チェック
        if [ ${_retry_count} -ge ${GITLAB__MAX_RETRY_COUNT} ]; then
          # 最大リトライ回数の場合
          log.error_console "最大リトライ回数を超過しました。リトライ回数：${_retry_count}"
          rm -fr ${dir_work}                                                                         > /dev/null 2>&1
          log.remove_indent 3
          return ${EXITCODE_ERROR}
        fi

        log.debug_console "リトライ: `expr ${_retry_count} + 1`"
        log.add_indent

        # レスポンスファイル削除
        rm -f ${_cur_path_res_header}
        rm -f ${_cur_path_res_body}

        # リトライ間隔調整
        sleep ${GITLAB__RETRY_INTERVAL}

        # リトライ実施
        if [ "${_is_form_param}" = "true" ]; then
          # フォームパラメータが指定されている場合
          log.debug_console "[RETRY] curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" ${_cur_request_url} -F \"${_form_param}\" -o ${_cur_path_res_body} --dump-header ${_cur_path_res_header} -w '%{http_code}'"
          log.add_indent
          _cur_response_code=`curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_cur_request_url} -F "${_form_param}" -o ${_cur_path_res_body} --dump-header ${_cur_path_res_header} -w '%{http_code}'`
          _cur_ret_code=$?
        else
          # フォームパラメータが指定されていない場合
          log.debug_console "[RETRY] curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" ${_cur_request_url} -o ${_cur_path_res_body} --dump-header ${_cur_path_res_header} -w '%{http_code}'"
          log.add_indent
          _cur_response_code=`curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_cur_request_url} -o ${_cur_path_res_body} --dump-header ${_cur_path_res_header} -w '%{http_code}'`
          _cur_ret_code=$?
        fi

        log.debug_console "response code: ${_cur_response_code}"
        log.debug_console "return code  : ${_cur_ret_code}"
        log.remove_indent

        # 実行結果チェック
        if [ ${_cur_ret_code} -eq ${EXITCODE_SUCCESS} -a `echo ${_cur_response_code} | cut -c 1`"" = "2"  ]; then
          # 200系の場合、正常終了
          log.remove_indent
          break

        elif [ `echo ${_cur_response_code} | cut -c 1`"" = "0"  ]; then
          # 000系の場合、タイムアウト
          log.warn_console "リクエスト実行がタイムアウトしました。リクエストURL:${_request_url}、レスポンスコード：${_cur_response_code}、リターンコード：${_cur_ret_code}"

        else
          # 000、200系以外の場合、異常終了
          log.error_console "リクエスト実行でエラーが発生しました。レスポンスコード：${_cur_response_code}、リターンコード：${_cur_ret_code}"
          rm -fr ${dir_work}                                                                         > /dev/null 2>&1
          log.remove_indent 5
          return ${EXITCODE_ERROR}
        fi

        # リトライ回数カウントアップ
        _retry_count=$((${_retry_count} + 1))

        log.remove_indent
      done

      log.remove_indent

    elif [ ${_cur_ret_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_cur_response_code} | cut -c 1` != "2" ]; then
      # 000、200系以外の場合、異常終了
      log.error_console "リクエスト実行でエラーが発生しました。レスポンスコード：${_cur_response_code}、リターンコード：${_cur_ret_code}"
      rm -fr ${dir_work} > /dev/null 2>&1
      log.remove_indent 3
      return ${EXITCODE_ERROR}
    fi

    # ページ数カウントアップ
    _page_count=$(expr ${_page_count} + 1)

    # 次のページチェック
    local _next_page=`cat ${_cur_path_res_header} | grep "X-Next-Page" | ${DIR_BIN_LIB}/Tukubai/self 2`
    if [ "${_next_page}" != "" ]; then
      # 次ページが存在する場合
      log.remove_indent
      _cur_page=${_next_page}
    else
      # 次ページが存在しない場合
      log.remove_indent
      break
    fi
  done

  log.remove_indent

  # レスポンスファイルコピー
  if [ ${_page_count} -gt 1 ]; then
    # 2ページ以上存在する場合
    #------------------------------------------------
    # レスポンスファイル結合
    #------------------------------------------------
    log.debug_console "レスポンスファイル結合"
    log.add_indent

    local _path_res_body_all=${_dir_work}/res_body

    # 先頭に "[" を出力
    log.debug_console "echo \"[\" > ${_path_res_body_all}"
    echo  -n "["                                                                                       > ${_path_res_body_all}

    # レスポンスファイル分ループ
    for _cur_response in `find ${_dir_work} -type f -name res_body_* | sed "s|${_dir_work}/||g"  | sort -t '_' -k3n`; do
      # 先頭の "[" と 末尾の "]" を除外し、","を付与して出力
      log.debug_console "cat ${_dir_work}/${_cur_response} | sed -e 's|^\[||' | sed -e 's|\]$||g' | sed 's|$|,|g' >> ${_path_res_body_all}"
      cat ${_dir_work}/${_cur_response} | sed -e 's|^\[||' | sed -e 's|\]$||g' | sed 's|$|,|g'         >> ${_path_res_body_all}
    done

    # 末尾の "," を "]" に変換し改行を除去
    log.debug_console "mv ${_path_res_body_all} ${_path_res_body_all}.tmp"
    mv ${_path_res_body_all} ${_path_res_body_all}.tmp

    log.debug_console "cat ${_path_res_body_all}.tmp | sed '$s|,$|\]|g' | tr -d '\n' > ${_path_res_body_all}"
    cat ${_path_res_body_all}.tmp | sed '$s|,$|\]|g' | tr -d '\n'                                      > ${_path_res_body_all}

    log.debug_console "rm -f ${_path_res_body_all}.tmp"
    rm -f ${_path_res_body_all}.tmp

    # 結合したレスポンスファイルを指定のパスにコピー
    log.debug_console "cp -f ${_path_res_body_all} ${_path_response}"
    cp -f ${_path_res_body_all} ${_path_response}

    log.remove_indent
  else
    # 1ページのみの場合
    log.debug_console "cp -f ${_dir_work}/res_body_1 ${_path_response}"
    cp -f ${_dir_work}/res_body_1 ${_path_response}
  fi

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  rm -fr ${_dir_work}                                                                                > /dev/null 2>&1

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   （Util Private）GITLAB API の GET 以外の処理
#    ※ このFunctionを直接実行するのではなく gitlab.local.execute_api を実行して下さい。
#
# 前提
#   なし
#
# オプション
#   ・-f | --form PRAM
#     curl コマンド実行時に -F オプション指定して実行します。
#   ・-db | --data-binary DATA
#     curl コマンド実行時に --data-binary オプション指定して実行します。
#
# 引数
#   ・1: HTTPメソッド           ※ POST | PUT
#   ・2: リクエストURL
#   ・3: レスポンスファイルパス
#   ・4: フォームパラメータ     ※ 任意
#
# 出力
#   レスポンスファイル
#
#--------------------------------------------------------------------------------------------------
function gitlab.local.execute_api.other() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _is_form_param=false
  local _form_param=""
  local _is_data_binary=false
  local _data_binary=""
  local _USAGE="Usage: ${FUNCNAME[0]} [-f PARAM] HTTP_METHOD REQUEST_URL PATH_RESPONSE"

  # オプション解析
  while :; do
    case $1 in
      -f|--form)
        _is_form_param=true
        _form_param="$2"
        shift 2
        ;;
      -db | --data-binary)
        _is_data_binary=true
        _data_binary="$2"
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

  if [ "${_is_form_param}" = "true" -a "${_is_data_binary}" = "true" ]; then
    # -F と --data-bainary の両方が指定されている場合
    log.error_console "-f / --data-bainary オプションを同時に指定する事はできません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # HTTPメソッド
  local _http_method="$1"
  if [ "${_http_method}" != "POST" -a "${_http_method}" != "PUT" -a "${_http_method}" != "DELETE"  ]; then
    log.error_console "HTTPメソッドには POST / PUT / DELETE のどちらかを指定して下さい。HTTPメソッド：${_http_method}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # リクエストURL
  local _request_url="$2"

  # レスポンスファイルパス
  local _path_response="$3"
  if [ ! -d  `dirname ${_path_response}` ]; then
    mkdir -p `dirname ${_path_response}`
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  log.debug_console "リクエスト実行"
  log.add_indent

  # リクエスト実行
  if [ "${_is_form_param}" = "true" ]; then
    # -f が指定されている場合
    log.debug_console "curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" ${_request_url} -F \"${_form_param}\" -o ${_path_response} -w '%{http_code}'"
    log.add_indent
    local _cur_response_code=`curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_request_url} -F "${_form_param}" -o ${_path_response} -w '%{http_code}'`
    local _cur_ret_code=$?
  elif [ "${_is_data_binary}" = "true" ]; then
    # --data-binary が指定されている場合
    log.debug_console "curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" ${_request_url} --data-binary \"${_data_binary}\" -o ${_path_response} -w '%{http_code}'"
    log.add_indent
    local _cur_response_code=`curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_request_url} --data-binary "${_data_binary}" -o ${_path_response} -w '%{http_code}'`
    local _cur_ret_code=$?
  else
    # オプションの指定が無い場合
    log.debug_console "curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" ${_request_url} -o ${_path_response} -w '%{http_code}'"
    log.add_indent
    local _cur_response_code=`curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_request_url} -o ${_path_response} -w '%{http_code}'`
    local _cur_ret_code=$?
  fi

  log.debug_console "response code: ${_cur_response_code}"
  log.debug_console "return code  : ${_cur_ret_code}"
  log.remove_indent

  # 実行結果チェック
  if [ `echo ${_cur_response_code} | cut -c 1` = "0"  ]; then
    # 000系の場合、タイムアウト ※ リトライ
    log.warn_console "リクエスト実行がタイムアウトしました。リクエストURL:${_request_url}、レスポンスコード：${_cur_response_code}、リターンコード：${_cur_ret_code}"
    log.add_indent

    local _retry_count=0
    while :; do
      # リトライ回数チェック
      if [ ${_retry_count} -ge ${GITLAB__MAX_RETRY_COUNT} ]; then
        # 最大リトライ回数の場合
        log.error_console "最大リトライ回数を超過しました。リトライ回数：${_retry_count}"
        log.remove_indent 3
        return ${EXITCODE_ERROR}
      fi

      log.debug_console "リトライ: `expr ${_retry_count} + 1`"
      log.add_indent

      # レスポンスファイル削除
      rm -f ${_cur_path_res_header}
      rm -f ${_cur_path_res_body}

      # リトライ間隔調整
      sleep ${GITLAB__RETRY_INTERVAL}

      # リトライ実施
      if [ "${_is_form_param}" = "true" ]; then
        #  -f が指定されている場合
        log.debug_console "curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" ${_request_url} -F \"${_form_param}\" -o ${_path_response} -w '%{http_code}'"
        log.add_indent
        _cur_response_code=`curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_request_url} -F "${_form_param}" -o ${_path_response} -w '%{http_code}'`
        _cur_ret_code=$?
      elif [ "${_is_data_binary}" = "true" ]; then
        # --data-binary が指定されている場合
        log.debug_console "curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" ${_request_url} --data-binary \"${_data_binary}\" -o ${_path_response} -w '%{http_code}'"
        log.add_indent
        _cur_response_code=`curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_request_url} --data-binary "${_data_binary}" -o ${_path_response} -w '%{http_code}'`
        _cur_ret_code=$?
      else
        # オプションの指定が無い場合
        log.debug_console "curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" ${_request_url} -o ${_path_response} -w '%{http_code}'"
        log.add_indent
        _cur_response_code=`curl -s -m ${GITLAB__TIMEOUT_SEC} -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_request_url} -o ${_path_response} -w '%{http_code}'`
        _cur_ret_code=$?
      fi

      log.debug_console "response code: ${_cur_response_code}"
      log.debug_console "return code  : ${_cur_ret_code}"
      log.remove_indent

      # 実行結果チェック
      if [ ${_cur_ret_code} -eq ${EXITCODE_SUCCESS} -a `echo ${_cur_response_code} | cut -c 1` = "2"  ]; then
        # 200系の場合、正常終了
        log.remove_indent
        break

      elif [ `echo ${_cur_response_code} | cut -c 1` = "0"  ]; then
        # 000系の場合、タイムアウト
        log.warn_console "リクエスト実行がタイムアウトしました。リクエストURL:${_cur_request_url}、レスポンスコード：${_cur_response_code}、リターンコード：${_cur_ret_code}"

      else
        # 000、200系以外の場合、異常終了
        log.error_console "リクエスト実行でエラーが発生しました。レスポンスコード：${_cur_response_code}、リターンコード：${_cur_ret_code}"
        log.remove_indent 4
        return ${EXITCODE_ERROR}
      fi

      # リトライ回数カウントアップ
      _retry_count=$((${_retry_count} + 1))

      log.remove_indent
    done

    log.remove_indent

  elif [ ${_cur_ret_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_cur_response_code} | cut -c 1` != "2" ]; then
    # 000、200系以外の場合、異常終了
    log.error_console "リクエスト実行でエラーが発生しました。レスポンスコード：${_cur_response_code}、リターンコード：${_cur_ret_code}"
    log.remove_indent 2
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
#   （Util Private）APIアクセス向けのGitLabでのプロジェクトID取得処理
#
# 前提
#   なし
#
# 引数
#   ・1: GitLabグループ名 ※グループが存在しない場合、""で指定。
#   ・2: GitLabプロジェクト名
#
# 出力
#   標準出力
#
#--------------------------------------------------------------------------------------------------
function gitlab.local.get_project_id() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_log "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT"

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # HTTPメソッド
  local _http_method="GET"

  # プロジェクト情報取得エンドポイントURL
  local readonly _url="${GITLAB_URL}/api/v3/projects"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  gitlab.local.execute_api "${_http_method}" "${_url}" "${_path_response}"                         > /dev/null 2>&1
  local _cur_return_code=$?

  # path_with_namespace の組み立て
  if [ "${_group}" = "" ]; then
    local _path_with_namespace="${_project}"
  else
    local _path_with_namespace="${_group}/${_project}"
  fi
  log.debug_log "path_with_namespace: ${_path_with_namespace}"

  # プロジェクトID抽出
  log.debug_log "cat ${_path_response} | ${DIR_BIN_LIB}/jq '.[] | select(.path_with_namespace == \"${_path_with_namespace}\") | .id'"
  local _project_id=`cat ${_path_response} | ${DIR_BIN_LIB}/jq '.[] | select(.path_with_namespace == "'${_path_with_namespace}'") | .id'`

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # プロジェクトIDを表示
  log.add_indent
  log.debug_log "project_id: ${_project_id}"
  log.remove_indent
  echo "${_project_id}"

  # レスポンスコードを確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # エラー終了
    log.remove_indent
    return ${EXITCODE_ERROR}

  else
    # 一時ファイル削除
    rm -f ${_path_response} > /dev/null 2>&1

    log.remove_indent
    return ${EXITCODE_SUCCESS}
  fi

}


#--------------------------------------------------------------------------------------------------
# 概要
#   protectブランチか否かを確認します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: 対象ブランチ
#
# 標準出力
#   なし
#
# 戻り値
#   0: protectedブランチの場合
#   3: protectedブランチでない場合
#   6: 確認に失敗した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.is_protected_branch() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TARGET_BRANCH"

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # 対象ブランチ名
  local _branch="$3"

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id ${_group} ${_project}`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、対象ブランチ：${_branch}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="GET"

  # protect実行エンドポイントURL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/repository/branches/${_branch}"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  gitlab.local.execute_api "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 結果取得
  log.debug_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_console
  log.remove_indent

  log.debug_console "cat ${_path_response} | ${DIR_BIN_LIB}/jq . | ${DIR_BIN_LIB}/Parsrs/parsrj.sh | grep \"protected\" | ${DIR_BIN_LIB}/Tukubai/self 2"
  log.add_indent
  local _is_protected=`cat ${_path_response} | ${DIR_BIN_LIB}/jq . | ${DIR_BIN_LIB}/Parsrs/parsrj.sh | grep "protected" | ${DIR_BIN_LIB}/Tukubai/self 2`
  log.debug_console "is_protected : ${_is_protected}"
  log.remove_indent

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 結果を確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS}  ]; then
    # エラー終了
    log.error_console "ブランチ情報の取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、対象ブランチ：${_branch}、is_protected：${_is_protected}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}

  else
    # 一時ファイル削除
    rm -f ${_path_response} > /dev/null 2>&1

    log.remove_indent
    if [ "${_is_protected}" = "true" ]; then
      return ${EXITCODE_SUCCESS}
    elif [ "${_is_protected}" = "false" ]; then
      return ${EXITCODE_WARN}
    else
      return ${EXITCODE_ERROR}
    fi
  fi

}


#--------------------------------------------------------------------------------------------------
# 概要
#   ブランチをprotectにします。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: 対象ブランチ
#
# 標準出力
#   なし
#
# 戻り値
#   0: protectに成功した場合
#   6: protectに失敗した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.protect_branch() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TARGET_BRANCH"

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # 対象ブランチ名
  local _branch="$3"

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id ${_group} ${_project}`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、対象ブランチ：${_branch}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="PUT"

  # protect実行エンドポイントURL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/repository/branches/${_branch}/protect"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  gitlab.local.execute_api "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 結果取得
  log.debug_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_console
  log.remove_indent

  log.debug_console "cat ${_path_response} | ${DIR_BIN_LIB}/jq . | ${DIR_BIN_LIB}/Parsrs/parsrj.sh | grep \"protected\" | ${DIR_BIN_LIB}/Tukubai/self 2"
  log.add_indent
  local _is_protected=`cat ${_path_response} | ${DIR_BIN_LIB}/jq . | ${DIR_BIN_LIB}/Parsrs/parsrj.sh | grep "protected" | ${DIR_BIN_LIB}/Tukubai/self 2`
  log.debug_console "is_protected : ${_is_protected}"
  log.remove_indent

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 結果を確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_is_protected}`"" != "true" ]; then
    # エラー終了
    log.error_console "ブランチのprotectでエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、対象ブランチ：${_branch}、is_protected：${_is_protected}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}

  else
    # 一時ファイル削除
    rm -f ${_path_response} > /dev/null 2>&1

    log.remove_indent
    return ${EXITCODE_SUCCESS}
  fi

}


#--------------------------------------------------------------------------------------------------
# 概要
#   ブランチをunprotectにします。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: 対象ブランチ
#
# 標準出力
#   なし
#
# 戻り値
#   0: unprotectに成功した場合
#   6: unprotectに失敗した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.unprotect_branch() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TARGET_BRANCH"

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # 対象ブランチ名
  local _branch="$3"

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id ${_group} ${_project}`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、対象ブランチ：${_branch}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="PUT"

  # protect実行エンドポイントURL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/repository/branches/${_branch}/unprotect"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  gitlab.local.execute_api "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 結果取得
  log.debug_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_console
  log.remove_indent

  log.debug_console "cat ${_path_response} | ${DIR_BIN_LIB}/jq . | ${DIR_BIN_LIB}/Parsrs/parsrj.sh | grep \"protected\" | ${DIR_BIN_LIB}/Tukubai/self 2"
  log.add_indent
  local _is_protected=`cat ${_path_response} | ${DIR_BIN_LIB}/jq . | ${DIR_BIN_LIB}/Parsrs/parsrj.sh | grep "protected" | ${DIR_BIN_LIB}/Tukubai/self 2`
  log.debug_console "is_protected : ${_is_protected}"
  log.remove_indent

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 結果を確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_is_protected}`"" != "false" ]; then
    # エラー終了
    log.error_console "ブランチのunprotectでエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、対象ブランチ：${_branch}、is_protected：${_is_protected}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}

  else
    # 一時ファイル削除
    rm -f ${_path_response} > /dev/null 2>&1

    log.remove_indent
    return ${EXITCODE_SUCCESS}
  fi

}


#--------------------------------------------------------------------------------------------------
# 概要
#   プロジェクトに存在するマージリクエストを全て取得します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: 出力先パス
#
# 標準出力
#   なし
#
# 戻り値
#   0: 異常終了した場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.get_merge_request() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT PATH_OUT"

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # 出力先パス
  local _path_out="$3"
  if [ ! -d `dirname ${_path_out}` ]; then
    mkdir -p `dirname ${_path_out}`
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="GET"

  # マージリクエスト取得URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/merge_requests"

  # 一時ファイルパス
  local _path_response="${_path_out}"

  # リクエスト実行
  gitlab.local.execute_api "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 取得結果出力
  log.debug_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_console
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "マージリクエストの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  log.remove_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   プロジェクトに指定のマージリクエストが存在するかチェックします。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# オプション
#   --status-only:
#     ステータスのみを対象に存在チェックする場合に指定します。
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: ターゲットブランチ(マージ先ブランチ) ※ --status-only の場合は指定なし
#   ・4: ステータス                           ※ opened / merged / closed / reopened
#
# 標準出力
#   なし
#
# 戻り値
#   0: マージリクエストが存在する場合
#   3: マージリクエストが存在しない場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.is_exist_merge_request() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  local _is_status_only=false
  local _USAGE="Usage: ${FUNCNAME[0]} [--status-only] GITLAB_GROUP GITLAB_PROJECT [TAGET_BRANCH] STATUS"

  # オプション解析
  while :; do
    case $1 in
      --status-only)
        _is_status_only=true
        shift
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
  if [ $# -lt 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # ターゲットブランチ
  local _target_branch=""
  if [ "${_is_status_only}" != "true" ]; then
    # 通常モードの場合
    _target_branch="$3"
    shift
  fi
  # ステータス
  local _status="$3"


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト取得
  gitlab.get_merge_request "${_group}" "${_project}" "${_path_response}"
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    log.remove_indent
    return ${_ret_code}
  fi

  # jsonのリスト数取得
  local _list_count=`cat ${_path_response} | ${DIR_BIN_LIB}/jq length`

  # マージリクエスト分ループ
  local _is_exist=false
  if [ ${_list_count} -gt 0 ]; then
    for _cur_index in `seq 0 $(expr ${_list_count} - 1)`; do
      # ターゲットブランチ
      local _cur_target_branch=$(cat ${_path_response} | ${DIR_BIN_LIB}/jq .[${_cur_index}].target_branch | sed "s|^\"||g" | sed "s|\"$||g")
      # ステータス
      local _cur_status=$(cat ${_path_response} | ${DIR_BIN_LIB}/jq .[${_cur_index}].state | sed "s|^\"||g" | sed "s|\"$||g")

      # 判定
      if [ "${_is_status_only}" != "true" ]; then
        # 通常 モードの場合
        if [ "${_cur_target_branch}" = "${_target_branch}" -a "${_cur_status}" = "${_status}" ]; then
          # 指定のターゲットブランチ・ステータスと一致する場合
          _is_exist=true
          break
        fi
      else
        # --satatus-only モードの場合
        if [ "${_cur_status}" = "${_status}" ]; then
          # 指定のステータスと一致する場合
          _is_exist=true
          break
        fi
      fi
    done
  fi

  if [ "${_is_exist}" = "true" ]; then
    # 存在する場合
    _ret_code=${EXITCODE_SUCCESS}
  else
    # 存在しない場合
    _ret_code=${EXITCODE_WARN}
  fi

  # 判定結果出力
  echo "${_is_exist}"


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response} > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   プロジェクトにマージリクエストを作成します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: ソースブランチ       ※ マージ元ブランチ
#   ・4: ターゲットブランチ   ※ マージ先ブランチ
#   ・5: タイトル
#   ・6: アサイニーID
#   ・7: 出力先パス           ※ 任意
#
# オプション
#   ・ -d | --description PATH_FILE
#     description を設定する場合に指定します。
#     設定内容が記載されているファイパスを指定して下さい。
#     指定しない場合のデフォルトは null が設定されます。
#
#   ・-l | --labels VALUE
#     labels を設定する場合に指定します。
#     指定しない場合のデフォルトは null が設定されます。
#
#   ・-mi | --milestone_id VALUE
#     milestone_id を設定する場合に指定します。
#     指定しない場合のデフォルトは null が設定されます。
#
#   ・-rsb | --remove_source_branch VALUE
#     remove_reousrce_branch を設定する場合に指定します。
#     true / false のどちらかを指定して下さい。
#     指定しない場合のデフォルトは true (マージ時に削除) が設定されます。
#
# 標準出力
#   なし
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.create_merge_request() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _path_description=""
  local _labels=""
  local _milestone_id=""
  local _remove_source_branch=""
  local _USAGE="Usage: ${FUNCNAME[0]} [OPTIONS] GITLAB_GROUP GITLAB_PROJECT SOURCE_BRANCH TARGET_BRANCH TITLE ASSINGEE_ID [PATH_OUT]"

  # オプション解析
  while :; do
    case $1 in
      -d|--description)
        if [ -n "${_path_description}" ]; then
          log.error_console "-d | --description が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _path_description="$2"
        if [ ! -f ${_path_description} ]; then
          log.error_console "-d | --description の指定ファイルが存在していません。パス：${_path_description}"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        shift 2
        ;;
      -l|--labels)
        if [ -n "${_labels}" ]; then
          log.error_console "-l | --labels が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _labels="$2"
        shift 2
        ;;
      -mi|--milestone_id)
        if [ -n "${_milestone_id}" ]; then
          log.error_console "-mi | --milestone_id が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _milestone_id="$2"
        shift 2
        ;;
      -rsb|--remove_source_branch)
        if [ -n "${_remove_source_branch}" ]; then
          log.error_console "-rsb | --remove_source_branch が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _remove_source_branch="$2"
        if [ "${_remove_source_branch}" != "true" -a "${_remove_source_branch}" != "false" ]; then
          log.error_console "-rsb|--remove_source_branch は true / false のみ指定可能です。remove_source_branch：${_remove_source_branch}"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
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
  if [ $# -lt 6 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # ソースブランチ
  local _source_branch="$3"
  # ターゲットブランチ
  local _target_branch="$4"
  # タイトル
  local _title="$5"
  # アサイニーID
  local _assignee_id="$6"
  if [ "`echo ${_assignee_id} | sed -e "s|[0-9]||g"`" != "" ]; then
    log.error_console "assignee_id は数値のみ指定可能です。assignee_id：${_assignee_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  # 出力先パス
  local _path_out=""
  if [ $# -ge 7 ]; then
    # 出力先パスが指定されている場合
    _path_out="$7"
    if [ ! -d `dirname ${_path_out}` ]; then
      mkdir -p `dirname ${_path_out}`
    fi
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="POST"

  # マージリクエスト取得URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/merge_requests"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_response_$$"

  # データ作成
  local _path_data="/tmp/${FUNCNAME[0]}_data_$$"
  local _data_content=""

  # sourve_branch
  _data_content="source_branch=`echo "${_source_branch}" | _urlencode`"

  # target_branch
  _data_content="${_data_content}&target_branch=`echo "${_target_branch}" | _urlencode`"

  # title
  _data_content="${_data_content}&title=`echo "${_title}" | _urlencode`"

  # assignee_id
  _data_content="${_data_content}&assignee_id=`echo "${_assignee_id}" | _urlencode`"

  # description
  if [ -n "${_path_description}" ]; then
    # 指定されている場合
    local _description=`cat ${_path_description}`
    _data_content="${_data_content}&description=`echo "${_description}" | _urlencode`"
  fi

  # labels
  if [ -n "${_labels}" ]; then
    # 指定されている場合
    _data_content="${_data_content}&labels=`echo "${_labels}" | _urlencode`"
  fi

  # milestone_id
  if [ -n "${_milestone_id}" ]; then
    # 指定されている場合
    _data_content="${_data_content}&milestone_id=`echo "${_milestone_id}" | _urlencode`"
  fi

  # remove_source_branch
  if [ -n "${_remove_source_branch}" ]; then
    # 指定されている場合
    _data_content="${_data_content}&remove_source_branch=`echo "${_remove_source_branch}" | _urlencode`"
  else
    # 指定されていない場合
    _data_content="${_data_content}&remove_source_branch=`echo 'true' | _urlencode`"
  fi

  # 一時ファイルに出力
  echo -n "${_data_content}"                                                                       > ${_path_data}

  # リクエスト実行
  gitlab.local.execute_api --data-binary "@${_path_data}" "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 実行結果出力
  log.debug_log "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_log
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "マージリクエスト作成でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、レスポンスファイル：${_path_response}、データファイル：${_path_data}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # レスポンスファイルをコピー
  if [ -n "${_path_out}" ]; then
    cp -f ${_path_response} ${_path_out} > /dev/null 2>&1
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response} > /dev/null 2>&1
  rm -f ${_path_data}     > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   プロジェクトのマージリクエストを更新します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: マージリクエストID
#   ・4: 出力先パス           ※ 任意
#
# オプション
#   ・-tb | --target_branch VALUE
#     target_branch を更新する場合に指定します。
#
#   ・-t | --title VALUE
#     title を更新する場合に指定します。
#
#   ・-ai | --assignee_id VALUE
#     assignee_id を更新する場合に指定します。
#     assignee_id の指定を解除する場合は "" を指定して下さい。
#
#   ・-d | --description PATH_FILE
#     description を更新する場合に指定します。
#     設定内容が記載されているファイパスを指定して下さい。
#
#   ・-se | --state_event VALUE
#     state_event を更新する場合に指定します。
#
#   ・-l | --labels VALUE
#     labels を更新する場合に指定します。
#
#   ・-mi | --milestone_id VALUE
#     milestone_id を更新する場合に指定します。
#     milestone_id の指定を解除する場合は "" を指定して下さい。
#
#   ・-rsb | --remove_source_branch VALUE
#     remove_reousrce_branch を更新する場合に指定します。
#     true / false のどちらかを指定して下さい。
#
# 標準出力
#   なし
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.update_merge_request() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _count_option=0
  local _target_branch=""
  local _title=""
  local _is_exist_assignee_id=false
  local _assignee_id=""
  local _path_description=""
  local _state_event=""
  local _labels=""
  local _is_exist_labels=false
  local _milestone_id=""
  local _is_exist_milestone_id=false
  local _remove_source_branch=""
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT MERGE_REQUEST_ID [PATH_OUT]"

  # オプション解析
  while :; do
    case $1 in
      -tb|--target_branch)
        if [ -n "${_target_branch}" ]; then
          log.error_console "-tb | --target_branch が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _target_branch="$2"
        _count_option=$(expr ${_count_option} + 1)
        shift 2
        ;;
      -t|--title)
        if [ -n "${_title}" ]; then
          log.error_console "-t | --title が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _title="$2"
        _count_option=$(expr ${_count_option} + 1)
        shift 2
        ;;
      -ai|--assignee_id)
        if [ "${_is_exist_assignee_id}" = "true" ]; then
          log.error_console "-ai | --assignee_id が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _assignee_id="$2"
        _is_exist_assignee_id=true
        _count_option=$(expr ${_count_option} + 1)
        shift 2
        ;;
      -d|--description)
        if [ -n "${_path_description}" ]; then
          log.error_console "-d | --description が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _path_description="$2"
        if [ ! -f ${_path_description} ]; then
          log.error_console "--descriotion で指定のファイルが存在していません。パス：${_path_description}"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _count_option=$(expr ${_count_option} + 1)
        shift 2
        ;;
      -se|--state_event)
        if [ -n "${_state_event}" ]; then
          log.error_console "-se | --state_event が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _state_event="$2"
        if [ "${_state_event}" != "close" -a "${_state_event}" != "reopen" ]; then
          log.error_console "-se | --state_event は close / reopen のみ指定可能です。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _count_option=$(expr ${_count_option} + 1)
        shift 2
        ;;
      -l|--labels)
        if [ "${_is_exist_labels}" = "true" ]; then
          log.error_console "-l | --labels が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _labels="$2"
        _is_exist_labels=true
        _count_option=$(expr ${_count_option} + 1)
        shift 2
        ;;
      -mi|--milestone_id)
        if [ "${_is_exist_milestone_id}" = "true" ]; then
          log.error_console "-mi | --milestone_id が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _milestone_id="$2"
        _is_exist_milestone_id=true
        _count_option=$(expr ${_count_option} + 1)
        shift 2
        ;;
      -rsb|--remove_source_branch)
        if [ -n "${_remove_source_branch}" ]; then
          log.error_console "-rsb | --remove_source_branch が複数回指定されています。"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _remove_source_branch="$2"
        if [ "${_remove_source_branch}" != "true" -a "${_remove_source_branch}" != "false" ]; then
          log.error_console "-rsb|--remove_source_branch は true / false のみ指定可能です。remove_source_branch：${_remove_source_branch}"
          log.remove_indent
          return ${EXITCODE_ERROR}
        fi
        _count_option=$(expr ${_count_option} + 1)
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

  if [ ${_count_option} -eq 0 ]; then
    # 更新項目が存在しない場合
    log.error_console "更新項目が1つも設定されていません。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 引数の数
  if [ $# -lt 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # マージリクエストID
  local _merge_request_id="$3"
  # 出力先パス
  local _path_out=""
  if [ $# -ge 4 ]; then
    # 出力先パスが指定されている場合
    _path_out="$4"
    if [ ! -d `dirname ${_path_out}` ]; then
      mkdir -p `dirname ${_path_out}`
    fi
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="PUT"

  # マージリクエスト取得URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/merge_requests/${_merge_request_id}"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # データ作成
  local _path_data="/tmp/${FUNCNAME[0]}_data_$$"
  local _data_content=""

  # target_branch
  if [ -n "${_target_branch}" ]; then
    # 指定されている場合
    _data_content="${_data_content}&target_branch=` echo "${_target_branch}" | _urlencode`"
  fi

  # title
  if [ -n "${_title}" ]; then
    # 指定されている場合
    _data_content="${_data_content}&title=`echo "${_title}" | _urlencode`"
  fi

  # assignee_id
  if [ "${_is_exist_assignee_id}" = "true" ]; then
    # 指定されている場合
    _data_content="${_data_content}&assignee_id=`echo "${_assignee_id}" | _urlencode`"
  fi

  # description
  if [ -n "${_path_description}" ]; then
    # 指定されている場合
    local _description=`cat ${_path_description}`
    _data_content="${_data_content}&description=`echo "${_description}" | _urlencode`"
  fi

  # state_event
  if [ -n "${_state_event}" ]; then
    # 指定されている場合
    _data_content="${_data_content}&state_event=`echo "${_state_event}" | _urlencode`"
  fi

  # labels
  if [ "${_is_exist_labels}" = "true" ]; then
    # 指定されている場合
    _data_content="${_data_content}&labels=`echo "${_labels}" | _urlencode`"
  fi

  # milestone_id
  if [ "${_is_exist_milestone_id}" = "true" ]; then
    # 指定されている場合
    _data_content="${_data_content}&milestone_id=`echo "${_milestone_id}" | _urlencode`"
  fi

  # remove_source_branch
  if [ -n "${_remove_source_branch}" ]; then
    # 指定されている場合
    _data_content="${_data_content}&remove_source_branch=`echo "${_remove_source_branch}" | _urlencode`"
  fi

  # 先頭の&を削除
  _data_content=`echo "${_data_content}" | sed "s|^\&||g"`

  # 一時ファイルに出力
  echo -n "${_data_content}"                                                                       > ${_path_data}

  # リクエスト実行
  gitlab.local.execute_api --data-binary "@${_path_data}" "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 取得結果出力
  log.debug_log "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_log
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "マージリクエスト更新でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、マージリクエストID:${_merge_request_id}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # レスポンスファイルをコピー
  if [ -n "${_path_out}" ]; then
    cp -f ${_path_response} ${_path_out} > /dev/null 2>&1
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response} > /dev/null 2>&1
  rm -f ${_path_data}     > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   プロジェクトのマージリクエストを削除します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限(admin もしくは owners)が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: マージリクエストID
#   ・4: 出力先パス ※ 任意
#
# 標準出力
#   なし
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.delete_merge_request() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT MERGE_REQUEST_ID [PATH_OUT]"

  # 引数の数
  if [ $# -lt 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # マージリクエストID
  local _merge_request_id="$3"
  # 出力先パス
  local _path_out=""
  if [ $# -ge 4 ]; then
    # 出力先パスが指定されている場合
    _path_out="$4"
    if [ ! -d `dirname ${_path_out}` ]; then
      mkdir -p `dirname ${_path_out}`
    fi
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="DELETE"

  # マージリクエスト削除URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/merge_requests/${_merge_request_id}"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  gitlab.local.execute_api "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 取得結果出力
  log.debug_log "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_log
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "マージリクエスト削除でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、マージリクエストID:${_merge_request_id}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # レスポンスファイルをコピー
  if [ -n "${_path_out}" ]; then
    cp -f ${_path_response} ${_path_out} > /dev/null 2>&1
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response} > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   マージリクエストに存在するコメントを全て取得します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: マージリクエストID
#   ・4: 出力先パス
#
# 標準出力
#   なし
#
# 戻り値
#   0: 異常終了した場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.get_merge_request_comment() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT MERGE_REQUEST_ID PATH_OUT"

  # 引数の数
  if [ $# -ne 4 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # マージリクエストID
  local _merge_request_id="$3"
  # 出力先パス
  local _path_out="$4"
  if [ ! -d `dirname ${_path_out}` ]; then
    mkdir -p `dirname ${_path_out}`
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="GET"

  # マージリクエスト取得URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/merge_requests/${_merge_request_id}/notes"

  # 一時ファイルパス
  local _path_response="${_path_out}"

  # リクエスト実行
  gitlab.local.execute_api "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 取得結果出力
  log.debug_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_console
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "マージリクエストコメントの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、マージリクエストID；${_merge_request_id}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  log.remove_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   マージリクエストにコメントを追加します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: マージリクエストID
#   ・4: コメント
#   ・5: 出力先パス           ※ 任意
#
# 標準出力
#   なし
#
# 戻り値
#   0: 異常終了した場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.create_merge_request_comment() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT MERGE_REQUEST_ID COMMENT [PATH_OUT]"

  # 引数の数
  if [ $# -lt 4 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # マージリクエストID
  local _merge_request_id="$3"
  # コメント
  local _comment="$4"
  # 出力先パス
  local _path_out=""
  if [ $# -ge 5 ]; then
    # 出力先パスが指定されている場合
    _path_out="$5"
    if [ ! -d `dirname ${_path_out}` ]; then
      mkdir -p `dirname ${_path_out}`
    fi
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="POST"

  # マージリクエスト追加URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/merge_requests/${_merge_request_id}/notes"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # コメントをURLエンコード
  local _path_data="/tmp/${FUNCNAME[0]}_data_$$"
  echo "body=`echo "${_comment}" | _urlencode`"                                                    > ${_path_data}

  # リクエスト実行
  gitlab.local.execute_api --data-binary "@${_path_data}" "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 取得結果出力
  log.debug_log "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_log
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "マージリクエストコメントの作成でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、マージリクエストID；${_merge_request_id}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # レスポンスファイルをコピー
  if [ -n "${_path_out}" ]; then
    cp -f ${_path_response} ${_path_out} > /dev/null 2>&1
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response} > /dev/null 2>&1
  rm -f ${_path_data}     > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   マージリクエストのコメントを更新します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: マージリクエストID
#   ・4: コメントID
#   ・5: コメント
#   ・6: 出力先パス ※ 任意
#
# 標準出力
#   なし
#
# 戻り値
#   0: 異常終了した場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.update_merge_request_comment() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT MERGE_REQUEST_ID COMMENT_ID COMMENT [PATH_OUT]"

  # 引数の数
  if [ $# -lt 5 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # マージリクエストID
  local _merge_request_id="$3"
  # コメントID
  local _comment_id="$4"
  # コメント
  local _comment="$5"
  # 出力先パス
  local _path_out=""
  if [ $# -ge 6 ]; then
    # 出力先パスが指定されている場合
    _path_out="$6"
    if [ ! -d `dirname ${_path_out}` ]; then
      mkdir -p `dirname ${_path_out}`
    fi
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="PUT"

  # マージリクエスト取得URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/merge_requests/${_merge_request_id}/notes/${_comment_id}"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # コメントをURLエンコード
  local _path_data="/tmp/${FUNCNAME[0]}_data_$$"
  echo "body=`echo "${_comment}" | _urlencode`"                                                    > ${_path_data}

  # リクエスト実行
  gitlab.local.execute_api --data-binary "@${_path_data}" "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 取得結果出力
  log.debug_log "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_log
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "マージリクエストコメントの作成でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、マージリクエストID；${_merge_request_id}、コメントID：${_comment_id}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # レスポンスファイルをコピー
  if [ -n "${_path_out}" ]; then
    cp -f ${_path_response} ${_path_out} > /dev/null 2>&1
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response} > /dev/null 2>&1
  rm -f ${_path_data}     > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   マージリクエストのコメントを削除します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: マージリクエストID
#   ・4: コメントID
#   ・5: 出力先パス ※ 任意
#
# 標準出力
#   なし
#
# 戻り値
#   0: 異常終了した場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.delete_merge_request_comment() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT MERGE_REQUEST_ID COMMENT_ID COMMENT [PATH_OUT]"

  # 引数の数
  if [ $# -lt 4 ]; then
    log.error_console "Usage${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # マージリクエストID
  local _merge_request_id="$3"
  # コメントID
  local _comment_id="$4"
  # 出力先パス
  local _path_out=""
  if [ $# -ge 5 ]; then
    # 出力先パスが指定されている場合
    _path_out="$5"
    if [ ! -d `dirname ${_path_out}` ]; then
      mkdir -p `dirname ${_path_out}`
    fi
  fi

  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="DELETE"

  # マージリクエスト取得URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/merge_requests/${_merge_request_id}/notes/${_comment_id}"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  gitlab.local.execute_api "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 取得結果出力
  log.debug_log "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_log
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "マージリクエストコメントの作成でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、マージリクエストID；${_merge_request_id}、コメントID：${_comment_id}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # レスポンスファイルをコピー
  if [ -n "${_path_out}" ]; then
    cp -f ${_path_response} ${_path_out} > /dev/null 2>&1
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response} > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   プロジェクトにファイルをアップロードします。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: アップロードファイルパス
#   ・4: レスポンス出力先ファイルパス
#
# 標準出力
#   api標準出力
#
#   ※ api標準出力形式
#   {"alt":"ファイル名","url":"upload先参照URL","is_image":"true / false","markdown":"markdown書式での参照記述"}
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.upload_file() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT PATH_UPLOAD_FILE PATH_OUTPUT_RESPONSE"

  # 引数の数
  if [ $# -ne 4 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"

  # プロジェクト名
  local _project="$2"

  # アップロードファイルパス
  local _path_upload_file="$3"
  if [ ! -f ${_path_upload_file} ] ; then
    log.error_console "アップロードファイルパスにファイルが存在しません。アップロードファイルパス：${_path_upload_file}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # レスポンス出力先ファイルパス
  local _path_output_response="$4"
  if [ ! -d `dirname ${_path_output_response}` ]; then
    mkdir -p `dirname ${_path_output_response}`
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="POST"

  # リクエスト実行URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/uploads"

  # フォームパラメータ
  local _form_param="file=@${_path_upload_file}"

  # リクエスト実行
  gitlab.local.execute_api -f "${_form_param}" "${_http_method}" "${_url}" "${_path_output_response}"
  local _cur_return_code=$?

  # 取得結果出力
  log.debug_console "${_path_output_response}:"
  log.add_indent
  cat ${_path_output_response}                                                                            |
  log.debug_console
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "ファイルのアップロードでエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、レスポンスファイル：${_path_response}"
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
#   タグにリリースノートが存在するかチェックします。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: タグ
#
# 標準出力
#   なし
#
# 戻り値
#   0: 存在する場合
#   3: 存在しない場合
#   6: 確認に失敗した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.is_exist_tag_release() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TAG"

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"

  # プロジェクト名
  local _project="$2"

  # タグ
  local _tag="$3"


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、対象ブランチ：${_branch}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="GET"

  # タグ一覧取得エンドポイントURL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/repository/tags"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  gitlab.local.execute_api "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 結果取得
  log.debug_console "cat ${_path_response} | ${DIR_BIN_LIB}/jq '.[] | select(.name == \"${_tag}\") | .release'"
  log.add_indent
  local _release=`cat ${_path_response} | ${DIR_BIN_LIB}/jq '.[] | select(.name == "'${_tag}'") | .release'`
  log.debug_console "release : ${_release}"
  log.remove_indent


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 結果を確認
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_release}" = "" ]; then
    # エラー終了
    log.error_console "タグ情報の取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、対象タグ：${_tag}、release：${_release}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}

  else
    # 一時ファイル削除
    rm -f ${_path_response}                                                                        > /dev/null 2>&1

    log.remove_indent
    if [ "${_release}" != "null" ]; then
      # 存在する場合
      return ${EXITCODE_SUCCESS}
    else
      # 存在しない場合
      return ${EXITCODE_WARN}
    fi
  fi

}


#--------------------------------------------------------------------------------------------------
# 概要
#   タグのリリースノートを更新します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: タグ
#   ・4: 説明ファイルパス     ※ ファイルの記載内容がリリースノートの説明に反映されます。
#
# 標準出力
#   なし
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.update_tag_release() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TAG PATH_DESCRIPTION_FILE"

  # 引数の数
  if [ $# -ne 4 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"

  # プロジェクト名
  local _project="$2"

  # タグ
  local _tag="$3"

  # 説明ファイルパス
  local _path_description="$4"
  if [ ! -f "${_path_description}" ]; then
    log.error_console "説明ファイルが存在しません。説明ファイルパス：${_path_description}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # リリースノートの存在チェック
  gitlab.is_exist_tag_release "${_group}" "${_project}" "${_tag}"
  _cur_return_code=$?
  if [ ${_cur_return_code} -eq ${EXITCODE_SUCCESS} ]; then
    # 正常終了の場合 (更新)
    local _http_method="PUT"
  elif [ ${_cur_return_code} -eq ${EXITCODE_WARN} ]; then
    # 警告終了の場合（新規追加）
    local _http_method="POST"
  else
   # 異常終了の場合
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # リクエスト実行URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/repository/tags/${_tag}/release"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # フォームパラメータ
  local _form_param="description=<${_path_description}"

  # リクエスト実行
  gitlab.local.execute_api -f "${_form_param}" "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 取得結果出力
  log.debug_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_console
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "リリースノートの編集でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、対象タグ；${_tag}、レスポンスファイル：${_path_response}"
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
#   タグに配布アーカイブを添付します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1  : GitLabグループ名
#   ・2  : GitLabプロジェクト名
#   ・3  : タグ
#   ・4～: 添付ファイルパスリスト
#
# 標準出力
#   なし
#
# 戻り値
#   0: 正常終了の場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.attachment_archive() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TAG PATH_TARGET_FILE1 [PATH_TARGET_FILE2 ...]"

  # 引数の数
  if [ $# -lt 4 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"

  # プロジェクト名
  local _project="$2"

  # タグ
  local _tag="$3"

  # 作業ディレクトリ
  local _dir_work=/tmp/${FUNCNAME[0]}_$$
  mkdir -p ${_dir_work}

  # リリースノートの説明
  local _path_description=${_dir_work}/description


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  log.debug_console "ファイルアップロード"
  log.add_indent

  # 添付ファイルリストへシフト
  shift 3

  # 添付ファイルリスト分ループ
  local _count_upload_file=1
  while [ $# -gt 0 ]; do
    # 添付ファイルパス
    local _cur_path_attachment_file=$1
    # 添付ファイル名
    local _cur_attachment_filename=`basename ${_cur_path_attachment_file}`
    # ファイルアップロードのレスポンスファイルパス
    local _cur_path_upload_response=${_dir_work}/response_${_count_upload_file}_${_cur_attachment_filename%.*}

    log.debug_console "${_cur_path_attachment_file}"
    log.add_indent

    # 存在チェック
    if [ ! -f "${_cur_path_attachment_file}" ]; then
      # 存在していない場合
      log.error_console "ファイルが存在しません。"
      rm -rf ${_dir_work}                                                                         > /dev/null 2>&1
      log.remove_indent 3
      return ${EXITCODE_ERROR}
    fi

    # ファイルアップロード
    gitlab.upload_file "${_group}" "${_project}" "${_cur_path_attachment_file}" "${_cur_path_upload_response}"
    local _cur_ret_code=${PIPESTATUS[0]}
    if [ ${_cur_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
      # 異常終了の場合
      rm -rf ${_dir_work}                                                                          > /dev/null 2>&1
      log.remove_indent 3
      return ${EXITCODE_ERROR}
    fi

    # レスポンスからmarkdown取得
    log.debug_console "cat ${_cur_path_upload_response} | ${DIR_BIN_LIB}/jq .markdown | sed 's|\"||g'"
    local _cur_markdown=`cat ${_cur_path_upload_response} | ${DIR_BIN_LIB}/jq .markdown | sed 's|"||g'`

    log.add_indent
    log.debug_console "markdown: ${_cur_markdown}"
    log.remove_indent

    # 説明ファイルに記載追加
    echo "${_cur_markdown}"                                                                       >> ${_path_description}
    echo ""                                                                                       >> ${_path_description}

    log.remove_indent

    # カウントアップ
    _count_upload_file=`expr ${_count_upload_file} + 1`

    # 次のファイルへ
    shift
  done
  log.remove_indent

  # リリースノートへ反映
  log.debug_console "ファイル添付"
  log.add_indent

  gitlab.update_tag_release "${_group}" "${_project}" "${_tag}" "${_path_description}"
  local _ret_code=$?
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    rm -rf ${_dir_work}                                                                            > /dev/null 2>&1
    log.remove_indent 2
    return ${EXITCODE_ERROR}
  fi
  log.remove_indent

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -rf ${_dir_work}                                                                              > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   プロジェクトのメンバー一覧を取得します。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
#   ・3: 出力先パス
#
# 戻り値
#   0: 異常終了した場合
#   6: エラーが発生した場合
#
#--------------------------------------------------------------------------------------------------
function gitlab.get_project_member() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent
  local _USAGE="Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT PATH_OUT"

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "${_USAGE}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # グループ名
  local _group="$1"
  # プロジェクト名
  local _project="$2"
  # 出力先パス
  local _path_out="$3"
  if [ ! -d `dirname ${_path_out}` ]; then
    mkdir -p `dirname ${_path_out}`
  fi


  #--------------------------------------------------
  # 本処理
  #--------------------------------------------------
  # プロジェクトID取得
  local _project_id=`gitlab.local.get_project_id "${_group}" "${_project}"`
  local _cur_return_code=$?
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o "${_project_id}" = "" ]; then
    # プロジェクトIDが取得できない場合、エラー終了
    log.error_console "プロジェクトIDの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、プロジェクトID：${_project_id}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  log.add_indent
  log.debug_console "project id   : ${_project_id}"
  log.remove_indent

  # HTTPメソッド
  local _http_method="GET"

  # マージリクエスト取得URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/users"

  # 一時ファイルパス
  local _path_response="${_path_out}"

  # リクエスト実行
  gitlab.local.execute_api "${_http_method}" "${_url}" "${_path_response}"
  local _cur_return_code=$?

  # 取得結果出力
  log.debug_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_console
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 200系以外の場合、エラー終了
    log.error_console "メンバーリストの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  log.remove_indent
  return ${_ret_code}
}
