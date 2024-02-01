#!/bin/sh

# external envs
TIBERO_IMG_VERSION="${TIBERO_IMG_VERSION:-}"

# envs
BUILD_DIR="./out-deployer"
TEMPLATE_DIR="./deployer-template"

mkdir -p "${BUILD_DIR}"

for template in "$TEMPLATE_DIR"/*
do
  PACKAGE_BASENAME="$(basename "${template}")"
  printf "\n - Packing '%s' in the directory '%s'...\n" "${PACKAGE_BASENAME}${TIBERO_IMG_VERSION:+ (${TIBERO_IMG_VERSION})}" "${BUILD_DIR}"
  if [ -d "${template}" ]
  then
    tar -C "${TEMPLATE_DIR}" -zcvf "${BUILD_DIR}/${PACKAGE_BASENAME}${TIBERO_IMG_VERSION:+-${TIBERO_IMG_VERSION}}.tar.gz" "${PACKAGE_BASENAME}"
  fi
done
printf "\n"
