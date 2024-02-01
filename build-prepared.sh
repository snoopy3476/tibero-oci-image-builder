#!/bin/sh
# build a prepared image with the normal tibero image built with 'build.sh'
# * NOTE: before running this script, run 'build.sh' first (with the EXACTLY SAME parameter & env vars)
#         if no image was built from it previously.
#
# usage: build-prepared.sh <oci-cmd (podman/docker)> <pkg-dir-path (where tar.gz located)> <jdk-version>
#
# env vars
#   - BASE_IMG_REGISTRY: prefix (registry server && namespace) of the built tibero image
#   - TIBERO_IMG_VERSION: prefix of tag version (should be set when BASE_IMG_REGISTRY set)



# args
OCI_CMD="${1:?No OCI command name given}"
TIBERO_PACKAGE_DIR="${2:?No tibero installer dir given}"
TIBERO_JDK_VERSION="${3:?No JDK version given}"



# check required binaries
for bin in jq envsubst; do command -v "${bin}" >/dev/null || { printf " *** No '%s' command found! *** \n" "${bin}"; exit 1; }; done



# external envs
BASE_IMG_REGISTRY="${BASE_IMG_REGISTRY:-}"
TIBERO_IMG_VERSION="${TIBERO_IMG_VERSION:-}"
if [ -n "${BASE_IMG_REGISTRY}" ] && [ -z "${TIBERO_IMG_VERSION}" ]
then printf " *** BASE_IMG_REGISTRY is defined but TIBERO_IMG_VERSION is not! *** \n"; exit 1;
fi



# derived envs
TIBERO_PACKAGE_PREPARED_DIR="${TIBERO_PACKAGE_DIR}/prepared"
TIBERO_PACKAGE="$(find "$TIBERO_PACKAGE_DIR" -name "*.tar.gz" | head -n1)" || exit 1
TIBERO_SRC_IMG_NAME="${BASE_IMG_REGISTRY:+${BASE_IMG_REGISTRY}/}$(basename "$(dirname "${TIBERO_PACKAGE}")")" || exit 1
TIBERO_IMG_NAME="${TIBERO_SRC_IMG_NAME}-prepared"
TIBERO_IMG_TAG_VERONLY="${TIBERO_IMG_VERSION}"
TIBERO_IMG_TAG_SHORT="${TIBERO_IMG_VERSION:+${TIBERO_IMG_VERSION}_}jdk${TIBERO_JDK_VERSION}"
TIBERO_IMG_TAG="${TIBERO_IMG_TAG_SHORT}_$(basename "${TIBERO_PACKAGE%.tar.gz}" | tr '_' '-')" || exit 1

TIBERO_LICENSE_FILE="${TIBERO_PACKAGE_PREPARED_DIR}/license.xml"
TIBERO_DBUSER_DATAFILE_COUNT="${TIBERO_DBUSER_DATAFILE_COUNT:-1}"
TIBERO_HOSTNAME="$(grep -o "<licensee>[^<]*</licensee>" "${TIBERO_LICENSE_FILE}" | sed 's/<licensee>\([^>]*\)<\/licensee>/\1/')" || exit 1

TIBERO_IMG_ENTRYPOINT="$(${OCI_CMD} inspect -f '{{json .Config.Entrypoint}}' "${TIBERO_SRC_IMG_NAME}:${TIBERO_IMG_TAG}")" || exit 1
TIBERO_IMG_CMD="$(${OCI_CMD} inspect -f '{{json .Config.Cmd}}' "${TIBERO_SRC_IMG_NAME}:${TIBERO_IMG_TAG}")" || exit 1



# read and export base container 'TB_*' env vars
eval "$(${OCI_CMD} inspect -f '{{json .Config.Env}}' "${TIBERO_SRC_IMG_NAME}:${TIBERO_IMG_TAG}" \
  | jq -r '"export \"" + ( [.[] | select(startswith("TB_"))] | join ("\" \"") ) + "\""')" || exit 1



# create temp file with envsubst
TIBERO_PREPARED_ASSET_DIR="$(mktemp -d)"
envsubst_to_tmpfile() {
  [ "${#}" -gt 0 ] || { printf " * No source file argument\n"; return 1; }
  [ -n "${TIBERO_PREPARED_ASSET_DIR}" ] || { printf " * No TIBERO_PREPARED_ASSET_DIR set!\n"; return 1; }

  unset FAILED

  for source_file in "${@}"
  do
    if [ -f "${source_file}" ]
    then
      TARGET_FILE="${TIBERO_PREPARED_ASSET_DIR}/$(basename "${source_file}")" || return 1
      envsubst < "${source_file}" | tee "${TARGET_FILE}" >/dev/null && chmod 644 "${TARGET_FILE}" || return 1
    else
      printf " * No source file: '%s'\n" "${source_file}" >&2
      FAILED=1
    fi
  done

  [ -z "$FAILED" ] || return 2
}



# build
printf " - Creating a new init container...\n"
trap 'RET_VAL="${?}"; ${OCI_CMD} rm -f "${TIBERO_CNT_ID}"; [ -d "${TIBERO_PREPARED_ASSET_DIR}" ] && rm -rf "${TIBERO_PREPARED_ASSET_DIR}"; exit "$RET_VAL";' INT HUP TERM EXIT



printf " - Starting the init container in sleep mode...\n"
TIBERO_CNT_ID="$(${OCI_CMD} create -h "${TIBERO_HOSTNAME}" \
  -e TB_DBUSER_DATAFILE_COUNT="${TIBERO_DBUSER_DATAFILE_COUNT}" \
  --entrypoint /bin/sh "${TIBERO_SRC_IMG_NAME}:${TIBERO_IMG_TAG}" \
  -c "trap 'kill -9 \${SLEEP_PID}; exit' TERM; while true; do sleep infinity & SLEEP_PID=\${!}; wait \${SLEEP_PID}; done;")" || exit 1
${OCI_CMD} start "${TIBERO_CNT_ID}" || exit 1



printf " - Copying necessary files to the new init container...\n"
envsubst_to_tmpfile "${TIBERO_PACKAGE_PREPARED_DIR}/license.xml" "${TIBERO_PACKAGE_PREPARED_DIR}/account-list" "${TIBERO_PACKAGE_PREPARED_DIR}/tip" || exit 1
if find "${TIBERO_PACKAGE_PREPARED_DIR}/"*.sql 2>/dev/null | grep . >/dev/null; then envsubst_to_tmpfile "${TIBERO_PACKAGE_PREPARED_DIR}/"*.sql || exit 1; fi
${OCI_CMD} cp "${TIBERO_PREPARED_ASSET_DIR}/." "${TIBERO_CNT_ID}":"${TB_INIT_HOST_VOL:?No TB_INIT_HOST_VOL set!}" || exit 1
rm -rf "${TIBERO_PREPARED_ASSET_DIR}"
${OCI_CMD} exec --user root "${TIBERO_CNT_ID}" copy-tibero-config



printf " - Initializing the init container...\n"
${OCI_CMD} exec "${TIBERO_CNT_ID}" tibero init || exit 1
${OCI_CMD} exec "${TIBERO_CNT_ID}" /bin/sh -c \
         "rm -f \"\${TB_ACC_PERSIST_CONFIG}/license/license.xml\" || exit 1; rm -rf \"\$TB_HOME\"/instance/tibero/log/* \"\$CUSTOM_DB_CREATE_SQL\"" || exit 1
${OCI_CMD} exec --user root "${TIBERO_CNT_ID}" sync
${OCI_CMD} exec "${TIBERO_CNT_ID}" /bin/sh -c \
         "printf \" [Final Target Config Directory] \\n%s\\n\\n\" \"\$(tree \"\${TB_ACC_PERSIST_CONFIG}\")\"" || exit 1
${OCI_CMD} stop "${TIBERO_CNT_ID}" || exit 1



printf " - Commiting the init container to the final image...\n"
${OCI_CMD} commit \
           -c "ENTRYPOINT ${TIBERO_IMG_ENTRYPOINT}" -c "CMD ${TIBERO_IMG_CMD}" -c "ENV TB_HOSTNAME=" \
           -a "Kim Hwiwon <kim.hwiwon@outlook.com>" \
           "${TIBERO_CNT_ID}" "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG}" || exit 1
${OCI_CMD} tag "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG}" "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG_SHORT}" || exit 1
if [ -n "${TIBERO_IMG_VERSION}" ] && [ -n "${BASE_IMG_REGISTRY}" ]
then
  ${OCI_CMD} tag "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG}" "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG_VERONLY}" || exit 1
else
  ${OCI_CMD} tag "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG}" "${TIBERO_IMG_NAME}:latest" || exit 1
fi

if [ -n "${TIBERO_IMG_VERSION}" ] && [ -n "${BASE_IMG_REGISTRY}" ]
then
  printf " - Pushing the final image...\n"
  ${OCI_CMD} push "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG}" || exit 1
  ${OCI_CMD} push "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG_SHORT}" || exit 1
  ${OCI_CMD} push "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG_VERONLY}" || exit 1
fi



${OCI_CMD} rm -f "${TIBERO_CNT_ID}"
trap - INT HUP TERM EXIT
