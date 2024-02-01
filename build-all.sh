#!/bin/sh
# build both normal image && prepared image with all tibero package inside the dir 'pkg'
#
# usage: build-all.sh <oci-cmd (podman/docker)> <jdk-version>
#
# env vars
#   - BASE_IMG_REGISTRY: prefix (registry server && namespace) of the built tibero image
#   - TIBERO_IMG_VERSION: prefix of tag version (should be set when BASE_IMG_REGISTRY set)

OCI_CMD="${1:?No OCI command name given}"
TIBERO_JDK_VERSION="${2:?No JDK version given}"

export BASE_IMG_REGISTRY TIBERO_IMG_VERSION
if [ -n "${BASE_IMG_REGISTRY}" ] && [ -z "${TIBERO_IMG_VERSION}" ]
then printf " *** BASE_IMG_REGISTRY is defined but TIBERO_IMG_VERSION is not! *** \n"; exit 1;
fi

# check required binaries
for bin in jq envsubst; do command -v "${bin}" >/dev/null || { printf " *** No '%s' command found! *** \n" "${bin}"; exit 1; }; done


export BASE_IMG_TAG="${BASE_IMG_TAG:-glibc}"


for pkg in pkg/*/
do
  printf "\n\n\n ***** Building '%s' with '%s' + '%s' ... ***** \n" \
         "$(basename "${pkg}")" "busybox:${BASE_IMG_TAG}" "openjdk:${TIBERO_JDK_VERSION}"
  ./build.sh "${OCI_CMD}" "${pkg}" "${TIBERO_JDK_VERSION}" && \
    ./build-prepared.sh "${OCI_CMD}" "${pkg}" "${TIBERO_JDK_VERSION}" || \
    exit 1
done


./pack-deploy-templates.sh
