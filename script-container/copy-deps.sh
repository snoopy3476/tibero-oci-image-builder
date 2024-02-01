#!/bin/sh

# copy script on image build (Containerfile)

EXCLUDE_PATH="${EXCLUDE_PATH:-}"

DEST_DIR="${1:?No destination dir}"

shift || exit 1
[ "${#}" -le 0 ] && exit 1




IFS='
'



TARGET_LIST=''
for target in "${@}"
do
  TARGET_LIST="${TARGET_LIST}
$(readlink -f "$target")"
done

TARGET_PATH_LIST="$(printf "%s" "${TARGET_LIST}" | sort | uniq)"

TARGET_EXE_LIST="$(find ${TARGET_PATH_LIST} -executable -type f -not -type d | sort | uniq)" || exit 1

TARGET_LIB_LIST="$(ldd ${TARGET_EXE_LIST} 2>/dev/null | grep "^	.* (0x[0-9a-f]*)$" | awk 'NF == 4 {print $3}; NF == 2 {print $1}' | sort | uniq)"
[ -z "${TARGET_LIB_LIST}" ] && return 0

EXCLUDE_PATH_FULL="$(readlink -f "${EXCLUDE_PATH}")"
TARGET_LIB_EXIST_LIST=''
for lib in ${TARGET_LIB_LIST}
do
  case "${lib}" in "${EXCLUDE_PATH_FULL}"*) continue;; esac

  if [ -f "$(readlink -f "${lib}")" ]
  then
    TARGET_LIB_EXIST_LIST="${TARGET_LIB_EXIST_LIST}
${lib}"
  fi
done
[ -z "${TARGET_LIB_EXIST_LIST}" ] && return 0



mkdir -p "${DEST_DIR}"
cp -afvL ${TARGET_LIB_EXIST_LIST} "${DEST_DIR}" || return 1



unset IFS
