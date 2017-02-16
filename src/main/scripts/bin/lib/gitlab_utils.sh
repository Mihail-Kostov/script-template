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
#   ・gitlab.has_merge_request
#   ・gitlab.upload_file
#   ・gitlab.is_exist_tag_release
#   ・gitlab.update_tag_release
#   ・gitlab.attachment_archive
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
readonly PER_PAGE_COUNT=1000


#--------------------------------------------------------------------------------------------------
# 概要
#   （Util Private）APIアクセス向けのGitLabでのプロジェクトID取得処理
#
# 前提
#   なし
#
# 引数
#   ・1: GitLabグループ名
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

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT"
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
  # プロジェクト情報取得エンドポイントURL
  local readonly _url="${GITLAB_URL}/api/v3/projects?per_page=${PER_PAGE_COUNT}"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_log 'curl -s -X GET --header "PRIVATE-TOKEN: '${GITLAB_APIKEY}'" '${_url}' -o '${_path_response}' -w '"'%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X GET --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_url} -o ${_path_response} -w '%{http_code}'`
  local _cur_return_code=$?
  log.debug_log "response code      : ${_response_code}"
  log.debug_log "return code        : ${_cur_return_code}"
  log.remove_indent

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
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
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

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TARGET_BRANCH"
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

  # protect実行エンドポイントURL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/repository/branches/${_branch}"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_console 'curl -s -X GET --header "PRIVATE-TOKEN: '${GITLAB_APIKEY}'" '${_url}' -o '${_path_response}' -w '"'%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X GET --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_url} -o ${_path_response} -w '%{http_code}'`
  _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

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
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
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

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TARGET_BRANCH"
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

  # protect実行エンドポイントURL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/repository/branches/${_branch}/protect"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_console 'curl -s -X PUT --header "PRIVATE-TOKEN: '${GITLAB_APIKEY}'" '${_url}' -o '${_path_response}' -w '"'%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X PUT --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_url} -o ${_path_response} -w '%{http_code}'`
  _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

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
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" -o `echo ${_is_protected}`"" != "true" ]; then
    # 200系以外の場合、エラー終了
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

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TARGET_BRANCH"
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

  # protect実行エンドポイントURL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/repository/branches/${_branch}/unprotect"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_console 'curl -s -X PUT --header "PRIVATE-TOKEN: '${GITLAB_APIKEY}'" '${_url}' -o '${_path_response}' -w '"'%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X PUT --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_url} -o ${_path_response} -w '%{http_code}'`
  _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

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
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" -o `echo ${_is_protected}`"" != "false" ]; then
    # 200系以外の場合、エラー終了
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
#   プロジェクトにOpen状態のマージリクエストが存在するかチェックします。
#
# 前提
#   ・実行ユーザに、対象リポジトリの設定を変更する権限が付与されていること
#
# 引数
#   ・1: GitLabグループ名
#   ・2: GitLabプロジェクト名
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
function gitlab.has_merge_request() {
  #--------------------------------------------------
  # 事前処理
  #--------------------------------------------------
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  # 引数の数
  if [ $# -ne 2 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT"
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

  # マージリクエスト取得URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/merge_requests?per_page=${PER_PAGE_COUNT}&state=opened"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_console 'curl -s -X GET --header "PRIVATE-TOKEN: '${GITLAB_APIKEY}'" '${_url}' -o '${_path_response}' -w '"'%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X GET --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" ${_url} -o ${_path_response} -w '%{http_code}'`
  _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

  # 取得結果出力
  log.debug_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_console
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
    log.error_console "マージリクエストの取得でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # マージリクエスト存在判定
  local _has_merge_request=true
  local _ret_code=${EXITCODE_SUCCESS}
  log.debug_console "cat ${_path_response} | ${DIR_BIN_LIB}/jq . | ${DIR_BIN_LIB}/Parsrs/parsrj.sh | grep \"$\[[0-9]*\].project_id\""
  local _grep_result=`cat ${_path_response} | ${DIR_BIN_LIB}/jq . | ${DIR_BIN_LIB}/Parsrs/parsrj.sh | grep "$\[[0-9]*\].project_id"`
  if [ "${_grep_result}" != "" ]; then
    # 存在する場合
    _has_merge_request=true
    _ret_code=${EXITCODE_SUCCESS}
  else
    # 存在しない場合
    _has_merge_request=false
    _ret_code=${EXITCODE_WARN}
  fi

  # 判定結果出力
  log.add_indent
  log.debug_console "has_merge_request : ${_has_merge_request}"
  log.remove_indent
  echo "${_has_merge_request}"


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
#   {
#     "alt":"ファイル名",
#     "url":"upload先参照URL",
#     "is_image":"true / false",
#     "markdown":"markdown書式での参照記述"
#   }
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

  # 引数の数
  if [ $# -ne 4 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT PATH_UPLOAD_FILE PATH_OUTPUT_RESPONSE"
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

  # リクエスト実行URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/uploads"

  # リクエスト実行
  log.debug_console "curl -s -X POST --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" \"${_url}\" -F \"file=@${_path_upload_file}\" -o \"${_path_output_response}\" -w '%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X POST --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" "${_url}" -F "file=@${_path_upload_file}" -o "${_path_output_response}" -w '%{http_code}'`
  _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

  # 取得結果出力
  log.debug_console "${_path_output_response}:"
  log.add_indent
  cat ${_path_output_response}                                                                     |
  log.debug_console
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
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

  # 引数の数
  if [ $# -ne 3 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TAG"
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

  # タグ一覧取得エンドポイントURL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/repository/tags?per_page=${PER_PAGE_COUNT}"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リクエスト実行
  log.debug_console "curl -s -X GET --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" \"${_url}\" -o \"${_path_response}\" -w '%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X GET --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" "${_url}" -o "${_path_response}" -w '%{http_code}'`
  _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

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
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" -o "${_release}" = "" ]; then
    # 200系以外の場合、エラー終了
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

  # 引数の数
  if [ $# -ne 4 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TAG PATH_DESCRIPTION_FILE"
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

  # リクエスト実行URL
  local readonly _url="${GITLAB_URL}/api/v3/projects/${_project_id}/repository/tags/${_tag}/release"

  # 一時ファイルパス
  local _path_response="/tmp/${FUNCNAME[0]}_$$"

  # リリースノートの存在チェック
  gitlab.is_exist_tag_release "${_group}" "${_project}" "${_tag}"
  _cur_return_code=$?

  if [ ${_cur_return_code} -eq ${EXITCODE_SUCCESS} ]; then
    # 正常終了の場合 (更新)
    _http_method="PUT"
  elif [ ${_cur_return_code} -eq ${EXITCODE_WARN} ]; then
    # 警告終了の場合（新規追加）
    _http_method="POST"
  else
   # 異常終了の場合、ここで終了
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  log.debug_console "curl -s -X ${_http_method} --header \"PRIVATE-TOKEN: ${GITLAB_APIKEY}\" \"${_url}\" -F \"description=<${_path_description}\" -o \"${_path_response}\" -w '%{http_code}'"
  log.add_indent
  local _response_code=`curl -s -X ${_http_method} --header "PRIVATE-TOKEN: ${GITLAB_APIKEY}" "${_url}" -F "description=<${_path_description}" -o "${_path_response}" -w '%{http_code}'`
  _cur_return_code=$?
  log.debug_console "response code: ${_response_code}"
  log.debug_console "return code  : ${_cur_return_code}"
  log.remove_indent

  # 取得結果出力
  log.debug_console "${_path_response}:"
  log.add_indent
  cat ${_path_response}                                                                            |
  log.debug_console
  log.remove_indent

  # 結果チェック
  if [ ${_cur_return_code} -ne ${EXITCODE_SUCCESS} -o `echo ${_response_code} | cut -c 1`"" != "2" ]; then
    # 200系以外の場合、エラー終了
    log.error_console "リリースノートの更新でエラーが発生しました。グループ：${_group}、プロジェクト：${_project}、対象タグ；${_tag}、レスポンスファイル：${_path_response}"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi


  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -f ${_path_response}                                                                            > /dev/null 2>&1

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

  # 引数の数
  if [ $# -lt 4 ]; then
    log.error_console "Usage: ${FUNCNAME[0]} GITLAB_GROUP GITLAB_PROJECT TAG PATH_TARGET_FILE1 [PATH_TARGET_FILE2 PATH_TARGET_FILE3 ...]"
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
      # 存在してない場合
      log.error_console "ファイルが存在しません。"
      rm -rf ${_dir_work}                                                                            > /dev/null 2>&1
      log.remove_indent 3
      return ${EXITCODE_ERROR}
    fi

    # ファイルアップロード
    gitlab.upload_file "${_group}" "${_project}" "${_cur_path_attachment_file}" "${_cur_path_upload_response}"
    local _cur_ret_code=${PIPESTATUS[0]}
    if [ ${_cur_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
      # 異常終了の場合
      rm -rf ${_dir_work}                                                                            > /dev/null 2>&1
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
    echo "${_cur_markdown}"                                                                          >> ${_path_description}
    echo ""                                                                                          >> ${_path_description}

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
    rm -rf ${_dir_work}                                                                              > /dev/null 2>&1
    log.remove_indent 2
    return ${EXITCODE_ERROR}
  fi
  log.remove_indent

  #--------------------------------------------------
  # 事後処理
  #--------------------------------------------------
  # 一時ファイル削除
  rm -rf ${_dir_work}                                                                                > /dev/null 2>&1

  log.remove_indent
  return ${_ret_code}
}
