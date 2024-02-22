
#############################################################
############# TIBERO OCI IMAGE BUILDER (v1.1) ###############
#############################################################
################## kim.hwiwon@outlook.com ###################
#############################################################

# global args
ARG TB_PACKAGE_DIR
ARG BASE_IMG_REGISTRY="docker.io"
ARG BASE_IMG_TAG="latest"
ARG TB_ACC_NAME="tibero"
ARG TB_ACC_HOME="/opt/${TB_ACC_NAME}"
ARG TB_ACC_UID="999"
ARG TB_ACC_GID="${TB_ACC_UID}"
ARG TB_ACC_PERSIST="${TB_ACC_HOME}"/persistable
ARG TB_ACC_PERSIST_DB="${TB_ACC_PERSIST}"/database
ARG TB_ACC_PERSIST_CONFIG="${TB_ACC_PERSIST}"/config
ARG TB_ACC_PERSIST_DEFAULTS="${TB_ACC_HOME}"/persistable-defaults
ARG TB_ACC_LOCAL_BIN="${TB_ACC_HOME}"/.local/bin
ARG TB_ACC_LOCAL_LIB="${TB_ACC_HOME}"/.local/lib
ARG TB_JDK_VERSION="21"
ARG TB_JDK_HOME="${TB_ACC_HOME}/.local/openjdk-${TB_JDK_VERSION}"
ARG TB_BUILDER_JDK_HOME="/usr/local/openjdk-${TB_JDK_VERSION}"
ARG TB_ACC_FILE="${TB_ACC_PERSIST}/account-list"
ARG TB_CUSTOM_DB_CREATE_SQL="${TB_ACC_PERSIST_CONFIG}/sql/create-db.sql"
ARG TB_CUSTOM_INIT_SQL="${TB_ACC_PERSIST_CONFIG}/sql/init.sql"
ARG TB_HOME="${TB_ACC_HOME}/tibero-home"
ARG TB_SID="tibero"
ARG TB_PORT="8629"
ARG TB_CHARSET="UTF8"
ARG TB_NCHARSET="UTF8"
ARG TB_DBUSER_DATAFILE_COUNT="5"
ARG TB_INIT_HOST_VOL="/mnt"

# args for tip file default envsubst
ARG TB_TOTAL_SHM_SIZE="4G"
ARG TB_MEMORY_TARGET="6G"
ARG TB_MAX_SESSION_COUNT="50"
ARG TB_ACTIVE_SESSION_TIMEOUT="610"




###################### BUILDER (JDK) ########################

FROM ${BASE_IMG_REGISTRY:+${BASE_IMG_REGISTRY}/}openjdk:${TB_JDK_VERSION} AS builder-jdk

RUN mv "$JAVA_HOME" /java-home


######################### BUILDER ###########################

FROM ${BASE_IMG_REGISTRY:+${BASE_IMG_REGISTRY}/}debian:stable-slim AS builder
LABEL org.opencontainers.image.authors="Kim Hwiwon <kim.hwiwon@outlook.com>"



# args
ARG TB_PACKAGE_DIR
ARG TB_ACC_NAME
ARG TB_ACC_HOME
ARG TB_ACC_PERSIST
ARG TB_ACC_PERSIST_DB
ARG TB_ACC_PERSIST_CONFIG
ARG TB_ACC_PERSIST_DEFAULTS
ARG TB_ACC_LOCAL_BIN
ARG TB_ACC_LOCAL_LIB
ARG TB_BUILDER_JDK_HOME
ARG TB_ACC_FILE
ARG TB_CUSTOM_DB_CREATE_SQL
ARG TB_CUSTOM_INIT_SQL
ARG TB_HOME
ARG TB_SID
ARG TB_PORT


# envs
ENV TB_PACKAGE_DIR="${TB_PACKAGE_DIR}"
ENV ASSET="/asset"
ENV TB_ACC_PERSIST="${TB_ACC_PERSIST}"
ENV TB_ACC_PERSIST_DB="${TB_ACC_PERSIST_DB}"
ENV TB_ACC_PERSIST_CONFIG="${TB_ACC_PERSIST_CONFIG}"
ENV TB_ACC_PERSIST_DEFAULTS="${TB_ACC_PERSIST_DEFAULTS}"
ENV TB_ACC_FILE="${TB_ACC_FILE}"
ENV TB_CUSTOM_DB_CREATE_SQL="${TB_CUSTOM_DB_CREATE_SQL}"
ENV TB_CUSTOM_INIT_SQL="${TB_CUSTOM_INIT_SQL}"
ENV TB_DBDIR="${TB_HOME}/database"
ENV TB_LICENSE="${TB_HOME}/license/license.xml"
ENV TB_LICENSE_DEFAULT="${TB_ACC_PERSIST_DEFAULTS}/license.xml"
ENV TB_TIP="${TB_HOME}/config/${TB_SID}.tip"
ENV TB_TIP_TEMPLATE="${TB_HOME}/config/tip.template"
ENV TB_TIP_TEMPLATE_DEFAULT="${TB_ACC_PERSIST_DEFAULTS}/tip.template"
ENV TB_PORT="${TB_PORT}"

# system envs
ENV LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${TB_BUILDER_JDK_HOME}/lib:${TB_BUILDER_JDK_HOME}/lib/server:${TB_HOME}/lib:${TB_HOME}/client/lib"
ENV PATH="$PATH:${TB_BUILDER_JDK_HOME}/bin:${TB_HOME}/bin:${TB_HOME}/client/bin"


# copy initial files
RUN [ -n "${TB_PACKAGE_DIR}" ] || exit 1
ADD "${TB_PACKAGE_DIR}"/*.tar.gz "${TB_ACC_HOME}"
RUN mv "${TB_ACC_HOME}"/tibero[0-9]* "${TB_HOME}"
COPY asset "${ASSET}"


# make and initialize dir for persistable to store persistent data
RUN mkdir -p "${TB_ACC_PERSIST_DEFAULTS}" "${TB_ACC_PERSIST_CONFIG}"/sql "${TB_ACC_PERSIST_CONFIG}"/license "${TB_ACC_PERSIST_CONFIG}"/tip


# link original path to persistable
RUN ln -snf "${TB_ACC_PERSIST_DB}" "${TB_DBDIR}" \
    && ln -snf "${TB_ACC_PERSIST_CONFIG}"/license/license.xml "${TB_LICENSE}"


# place/generate tibero related files/dirs
RUN mkdir -p "${TB_ACC_PERSIST_DB}"
RUN if [ -f "${ASSET}"/init.sql ]; then \
       mv "${ASSET}"/init.sql "${TB_CUSTOM_INIT_SQL}"; \
    fi
RUN if [ -f "${ASSET}"/create-db.sql ]; then \
       mv "${ASSET}"/create-db.sql "${TB_CUSTOM_DB_CREATE_SQL}"; \
    fi
RUN if [ -f "${ASSET}"/license.xml ]; then \
       mv "${ASSET}"/license.xml "${TB_LICENSE_DEFAULT}"; \
    fi
RUN if [ -r "${TB_TIP_TEMPLATE}" ]; then \
       mv "${TB_TIP_TEMPLATE}" "${TB_TIP_TEMPLATE_DEFAULT}" || exit 1; \
    fi; \
    if [ -f "${ASSET}"/tip.template ]; then \
       mv "${ASSET}"/tip.template "${TB_TIP_TEMPLATE_DEFAULT}"; \
    fi



# install required libraries for tibero
RUN apt-get update && \
    apt-get install -y libaio1 procps libncurses5 terminfo gettext-base


# copy necessary libraries for Tibero
COPY ./script-container/copy-deps.sh "/copy-deps.sh"
RUN chmod +x "/copy-deps.sh"
RUN EXCLUDE_PATH="${TB_HOME}" /copy-deps.sh "${TB_ACC_LOCAL_LIB}" "${TB_HOME}"/bin "${TB_HOME}"/client/bin

RUN BIN_LIST="ps tput envsubst"; \
    for bin in ${BIN_LIST}; \
    do \
      BIN_PATH="$(which "${bin}")"; \
      if [ -x "${BIN_PATH}" ]; \
      then \
        printf " - Copying binary '%s' and its dependencies...\n" "${bin}"; \
        EXCLUDE_PATH="${TB_ACC_HOME}" /copy-deps.sh "${TB_ACC_LOCAL_LIB}" "${BIN_PATH}" \
          && mkdir -p "${TB_ACC_LOCAL_BIN}" && cp -afv "${BIN_PATH}" "${TB_ACC_LOCAL_BIN}"/; \
        [ -x "${TB_ACC_LOCAL_BIN}"/"${bin}" ] || exit 1; \
      fi; \
    done

RUN cp -af /usr/lib/terminfo "${TB_ACC_LOCAL_LIB}"/terminfo



# copy jdk
COPY --from=builder-jdk /java-home "${TB_BUILDER_JDK_HOME}"
RUN EXCLUDE_PATH="${TB_BUILDER_JDK_HOME}" /copy-deps.sh "${TB_ACC_LOCAL_LIB}" "${TB_BUILDER_JDK_HOME}"





########################## IMAGE ############################

FROM ${BASE_IMG_REGISTRY:+${BASE_IMG_REGISTRY}/}busybox:${BASE_IMG_TAG}
LABEL org.opencontainers.image.authors="Kim Hwiwon <kim.hwiwon@outlook.com>"



# args
ARG TB_ACC_NAME
ARG TB_ACC_HOME
ARG TB_ACC_UID
ARG TB_ACC_GID
ARG TB_ACC_PERSIST
ARG TB_ACC_PERSIST_DB
ARG TB_ACC_PERSIST_CONFIG
ARG TB_ACC_PERSIST_DEFAULTS
ARG TB_ACC_LOCAL_BIN
ARG TB_ACC_LOCAL_LIB
ARG TB_JDK_HOME
ARG TB_BUILDER_JDK_HOME
ARG TB_ACC_FILE
ARG TB_CUSTOM_DB_CREATE_SQL
ARG TB_CUSTOM_INIT_SQL
ARG TB_HOME
ARG TB_SID
ARG TB_PORT
ARG TB_CHARSET
ARG TB_NCHARSET
ARG TB_DBUSER_DATAFILE_COUNT
ARG TB_INIT_HOST_VOL

ARG TB_TOTAL_SHM_SIZE
ARG TB_MEMORY_TARGET
ARG TB_MAX_SESSION_COUNT
ARG TB_ACTIVE_SESSION_TIMEOUT

# envs
ENV TB_ACC_NAME="${TB_ACC_NAME}"
ENV TB_ACC_HOME="${TB_ACC_HOME}"
ENV TB_ACC_UID="${TB_ACC_UID}"
ENV TB_ACC_GID="${TB_ACC_GID}"
ENV TB_ACC_PERSIST="${TB_ACC_PERSIST}"
ENV TB_ACC_PERSIST_DB="${TB_ACC_PERSIST_DB}"
ENV TB_ACC_PERSIST_CONFIG="${TB_ACC_PERSIST_CONFIG}"
ENV TB_ACC_PERSIST_DEFAULTS="${TB_ACC_PERSIST_DEFAULTS}"
ENV TB_JDK_HOME="${TB_JDK_HOME}"
ENV TB_ACC_FILE="${TB_ACC_FILE}"
ENV TB_CUSTOM_DB_CREATE_SQL="${TB_CUSTOM_DB_CREATE_SQL}"
ENV TB_CUSTOM_INIT_SQL="${TB_CUSTOM_INIT_SQL}"
ENV TB_HOME="${TB_HOME}"
ENV TB_SID="${TB_SID}"
ENV TB_DBDIR="${TB_HOME}/database"
ENV TB_LICENSE="${TB_HOME}/license/license.xml"
ENV TB_LICENSE_DEFAULT="${TB_ACC_PERSIST_DEFAULTS}/license.xml"
ENV TB_TIP="${TB_HOME}/config/${TB_SID}.tip"
ENV TB_TIP_TEMPLATE="${TB_HOME}/config/tip.template"
ENV TB_TIP_TEMPLATE_DEFAULT="${TB_ACC_PERSIST_DEFAULTS}/tip.template"
ENV TB_CHARSET="${TB_CHARSET}"
ENV TB_NCHARSET="${TB_NCHARSET}"
ENV TB_DBUSER_DATAFILE_COUNT="${TB_DBUSER_DATAFILE_COUNT}"
ENV TB_PORT="${TB_PORT}"
ENV TB_INIT_HOST_VOL="${TB_INIT_HOST_VOL}"
ENV TMPSQL="${TB_ACC_HOME}/.tmpsql"

# tip file envsubst envs
ENV TB_TOTAL_SHM_SIZE="${TB_TOTAL_SHM_SIZE}"
ENV TB_MEMORY_TARGET="${TB_MEMORY_TARGET}"
ENV TB_MAX_SESSION_COUNT="${TB_MAX_SESSION_COUNT}"
ENV TB_ACTIVE_SESSION_TIMEOUT="${TB_ACTIVE_SESSION_TIMEOUT}"

# system envs
ENV LD_LIBRARY_PATH="/lib:${TB_JDK_HOME}/lib:${TB_JDK_HOME}/lib/server:${TB_HOME}/lib:${TB_HOME}/client/lib:${TB_ACC_LOCAL_LIB}"
ENV PATH="${TB_ACC_LOCAL_BIN}:${TB_JDK_HOME}/bin:${TB_HOME}/bin:${TB_HOME}/client/bin:/bin:/usr/bin:/sbin:/usr/sbin"
ENV JAVA_HOME="${TB_JDK_HOME}"
ENV TERMINFO="${TB_ACC_LOCAL_LIB}"/terminfo


# initialize user
WORKDIR "${TB_ACC_HOME}"
RUN chown -R "${TB_ACC_UID}":"${TB_ACC_GID}" "${TB_ACC_HOME}"
RUN addgroup -S -g "${TB_ACC_GID}" "${TB_ACC_NAME}"
RUN adduser -S -u "${TB_ACC_UID}" -G "${TB_ACC_NAME}" -h "${TB_ACC_HOME}" -D "${TB_ACC_NAME}"


# make required dirs
RUN mkdir -p "${TB_INIT_HOST_VOL}"


# copy required files from the builder
COPY --chown="${TB_ACC_UID}":"${TB_ACC_GID}" --from=builder "${TB_ACC_HOME}" "${TB_ACC_HOME}"
COPY --chown="${TB_ACC_UID}":"${TB_ACC_GID}" --from=builder "${TB_BUILDER_JDK_HOME}" "${TB_JDK_HOME}"


# generate old compatibilities
RUN ln -snf "$(which true)" "/usr/bin/pstack"
RUN mkdir -p "${TB_HOME}/dev-util"; ln -snf "$(which true)" "${TB_HOME}/dev-util/pstack64"


# remove duplicated libs
RUN for lib in ${TB_ACC_LOCAL_LIB}/*; \
    do if [ -r /lib/"$(basename "${lib}")" ]; then \
        printf " - Removing duplicated library '%s' from the final image...\n" "${lib}"; \
        rm -f "${lib}"; \
    fi; done


# copy necessary scripts to image & set the entrypoint for containers

COPY --chown=0:"${TB_ACC_GID}" ./script-container/copy-tibero-config.sh /bin/copy-tibero-config
RUN chmod 550 /bin/copy-tibero-config

COPY --chown=0:"${TB_ACC_GID}" ./script-container/test-tibero-conn.sh /bin/test-tibero-conn
RUN chmod 550 /bin/test-tibero-conn

COPY --chown=0:"${TB_ACC_GID}" ./script-container/tibero.sh /bin/tibero
RUN chmod 550 /bin/tibero
RUN ln -snf /bin/tibero /entrypoint && chmod 550 /entrypoint
ENTRYPOINT [ "/entrypoint" ]
CMD [ "daemon" ]



# default user
USER "${TB_ACC_NAME}"
