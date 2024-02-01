#!/bin/sh
# build a normal image with the tibero package inside the given pkg-dir-path
#
# usage: build.sh <oci-cmd (podman/docker)> <pkg-dir-path (where tar.gz located)> <jdk-version>
#
# env vars
#   - BASE_IMG_REGISTRY: prefix (registry server && namespace) of the built tibero image
#   - TIBERO_IMG_VERSION: prefix of tag version (should be set when BASE_IMG_REGISTRY set)



# args
OCI_CMD="${1:?No OCI command name given}"
TIBERO_PACKAGE_DIR="${2:?No tibero installer dir given}"
TIBERO_JDK_VERSION="${3:?No JDK version given}"



# external envs
BASE_IMG_REGISTRY="${BASE_IMG_REGISTRY:-}"
TIBERO_IMG_VERSION="${TIBERO_IMG_VERSION:-}"
if [ -n "${BASE_IMG_REGISTRY}" ] && [ -z "${TIBERO_IMG_VERSION}" ]
then printf " *** BASE_IMG_REGISTRY is defined but TIBERO_IMG_VERSION is not! *** \n"; exit 1;
fi
BASE_IMG_TAG="${BASE_IMG_TAG:-glibc}"



# derived envs
TIBERO_PACKAGE="$(find "${TIBERO_PACKAGE_DIR}" -name "*.tar.gz" | head -n1)" || exit 1
TIBERO_IMG_NAME="${BASE_IMG_REGISTRY:+${BASE_IMG_REGISTRY}/}$(basename "${TIBERO_PACKAGE_DIR}")" || exit 1
TIBERO_IMG_TAG_VERONLY="${TIBERO_IMG_VERSION}"
TIBERO_IMG_TAG_SHORT="${TIBERO_IMG_VERSION:+${TIBERO_IMG_VERSION}_}jdk${TIBERO_JDK_VERSION}"
TIBERO_IMG_TAG="${TIBERO_IMG_TAG_SHORT}_$(basename "${TIBERO_PACKAGE%.tar.gz}" | tr '_' '-')" || exit 1



# build
printf " - Building the image...\n"
${OCI_CMD} build . --no-cache -t "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG}" \
           --build-arg TB_JDK_VERSION="${TIBERO_JDK_VERSION}" \
           --build-arg TB_PACKAGE_DIR="${TIBERO_PACKAGE_DIR}" \
           --build-arg BASE_IMG_TAG="${BASE_IMG_TAG}" \
           -f Containerfile || exit 1

${OCI_CMD} tag "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG}" "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG_SHORT}" || exit 1
if [ -n "${TIBERO_IMG_VERSION}" ] && [ -n "${BASE_IMG_REGISTRY}" ]
then
  ${OCI_CMD} tag "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG}" "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG_VERONLY}" || exit 1
else
  ${OCI_CMD} tag "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG}" "${TIBERO_IMG_NAME}:latest" || exit 1
fi



# push
if [ -n "${TIBERO_IMG_VERSION}" ] && [ -n "${BASE_IMG_REGISTRY}" ]
then
  printf " - Pushing the image...\n"
  ${OCI_CMD} push "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG}" || exit 1
  ${OCI_CMD} push "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG_SHORT}" || exit 1
  ${OCI_CMD} push "${TIBERO_IMG_NAME}:${TIBERO_IMG_TAG_VERONLY}" || exit 1
fi
