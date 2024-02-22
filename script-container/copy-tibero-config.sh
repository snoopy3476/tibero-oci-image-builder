#!/bin/sh

#############################################################
########## TIBERO OCI IMAGE BUILDER - config copy ###########
#############################################################
################## kim.hwiwon@outlook.com ###################
#############################################################

# this script copies files in the mounted init volume
# to paths for each file corresponding to the current version of tibero runner
# use on initialization stage, or when replacing license

# run this as root account


copy_if_exist() {
  SRC_PATH="${1:?No source path}"
  DEST_PATH="${2:?No destination path}"
  if [ -f "${SRC_PATH}" ]
  then
    mkdir -p "$(dirname "${DEST_PATH}")"
    cp -f "${SRC_PATH}" "${DEST_PATH}" && chown "${TB_ACC_UID}:${TB_ACC_GID}" "${DEST_PATH}" || return 1;
  fi
}

TB_INIT_HOST_VOL="${TB_INIT_HOST_VOL:?No TB_INIT_HOST_VOL set!}"



# show source
printf " - Copying initial Tibero config to persistable...\n\n [Source Host Volume] - %s \n%s\n\n" \
       "$(mountpoint "${TB_INIT_HOST_VOL}")" \
       "$(tree "${TB_INIT_HOST_VOL}")"



# check root
[ "$(id -u)" -eq 0 ] || { printf " * Run this script with container user root.\n"; exit 1; }

# license.xml
copy_if_exist "${TB_INIT_HOST_VOL}"/license.xml "${TB_ACC_PERSIST_CONFIG}/license/license.xml" || exit 1

# account-list
copy_if_exist "${TB_INIT_HOST_VOL}"/account-list "${TB_ACC_FILE}" || exit 1

# tibero tip template
copy_if_exist "${TB_INIT_HOST_VOL}"/tip.template "${TB_ACC_PERSIST_CONFIG}/tip/tip.template" || exit 1

# sql
copy_if_exist "${TB_INIT_HOST_VOL}"/create-db.sql "${TB_CUSTOM_DB_CREATE_SQL}" || exit 1
copy_if_exist "${TB_INIT_HOST_VOL}"/init.sql "${TB_CUSTOM_INIT_SQL}" || exit 1



# show results
printf " - Tibero config copied.\n\n [Target Config Directory] \n%s\n\n" \
       "$(tree "${TB_ACC_PERSIST_CONFIG}")"
