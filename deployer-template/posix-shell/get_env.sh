#!/bin/sh

#
# Load an env file to the current shell.
#
# environment variables:
#   - Required (provide this either via '.env' file, or by direct environment variable)
#     - TB_IMG_NAME: full name with tag of tibero image to run
#
#   - Optional
#     - ENV_FILE: environment file to read (Default: '.env')
#     - OCI_CMD: OCI container command to use (Auto-detect the usable one if not provided)
#     - TB_PORT: Tibero port to bind on the host (Default: '10000')
#     - TB_VOLUME_MOUNT_PATH: Volume path to mount inside the container (Default: '/opt/tibero/persistable')
#     - TB_ASSET_DIR: Asset directory path, which contains license.xml, etc. (Default: './asset')
#     - TB_CNT_RESTART_POLICY: Restart policy of created container (Default: 'unless-stopped')
#     - TB_CNT_STOP_TIMEOUT: Timeout in seconds to kill the container after sending stop signal (Default: '120')
#     - TB_CNT_NAME: Name of the container (Default: 'tb-${TB_PORT}')
#     - TB_VOL_NAME: Name of the volume (Default: 'tb-${TB_PORT}')
#

# external envs
ENV_FILE="${ENV_FILE:-.env}"

# path envs
BIN_ORIG="$(readlink -f "${0}")"
ROOT_DIR="$(dirname "${BIN_ORIG?:binary path error!}")"

_CWD="$(pwd)"
cd "${ROOT_DIR}" || { printf " *** Failed to change directory to '%s'! ***\n" "${ROOT_DIR}"; exit 1; }

# load envfile envs
. "${ROOT_DIR}/${ENV_FILE}"


# auto-detect usable command if not given (check in podman -> docker order)
if [ -z "$OCI_CMD" ]
then
  if command -v podman >/dev/null
  then
    export OCI_CMD="podman"
  elif command -v docker >/dev/null
  then
    if [ -w /var/run/docker.sock ]; then export OCI_CMD="docker"; else export OCI_CMD="sudo docker"; fi
  else
    printf " *** No usable command detected (podman/docker) ***\n" >&2
    exit 1
  fi
fi
# get locked manager if initialized once
if [ -r "${ROOT_DIR}/.oci_cmd_lock" ]
then
  OCI_CMD="$(cat "${ROOT_DIR}/.oci_cmd_lock")"
fi


# process some envs
TB_ASSET_DIR="$(readlink -f "${TB_ASSET_DIR:-./asset}")" || exit 1
TB_HOSTNAME="$(grep -o "<licensee>[^<]*</licensee>" "${TB_ASSET_DIR}"/license.xml | sed 's/<licensee>\([^>]*\)<\/licensee>/\1/')"

# envfile check & default values
# required
export TB_HOSTNAME="${TB_HOSTNAME:?Error on detecting TB_HOSTNAME!}"
export TB_IMG_NAME="${TB_IMG_NAME:?No TB_IMG_NAME set!}"
# optional
export TB_PORT="${TB_PORT:-10000}"
export TB_VOLUME_MOUNT_PATH="${TB_VOLUME_MOUNT_PATH:-/opt/tibero/persistable}"
export TB_ASSET_DIR="${TB_ASSET_DIR}"
export TB_CNT_RESTART_POLICY="${TB_CNT_RESTART_POLICY:-unless-stopped}"
export TB_CNT_STOP_TIMEOUT="${TB_CNT_STOP_TIMEOUT:-120}"
export TB_CNT_NAME="${TB_CNT_NAME:-tb-${TB_PORT}}"
export TB_VOL_NAME="${TB_VOL_NAME:-tb-${TB_PORT}}"


cd "${_CWD}" || exit 1
unset _CWD
true
