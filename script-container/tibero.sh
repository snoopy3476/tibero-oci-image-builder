#!/bin/sh

#############################################################
########## TIBERO OCI IMAGE BUILDER - entry script ##########
#############################################################
################## kim.hwiwon@outlook.com ###################
#############################################################

TB_SID="${TB_SID:-tibero}"





####################### MAIN ROUTINE ########################


main() {
  START_MODE="${1}"
  set_colors

  case "${START_MODE}" in


  ### init container
  init)

    # check if running
    if wait_for_tbsvr open 0
    then
      printf "%s * Tibero service is running ! * %s\n" "${CX_C}${CF_B}${CB_R}" "${CX_C}" >&2
      exit 1
    fi

    init_svc || exit 1
    print_help
    ;;


  ### manage user
  user)
    shift
    manage_user "${@}" || { rm -f "${TB_ACC_FILE}"; exit 1; }
    rm -f "${TB_ACC_FILE}"
    ;;


  tbsql)
    shift
    if [ "${#}" -le 0 ]
    then tbsql2 /
    else tbsql2 "${@}"
    fi
    ;;


  daemon)

    # check if running
    if wait_for_tbsvr open 0
    then
      print_help
      sleep 1
      printf "%s * Tibero service is already running ! * %s\n" "${CX_C}${CF_B}${CB_R}" "${CX_C}" >&2
      exit 1
    fi

    # if db is not initialized, initialize it first
    init_svc || exit 1



    ### run container service

    # start message
    printf "%s\n\n\n=============================================================\n%s %s %s\n - Starting Tibero service...\n%s \n\n" "${CX_C}${CF_Y}"  "${CX_C}${CF_B}${CB_G}" "$(date +"%F %T %Z")" "${CX_C}${CF_Y}" "${CX_C}"

    trap 'RET_VAL="${?}"; kill -9 "${GLOBAL_SLEEP_PROC}"; kill -9 "${GLOBAL_LOG_PROC}"; on_terminate "${RET_VAL}"' INT HUP TERM EXIT
    # bg process to wait until signal
    sleep infinity &
    GLOBAL_SLEEP_PROC="${!}"
    exec_svc || exit 1
    print_help

    tail -F "${TB_HOME}"/instance/"${TB_SID}"/log/*/*.log &
    GLOBAL_LOG_PROC="${!}"
    # wait until signal (with listening signal)
    wait
    ;;


  test)
    if /bin/test-tibero-conn
    then
      printf "%sconnectable%s\n" "$CX_C$CF_G" "$CX_C"
      true
    else
      printf "%snot-connectable%s\n" "$CX_C$CF_R" "$CX_C"
      false
    fi
    ;;


  help)
    print_help
    ;;


  "")
    print_help
    false
    ;;


  *)
    print_help
    printf "%s * INVALID COMMAND '%s' * %s\n" "${CX_C}${CF_B}${CB_R}" "$START_MODE" "${CX_C}" >&2
    false
    ;;


  esac


  RET_VAL="${?}"
  # remove sensitive data if exists
  rm -f "${TB_ACC_FILE}"

  exit "${RET_VAL}"
}





####################### SUB ROUTINES ########################



init_svc() {

  # follow symlink env
  TB_LICENSE_ORIG="$(readlink -f "${TB_LICENSE}")"
  TB_DBDIR_ORIG="$(readlink -f "$TB_DBDIR")"

  # copy default configs or generate them
  if [ ! -r "${TB_ACC_PERSIST_CONFIG}/tip/tip.template" ]
  then
    cp "${TB_TIP_TEMPLATE_DEFAULT}" "${TB_ACC_PERSIST_CONFIG}/tip/tip.template" || exit 1
  fi
  envsubst < "${TB_ACC_PERSIST_CONFIG}/tip/tip.template" > "${TB_TIP_TEMPLATE}" || exit 1
  ( cd "${TB_HOME}/config/" || exit 1; rm -f ./*.tip; ./gen_tip.sh || exit 1 ) || exit 1

  if [ ! -r "${TB_LICENSE_ORIG}" ] && [ -r "${TB_LICENSE_DEFAULT}" ]
  then
    mkdir -p "$(dirname "${TB_LICENSE_ORIG}")"
    cp "${TB_LICENSE_DEFAULT}" "${TB_LICENSE_ORIG}"
  fi


  ### initialize tibero, if required ###

  # check if initialized
  # do initialize if $TB_DBDIR ($TB_DBDIR_ORIG) does not exist or empty,
  # or '.not-initialized-yet' exists
  if [ ! -d "${TB_DBDIR_ORIG}" ] \
       || [ "$(find "${TB_DBDIR_ORIG}" -mindepth 1 -maxdepth 1 | wc -l)" -eq 0 ] \
       || [ -f "${TB_DBDIR_ORIG}"/.initialization-in-progress ]
  then



    # print system info which may required for debug
    printf "\n\n\n - Tibero initialization started.\n\n%s [Current container info] \n - System memory size:  \t%s\n - Running user & group:\t%s:%s\n - Volume permission:   \t%s\n - Container hostname:   \t%s\n - License file hostname:\t%s\n - Tibero config file:%s\n%s\n%s============ END OF CONFIG =============\n%s\n\n" \
           "${CX_C}${CF_G}" \
           "$(free -h | grep "^Mem: " | awk '{print $2 "B (Available: " $7 "B)"}')" \
           "$(id -u)" "$(id -g)" \
           "$(stat -c "%A %u:%g %N" "${TB_VOLUME_MOUNT_PATH:-${TB_ACC_PERSIST}}")" \
           "$(hostname)" \
           "$(grep -o "<licensee>[^<]*</licensee>" "${TB_LICENSE}" | sed 's/<licensee>\([^>]*\)<\/licensee>/\1/' 2>/dev/null)" \
           "${CX_C}${CF_Y}" "$(cat "${TB_TIP}")" "${CX_C}${CF_G}" \
           "${CX_C}"



    # check for account info file, and prompt if not exists
    if [ ! -r "${TB_ACC_FILE}" ]
    then
      rm -rf "${TB_ACC_FILE}"
      touch "${TB_ACC_FILE}"
      chmod 600 "${TB_ACC_FILE}"

      # check if interactive mode
      if [ ! -t 0 ]
      then
        printf "%s%s\n%s\n" \
               \
               "${CX_C}${CF_B}${CB_R} * DB account should be entered to initialize tibero, " \
               "but current mode is non-interactive. " \
               "   Be sure to run this container in interactive mode! ${CX_C}" >&2
        return 1
      fi
      printf "%s - No pre-configured user account info for Tibero found! Enter your new ID below...%s\n" "${CX_C}${CF_Y}" "${CX_C}" >&2
      get_input_for_new_tibero_users || return 1
    fi



    printf "%s - Initializing tibero... %s\n" "${CF_Y}" "${CX_C}"
    "${TB_HOME}"/bin/tbdown clean >/dev/null 2>/dev/null

    # check if license file exists
    if [ ! -r "${TB_LICENSE}" ]
    then
      printf "%s * License file not found! * %s\n" "${CX_C}${CF_B}${CB_R}" "${CX_C}" >&2
      return 1
    fi
    printf "%s - New license file hostname:%s %s %s\n" \
           "${CX_C}${CF_G}" "${CF_R}" \
           "$(grep -o "<licensee>[^<]*</licensee>" "${TB_LICENSE}" | sed 's/<licensee>\([^>]*\)<\/licensee>/\1/' 2>/dev/null)" \
           "${CX_C}"

    # mark initialize processes as not completed
    mkdir -p "${TB_DBDIR_ORIG}"
    if ! [ -f "${TB_DBDIR_ORIG}"/.initialization-in-progress ]
    then
      touch "${TB_DBDIR_ORIG}"/.initialization-in-progress
      touch "${TB_DBDIR_ORIG}"/.db-not-initialized
      touch "${TB_DBDIR_ORIG}"/.acc-not-initialized
    fi

    # initialize tibero db
    if [ -f "${TB_DBDIR_ORIG}"/.db-not-initialized ]
    then
      if ! query_new_tibero_db "${TB_SID}" "$TB_CHARSET" "$TB_NCHARSET"
      then
        printf "%s * Initializing tibero DB FAILED! * %s\n" "${CX_C}${CF_B}${CB_R}" "${CX_C}" >&2
        return 1
      fi
      rm -f "${TB_DBDIR_ORIG}"/.db-not-initialized
    fi

    # initialize tibero accounts
    if [ -f "${TB_DBDIR_ORIG}"/.acc-not-initialized ]
    then
      if ! new_tibero_accounts "${TB_SID}"
      then
        printf "%s * Initializing tibero accounts FAILED! * %s\n" "${CX_C}${CF_B}${CB_R}" "${CX_C}" >&2
        return 1
      fi
      rm -f "${TB_DBDIR_ORIG}"/.acc-not-initialized
    fi

    # initialize user custom schema
    query_custom_sql "${TB_CUSTOM_INIT_SQL}" || return 1

    # finalize initialization
    "${TB_HOME}"/bin/tbdown post_tx 2>&1 | print_log
    rm -f "${TB_DBDIR_ORIG}"/.initialization-in-progress
  fi

  # always remove id/pw info if exists at this point
  rm -f "${TB_ACC_FILE}" "${TMPSQL}"
}



exec_svc() {

  # follow symlink env
  TB_LICENSE_ORIG="$(readlink -f "${TB_LICENSE}")"
  TB_DBDIR_ORIG="$(readlink -f "$TB_DBDIR")"

  # copy default configs or generate them
  if [ ! -r "${TB_ACC_PERSIST_CONFIG}/tip/tip.template" ]
  then
    cp "${TB_TIP_TEMPLATE_DEFAULT}" "${TB_ACC_PERSIST_CONFIG}/tip/tip.template" || exit 1
  fi
  envsubst < "${TB_ACC_PERSIST_CONFIG}/tip/tip.template" > "${TB_TIP_TEMPLATE}" || exit 1
  ( cd "${TB_HOME}/config/" || exit 1; rm -f ./*.tip; ./gen_tip.sh || exit 1 ) || exit 1

  if [ ! -r "${TB_LICENSE_ORIG}" ] && [ -r "${TB_LICENSE_DEFAULT}" ]
  then
    mkdir -p "$(dirname "${TB_LICENSE_ORIG}")"
    cp "${TB_LICENSE_DEFAULT}" "${TB_LICENSE_ORIG}"
  fi



  [ -x "${TB_HOME}"/bin/tbdown ] && { printf "y\n" | "${TB_HOME}"/bin/tbdown clean | print_log; }
  "${TB_HOME}"/bin/tbboot | print_log "^Tibero instance started up (.*)\.$"

  if ! wait_for_tbsvr connect
  then
    printf "%s * Starting tibero FAILED! * %s \n" "${CX_C}${CF_B}${CB_R}" "${CX_C}" >&2
    return 1
  fi
  printf "%s" "${CX_C}"

  printf "\n%s - Tibero service trigger finished!%s\n" "${CF_G}" "${CX_C}"
  printf " - This shell will now %sWAIT FOREVER%s until the container stops.\n\n" \
         "${CF_R}" "${CX_C}"

  printf "%s\n%s\n%s\n%s%s\n%s\n%s\n" \
         \
         "${CX_C}${CF_G}" \
         "${CX_C}${CF_G} ********************************************************** " \
         "${CX_C}${CF_G} *** To detach container and go back to original shell, *** " \
         "${CX_C}${CF_G} ***           Press ""${CF_B}${CB_Y}""[Ctrl+P]""${CX_C}${CF_G}""," \
         "${CX_C}${CF_G} then ""${CF_B}${CB_Y}""[Ctrl+Q]""${CX_C}${CF_G}""            *** " \
         "${CX_C}${CF_G} **********************************************************" \
         "${CX_C}"
  printf "\n\n%s\n\n" "${TB_READY_SIGNAL_PATTERN}"
}



manage_user() {
  MODE="${1}"
  if [ -z "${MODE}" ]
  then
    printf "%s * Specify which to do after the argument 'user' (ls/detail/new/rm/passwd/lock/unlock/expire) * %s\n" \
           "${CX_C}${CF_B}${CB_R}" "${CX_C}" >&2
    return 1
  fi


  # if tibero is not running, run the temporal service
  IS_TB_ON=1
  if ! wait_for_tbsvr open 0
  then
    unset IS_TB_ON
    exec_svc || {
      printf "%s * Tibero is not running and failed to start! * %s\n" "${CX_C}${CF_B}${CB_R}" "${CX_C}" >&2;
      on_terminate 1;
    }
  fi


  rm -f "${TB_ACC_FILE}"
  case "${MODE}" in

  ls)
    TMPOUT="$(mktemp)"
    printf "exp query '%s' fields term by '' encl by '' lines term by '\t';
            select DECODE(account_status, 'OPEN', '%s', '%s'), username, '%s' from dba_users where username not in ('SYS', 'SYSCAT', 'SYSGIS', 'OUTLN', 'OSA\$%s'); \n" \
            "${TMPOUT}" "${CX_C}${CF_B}${CB_G}" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" "$(printf '%s' "${TB_ACC_NAME}" | tr '[:lower:]' '[:upper:]')" \
            | tee "${TMPSQL}" >/dev/null
    tbsql -s / "@${TMPSQL}" <&- 2>&1 >/dev/null || return 1
    printf "\n\n%s[User List]%s \n%s%s \n\n\n" "${CX_C}${CF_B}${CB_C}" "${CX_C}" "$(sed "s/\t/${CX_C}\t${CF_B}${CB_G}/g" < "${TMPOUT}")" "${CX_C}"
    rm -f "${TMPOUT}"
    ;;


  detail)
    USERNAME="${2}"
    if [ -z "${USERNAME}" ]
    then get_input_for_select_tibero_users 1 || return 1
    else printf "%s\n" "${USERNAME}" | tee "${TB_ACC_FILE}" >/dev/null
    fi

    TMPOUT="$(mktemp)"
    printf "exp query '%s' fields term by '\\\n' encl by '' lines term by '';
            select username, default_tablespace, profile, account_status, lock_date,
            expiry_date, created from dba_users where USERNAME = '%s'; \n" \
            "${TMPOUT}" "$(tr '[:lower:]' '[:upper:]' < "${TB_ACC_FILE}")" \
            | tee "${TMPSQL}" >/dev/null
    tbsql -s / "@${TMPSQL}" <&- 2>&1 >/dev/null || return 1

    TMPROW="$(mktemp)"
    printf "%s[User Name]%s 
%s[Tablespace]%s 
%s[Profile]%s 
%s[Status]%s 
%s[Lock Date]%s 
%s[Expiry Date]%s 
%s[Created Date]%s 
%s \n" \
           "${CX_C}${CF_B}${CB_C}" "${CX_C}${CF_G}" "${CX_C}${CF_B}${CB_C}" "${CX_C}${CF_G}" \
           "${CX_C}${CF_B}${CB_C}" "${CX_C}${CF_G}" "${CX_C}${CF_B}${CB_C}" "${CX_C}${CF_G}" "${CX_C}${CF_B}${CB_C}" "${CX_C}${CF_G}" \
           "${CX_C}${CF_B}${CB_C}" "${CX_C}${CF_G}" "${CX_C}${CF_B}${CB_C}" "${CX_C}${CF_G}" "${CX_C}" \
      | tee "${TMPROW}" >/dev/null
    printf "\n\n%s\n\n" "$(paste "${TMPROW}" "${TMPOUT}" | expand -t 17)"
    rm -f "${TMPROW}" "${TMPOUT}"
    ;;

  new)
    get_input_for_new_tibero_users || return 1
    new_tibero_accounts "${TB_SID}" || return 1
    ;;

  rm)
    CASCADE_FLAG="${2}"
    get_input_for_select_tibero_users || return 1
    remove_tibero_accounts "${CASCADE_FLAG}" || return 1
    ;;

  passwd)
    get_input_for_new_tibero_users 1 no-tablespace || return 1
    printf "alter user \"%s\" identified by '%s'; \n" \
            "$(cut -d/ -f1 "${TB_ACC_FILE}" | "$(tr '[:lower:]' '[:upper:]')")" "$(cut -d/ -f2 "${TB_ACC_FILE}")" \
            | tee "${TMPSQL}" >/dev/null
    tbsql -s / "@${TMPSQL}" <&- 2>&1 || return 1
    ;;

  lock)
    USERNAME="${2}"
    if [ -z "${USERNAME}" ]
    then get_input_for_select_tibero_users 1 || return 1
    else printf "%s\n" "${USERNAME}" | tee "${TB_ACC_FILE}" >/dev/null
    fi

    printf "alter user \"%s\" account lock; \n" \
            "$(tr '[:lower:]' '[:upper:]' < "${TB_ACC_FILE}")" \
            | tee "${TMPSQL}" >/dev/null
    tbsql -s / "@${TMPSQL}" <&- 2>&1 || return 1
    ;;

  unlock)
    USERNAME="${2}"
    if [ -z "${USERNAME}" ]
    then get_input_for_select_tibero_users 1 || return 1
    else printf "%s\n" "${USERNAME}" | tee "${TB_ACC_FILE}" >/dev/null
    fi

    printf "alter user \"%s\" account unlock; \n" \
            "$(tr '[:lower:]' '[:upper:]' < "${TB_ACC_FILE}")" \
            | tee "${TMPSQL}" >/dev/null
    tbsql -s / "@${TMPSQL}" <&- 2>&1 || return 1
    ;;

  expire)
    USERNAME="${2}"
    if [ -z "${USERNAME}" ]
    then get_input_for_select_tibero_users 1 || return 1
    else printf "%s\n" "${USERNAME}" | tee "${TB_ACC_FILE}" >/dev/null
    fi

    printf "alter user \"%s\" password expire; \n" \
            "$(tr '[:lower:]' '[:upper:]' < "${TB_ACC_FILE}")" \
            | tee "${TMPSQL}" >/dev/null
    tbsql -s / "@${TMPSQL}" <&- 2>&1 || return 1
    ;;

  *)
    printf "%s * Invalid user operation: '%s' * %s\n" "${CX_C}${CF_B}${CB_R}" "${MODE}" "${CX_C}" >&2
    ;;
  esac

  # stop tibero if it wasn't running
  [ -n "${IS_TB_ON}" ] || on_terminate
}



print_help() {
    printf "


%s=============================================================%s 
%s --------[ %stibero%s container commands usage (v1.1) ]--------- %s 
%s                                                             %s 
%s                                                             %s 
%s * Only when the container is %srunning%s                        %s 
%s                                                             %s 
%s   - %stbsql%s [arg1] [arg2] ...: Run tbsql as the admin         %s 
%s        > To run with arguments,                             %s 
%s          just add parameters after the 'tbsql'              %s 
%s                                                             %s 
%s     e.g.)                                                   %s 
%s       \$ podman exec -it <container> tibero tbsql            %s 
%s       \$ docker exec -it <container> tibero tbsql id/pw      %s 
%s                                                             %s 
%s                                                             %s 
%s * Only when the container is %sstopped%s                        %s 
%s                                                             %s 
%s   - %sinit%s: Initialize a Tibero volume                        %s 
%s     e.g.)                                                   %s 
%s       \$ podman run -it --rm -v <vol>:<mnt-path> <img> init  %s 
%s       \$ docker run -it --rm -v <vol>:<mnt-path> <img> init  %s 
%s                                                             %s 
%s   - %sdaemon%s: %s(Default)%s (Optional)                            %s 
%s             Start a Tibero service with the                 %s 
%s             initialized volume above                        %s 
%s     e.g.)                                                   %s 
%s       \$ podman run -d -v <vol>:<mnt-path> <img> daemon      %s 
%s       \$ docker run -d -v <vol>:<mnt-path> <img>             %s 
%s                                                             %s 
%s                                                             %s 
%s * Always (on both running and stopped)                      %s 
%s                                                             %s 
%s   - %shelp%s: print this help message                           %s 
%s   - %stest%s: test if Tibero is running and connectable         %s 
%s   - %suser%s: manage users                                      %s 
%s     - %sls%s                                                    %s 
%s     - %sdetail%s [username]                                     %s 
%s     - %snew%s                                                   %s 
%s     - %srm%s [cascade (pass the literal string 'cascade')]      %s 
%s     - %spasswd%s                                                %s 
%s     - %slock%s [username]                                       %s 
%s     - %sunlock%s [username]                                     %s 
%s     - %sexpire%s [username]                                     %s 
%s                                                             %s 
%s     e.g.)                                                   %s 
%s       \$ podman exec -it <container> tibero user create      %s 
%s       \$ docker exec -it <container> tibero user detail sys  %s 
%s       \$ docker exec -it <container> tibero user rm          %s 
%s                                                             %s 
%s                                                             %s 
%s=============================================================%s \n\n" \
      "${CX_C}${CF_B}${CB_Y}$CX_B" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}$CX_B" "${CF_R}" "${CF_B}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      \
      "${CX_C}${CF_B}${CB_Y}$CX_B" "$CF_C" "${CF_B}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      \
      "${CX_C}${CF_B}${CB_Y}$CX_B" "${CF_R}" "${CF_B}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_B}${CF_R}" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      \
      "${CX_C}${CF_B}${CB_Y}$CX_B" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "$CX_B$CF_M" "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      "${CX_C}${CF_B}${CB_Y}" "${CX_C}" \
      \
      "${CX_C}${CF_B}${CB_Y}$CX_B" "${CX_C}"
}



### signal callback: set trap to run on signals ###
on_terminate() {
  trap - EXIT
  EXIT_CODE="${1:-0}"
  set_colors

  if [ -n "${GLOBAL_SLEEP_PROC}" ]; then kill "${GLOBAL_SLEEP_PROC}" || kill -9 "${GLOBAL_SLEEP_PROC}"; fi 2>/dev/null
  if [ -n "${GLOBAL_LOG_PROC}" ]; then kill "${GLOBAL_LOG_PROC}" || kill -9 "${GLOBAL_LOG_PROC}"; fi 2>/dev/null

  if wait_for_tbsvr open 0
  then
    printf "\n%s - Stopping Tibero service... %s\n" "${CX_C}${CF_Y}" "${CX_C}"

    # first stop gracefully (after all transaction ends)
    "${TB_HOME}"/bin/tbdown post_tx 2>&1 | print_log

    if ! wait_for_tbsvr close 60
    then
      # if not exit, cancel all transactions, rollback, and stop immediately
      "${TB_HOME}"/bin/tbdown immediate 2>&1 | print_log
      if ! wait_for_tbsvr close 60
      then
        printf "\n%s * Error during stopping Tibero! * %s\n\n" "${CX_C}${CF_B}${CB_R}" "${CX_C}" >&2
        exit 1
      fi
    fi
  fi

  printf "\n%s - Tibero container stopped. %s\n\n=============================================================\n" "${CX_C}${CF_G}" "${CX_C}"
  exit "$EXIT_CODE"
}



######################### HELPERS ###########################


### load account info ###


get_input_for_new_tibero_users() {
  MAX_USER_COUNT="${1:-9999999}"
  ADDITIONAL_FLAG="${2}"

  CUR_USER_COUNT=1
  while true
  do
    # ID
    unset TB_ID
    while [ -z "${TB_ID}" ]; do read_normal "Enter a new DB ID" TB_ID || return 1; done
    TB_ID="$(printf "%s" "${TB_ID}" | tr '[:lower:]' '[:upper:]')"
    # PW
    unset TB_PW
    while [ -z "${TB_PW}" ]; do read_secret "Enter a DB password for '${TB_ID}'" TB_PW || return 1; done
    # TABLESPACE
    if [ "${ADDITIONAL_FLAG}" != "no-tablespace" ]
    then
      unset TB_TABLESPACE
      read_normal "Enter a tablespace for '${TB_ID}' (named automatically if empty)" TB_TABLESPACE || return 1
    fi

    # write account id/tablespace/pw
    printf "%s%s/%s\n" \
            "${TB_ID}" \
            "${TB_TABLESPACE:+.${TB_TABLESPACE}}" \
            "${TB_PW}" \
            | tee -a "${TB_ACC_FILE}" >/dev/null || return 1

    if [ "${CUR_USER_COUNT}" -ge "${MAX_USER_COUNT}" ]; then break; fi
    CUR_USER_COUNT="$((CUR_USER_COUNT + 1))"

    # prompt to continue, break if no
    unset _CONTINUE
    while ! { [ -n "${_CONTINUE}" ] \
                && { [ "${_CONTINUE}" = "y" ] || [ "${_CONTINUE}" = "Y" ] \
                       || [ "${_CONTINUE}" = "n" ] || [ "${_CONTINUE}" = "N" ]; }; \
            }; do
      read_normal "Add more account? [y/n]" _CONTINUE || return 1
    done
    { [ "${_CONTINUE}" = "n" ] || [ "${_CONTINUE}" = "n" ]; } && break
  done
}


get_input_for_select_tibero_users() {
  MAX_USER_COUNT="${1:-9999999}"

  CUR_USER_COUNT=1
  while true
  do
    # ID
    unset TB_ID
    while [ -z "${TB_ID}" ]; do read_normal "Enter a DB user ID to select" TB_ID || return 1; done
    TB_ID="$(printf "%s" "${TB_ID}" | tr '[:lower:]' '[:upper:]')"

    # write account id
    printf "%s\n" "${TB_ID}" | tee -a "${TB_ACC_FILE}" >/dev/null || return 1

    if [ "${CUR_USER_COUNT}" -ge "${MAX_USER_COUNT}" ]; then break; fi
    CUR_USER_COUNT="$((CUR_USER_COUNT + 1))"

    # prompt to continue, break if no
    unset _CONTINUE
    while ! { [ -n "${_CONTINUE}" ] \
                && { [ "${_CONTINUE}" = "y" ] || [ "${_CONTINUE}" = "Y" ] \
                       || [ "${_CONTINUE}" = "n" ] || [ "${_CONTINUE}" = "N" ]; }; \
            }; do
      read_normal "Select more account? [y/N]" _CONTINUE || return 1
    done
    { [ "${_CONTINUE}" = "n" ] || [ "${_CONTINUE}" = "N" ]; } && break
  done
}


new_tibero_accounts() {
  DB_NAME="${1:?No DB_NAME}"

  if [ -r "${TB_ACC_FILE}" ]
  then
    while read -r ACC_INFO_LINE
    do
      _ID_TABLESPACE_STR="$(printf "%s" "${ACC_INFO_LINE}" | cut -d/ -f1)"
      TB_ID="$(printf "%s." "$_ID_TABLESPACE_STR" | cut -d. -f1 | tr '[:lower:]' '[:upper:]')"
      TB_TABLESPACE="$(printf "%s." "$_ID_TABLESPACE_STR" | cut -d. -f2)"
      TB_PW="$(printf "%s" "${ACC_INFO_LINE}" | cut -d/ -f2-)"

      query_new_tibero_user "${DB_NAME}" "${TB_ID}" "${TB_PW}" "${TB_TABLESPACE}" || return 1
    done < "${TB_ACC_FILE}"

  else

    printf "%s - No pre-configured user account info for Tibero found!%s \n" "${CX_C}${CF_Y}" "${CX_C}" >&2
  fi
}

remove_tibero_accounts() {
  DROP_CASCADE="${1}"

  if [ -r "${TB_ACC_FILE}" ]
  then
    while read -r ACC_INFO_LINE
    do
      TB_ID="${ACC_INFO_LINE}"

      query_remove_tibero_user "${TB_ID}" "${DROP_CASCADE}" || return 1
    done < "${TB_ACC_FILE}"

  else

    printf "%s - No user account info for Tibero found!%s \n" "${CX_C}${CF_Y}" "${CX_C}" >&2
  fi
}


read_normal()
{
  _="${2:?read_normal: No variable to read specified}"

  trap 'printf "\n"; return 1' TERM HUP INT
  printf "%s + %s:%s \n%s > %s " "${CX_C}${CF_Y}" "${1}" "${CX_C}" "${CF_G}" "${CF_R}"
  read -r "${2}"
  RET_VAL="${?}"
  trap - TERM HUP INT
  printf "%s\n" "${CX_C}"

  return "${RET_VAL}"
}

read_secret()
{
  _RET_VAL=1
  _="${2:?read_secret: No variable to read specified}"

  trap 'stty echo; printf "\n"; return 1' TERM HUP INT
  stty -echo

  while true
  do
    printf "%s + %s:%s \n%s > %s " "${CX_C}${CF_Y}" "${1}" "${CX_C}" "${CF_G}" "${CF_R}"
    read -r _PW_FIRST
    printf "%s \n" "${CX_C}"

    printf "%s + %s (Confirm):%s \n%s > %s " "${CF_Y}" "${1}" "${CX_C}" "${CF_G}" "${CF_R}"
    read -r _PW_SECOND
    printf "%s \n" "${CX_C}"
    _RET_VAL_TMP="${?}"

    if [ "${_PW_FIRST}" != "${_PW_SECOND}" ]
    then
      printf "%s * Both inputs do not match! * %s\n" "${CX_C}${CF_B}${CB_R}" "${CX_C}"
      continue
    fi

    eval "${2}"="\"${_PW_FIRST}\""
    _RET_VAL="${_RET_VAL_TMP}"
    break

  done

  stty echo
  trap - TERM HUP INT
  printf "%s\n" "${CX_C}"

  return "${_RET_VAL}"
}



### tibero initialization ###


# initialization process right after the tibero installation
query_new_tibero_db() {
  DB_NAME="${1?No DB name provided}"
  CHAR_SET="${2?No encoding character set provided}"
  NCHAR_SET="${3?No encoding national character set provided}"

  DB_NAME_LOWER="$(printf "%s" "${DB_NAME}" | tr '[:upper:]' '[:lower:]')"


  # create db
  "${TB_HOME}"/bin/tbboot nomount 2>&1 | print_log "^Tibero instance started up (.*)\.$"
  wait_for_tbsvr || return 1
  if [ -r "${TB_CUSTOM_DB_CREATE_SQL}" ]
  then
    printf " - Custom System DB creation SQL found! Creating a new DB using it...\n" | print_log
    tee "${TMPSQL}" < "${TB_CUSTOM_DB_CREATE_SQL}" >/dev/null
  else
    touch "${TMPSQL}"
    chmod 600 "${TMPSQL}"
    printf "
create database \"%s\"
  user sys identified by 'tibero'
  maxinstances 8
  maxdatafiles 100
  character set %s
  national character set %s
  logfile
    group 1 '%s_log-000.log' size 50M,
    group 2 '%s_log-001.log' size 50M,
    group 3 '%s_log-002.log' size 50M
  maxloggroups 255
  maxlogmembers 8
  noarchivelog
    datafile '%s_system.dtf' size 100M autoextend on next 10M maxsize unlimited
    default temporary tablespace TEMP
      tempfile '%s_temp.dtf' size 100M autoextend on next 10M maxsize unlimited
      extent management local autoallocate
    undo tablespace UNDO
      datafile '%s_undo.dtf' size 200M autoextend on next 10M maxsize unlimited
      extent management local autoallocate
    SYSSUB
      datafile '%s_syssub.dtf' size 10M autoextend on next 10M maxsize unlimited
    default tablespace USR
      datafile '%s_usr.dtf' size 100M autoextend on next 10M maxsize unlimited
      extent management local autoallocate;
" \
           "${DB_NAME}" "${CHAR_SET}" "${NCHAR_SET}" \
           "${DB_NAME_LOWER}" "${DB_NAME_LOWER}" "${DB_NAME_LOWER}" \
           "${DB_NAME_LOWER}" "${DB_NAME_LOWER}" "${DB_NAME_LOWER}" "${DB_NAME_LOWER}" "${DB_NAME_LOWER}" \
           | tee "${TMPSQL}" >/dev/null
  fi
  tbsql -s sys/"tibero" "@${TMPSQL}" <&- 2>&1 || return 1


  # initialize db
  "${TB_HOME}"/bin/tbboot 2>&1 | print_log "^Tibero instance started up (.*)\.$"
  wait_for_tbsvr || return 1
  ( cd "${TB_HOME}/scripts" || exit 1;
    ./system.sh -p1 "tibero" -p2 "syscat" -a1 Y -a2 Y -a3 Y -a4 Y error 2>&1 \
      | print_log; ) || true #|| return ${?}



  # remove sample user accounts
  printf "drop user tibero cascade; \n drop user tibero1 cascade;\n" \
          | tee "${TMPSQL}" >/dev/null
  tbsql -s sys/"tibero" "@${TMPSQL}" <&- 2>&1 || return 1

  # add a local linux user admin account
  TB_ACC_NAME_OSA='OSA$'"$(printf "%s" "${TB_ACC_NAME}" | tr '[:lower:]' '[:upper:]')"
  printf 'create user %s identified externally default tablespace SYSTEM;
          grant connect, resource, dba, hs_admin_role to %s with admin option;' \
          "${TB_ACC_NAME_OSA}" "${TB_ACC_NAME_OSA}" \
          | tee "${TMPSQL}" >/dev/null
  tbsql -s sys/"tibero" "@${TMPSQL}" <&- 2>&1 || return 1

  # change sys account password after init
  printf "
          alter user sys identified by '%s';
          alter user syscat identified by '%s';
          alter user sysgis identified by '%s';
          alter user outln identified by '%s';
" \
          "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 63)" \
          "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 63)" \
          "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 63)" \
          "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 63)" \
          | tee "${TMPSQL}" >/dev/null
  tbsql -s sys/"tibero" "@${TMPSQL}" <&- 2>&1 || return 1

  true
}



# user creation process after the tibero initialization
# args: DBNAME, TB_ID, TB_PW, [TABLESPACE] [DATAFILE_COUNT]
query_new_tibero_user() {

  DB_NAME="${1:?No DB name provided}"
  TB_ID="${2:?No id provided to create}"
  TB_PW="${3:?No password provided for tibero account \"${TB_ID}\"}"
  TABLESPACE="${4:-TABLESPACE_${TB_ID}}"
  DATAFILE_COUNT="${5:-$TB_DBUSER_DATAFILE_COUNT}"

  DB_NAME_LOWER="$(printf "%s" "${DB_NAME}" | tr '[:upper:]' '[:lower:]')"
  TABLESPACE_NAME_UPPER="$(printf "%s" "${TABLESPACE}" | tr '[:lower:]' '[:upper:]')"
  TABLESPACE_NAME_LOWER="$(printf "%s" "${TABLESPACE}" | tr '[:upper:]' '[:lower:]')"


  # new tablespace (ignore already exist error)

  DATAFILE_STR=""
  for idx in $(seq "${DATAFILE_COUNT}")
  do
    DATAFILE_STR="${DATAFILE_STR}
      '${DB_NAME_LOWER}_tablespace-${TABLESPACE_NAME_LOWER}-${idx}.dtf' size 100M"
    [ "${idx}" -lt "${DATAFILE_COUNT}" ] && DATAFILE_STR="${DATAFILE_STR},"
  done

  printf "create tablespace \"%s\"
          datafile %s
          autoextend on next 10M maxsize unlimited;" \
          "${TABLESPACE_NAME_UPPER}" "${DATAFILE_STR}" \
          | tee "${TMPSQL}" >/dev/null
  tbsql -s / "@${TMPSQL}" <&- 2>&1


  # new account
  printf "%s\n%s\n" \
         \
         "create user \"${TB_ID}\" identified by '${TB_PW}' default tablespace \"${TABLESPACE_NAME_UPPER}\";" \
         "grant connect, resource, create view to \"${TB_ID}\";" | tee "${TMPSQL}" >/dev/null
  tbsql -s / "@${TMPSQL}" <&- 2>&1 || return 1
  true
}



# user creation process after the tibero initialization
# args: TB_ID
query_remove_tibero_user() {
  TB_ID="${1:?No user id provided to remove}"
  DROP_CASCADE="${2:-}"

  unset DROP_CASCADE_STR
  if [ "${DROP_CASCADE}" = "cascade" ]; then DROP_CASCADE_STR="cascade"; fi

  # drop user
  printf "drop user \"%s\" %s;" "${TB_ID}" "${DROP_CASCADE_STR}" | tee "${TMPSQL}" >/dev/null
  tbsql -s / "@${TMPSQL}" <&- 2>&1 || return 1
  true
}



# run user custom sql
# args: CUSTOM_SQL_PATH
query_custom_sql() {
  CUSTOM_SQL_PATH="${1:?No custom sql path}"

  if [ ! -r "${CUSTOM_SQL_PATH}" ]
  then
    printf " - No custom SQL init file found (%s): skipping...\n" "${CUSTOM_SQL_PATH}"
    return 0
  fi
  printf " - Custom SQL init file found! (%s)\n" "${CUSTOM_SQL_PATH}"

  tbsql -s / "@${CUSTOM_SQL_PATH}" <&- 2>&1 || return 1
  true
}



# args: [WAIT_FOR_CLOSE (open/close)], [TOTAL_WAIT_SEC]
wait_for_tbsvr() {
  WAIT_FOR_CLOSE="${1:-open}"

  TOTAL_WAIT_SEC="${2:-10}"
  WAIT_SEC=0

  if [ "${WAIT_FOR_CLOSE}" = "open" ]
  then
    until pgrep -x "${TB_HOME}/bin/tblistener" >/dev/null 2>/dev/null; do
      if [ "${WAIT_SEC}" -ge "${TOTAL_WAIT_SEC}" ]; then
        return 1
      fi
      WAIT_SEC="$((WAIT_SEC + 1))"
      sleep 1
    done
    return 0
  elif [ "${WAIT_FOR_CLOSE}" = "connect" ]
  then
    until test-tibero-conn >/dev/null 2>/dev/null; do
      if [ "${WAIT_SEC}" -ge "${TOTAL_WAIT_SEC}" ]; then
        return 1
      fi
      WAIT_SEC="$((WAIT_SEC + 1))"
      sleep 1
    done
    return 0
  elif [ "${WAIT_FOR_CLOSE}" = "close" ]
  then
    until ! pgrep -P1 "tbsvr" >/dev/null 2>/dev/null; do
      if [ "${WAIT_SEC}" -ge "${TOTAL_WAIT_SEC}" ]; then
        return 1
      fi
      WAIT_SEC="$((WAIT_SEC + 1))"
      sleep 1
    done
    return 0
  else
    return 1
  fi
}


# args: [READ_UNTIL_LINE_PATTERN]
print_log() {
  STOP_PATTERN="${1}"
  while IFS= read -r line
  do
    printf "%s[%s] %s%s%s\n" \
           "${CX_C}" "$(date +"%F %T %Z")" "${CX_C}${CX_D}" "${line}" "${CX_C}"
    [ -n "${STOP_PATTERN}" ] \
      && printf "%s" "${line}" | grep "${STOP_PATTERN}" >/dev/null 2>/dev/null && break
  done
}



### color support ###


set_colors() {
  CF_B="$(tput setaf 0 2>/dev/null)"
  CF_R="$(tput setaf 1 2>/dev/null)"
  CF_G="$(tput setaf 2 2>/dev/null)"
  CF_Y="$(tput setaf 3 2>/dev/null)"
  CF_M="$(tput setaf 5 2>/dev/null)"
  CF_C="$(tput setaf 6 2>/dev/null)"

  CB_R="$(tput setab 1 2>/dev/null)"
  CB_G="$(tput setab 2 2>/dev/null)"
  CB_Y="$(tput setab 3 2>/dev/null)"
  CB_C="$(tput setab 6 2>/dev/null)"

  CX_B="$(tput bold 2>/dev/null)"
  CX_D="$(tput dim 2>/dev/null)"
  CX_C="$(tput sgr0 2>/dev/null)$(tput el 2>/dev/null)"
}



#############################################################




# start main routine
main "${@}"
