# `asset` Directory
Place files here to make them the default configs of the built Tibero image.

- `license.xml`: Tibero license file


- (Optional) `account-list`: Tibero user ID/password list file
  - Format of each line in this file: `<user-id>[.<user-tablespace>]/(user-password)`  
    e.g.)
    ```
    user1/password1
    user2/other-password-2
    user3.custom_user3_tablespace/pass3
    ```
  - If this file does not exist on initialization stage,
    the user is prompt to enter one or more username, password, and tablespace when the initialization starts

- (Optional) `create-db.sql`: Tibero initial DB creation SQL query file
  - This SQL script is executed on initialization stage, but only when no data exists inside the volume > `database` dir.  
    If the volume already contains DB data, this script is ignored.

- (Optional) `init.sql`: Tibero initialization SQL query file, after the DB creation
  - This SQL script is executed on initialization stage, but only when no data exists inside the volume > `database` dir.  
    If the volume already contains DB data, this script is ignored.

- (Optional) `tip.template`: Custom configuration template, used when generation `${TB_SID}.tip` config file
  - Default value of `${TB_SID}` is `tibero`, if the environment variable is not set during the img build step.
  - e.g.)
    ```
    DB_NAME=@SID@
    LISTENER_PORT=@PORT@
    \#CONTROL_FILES="@HOME@/database/@SID@/c1.ctl"
    \#CERTIFICATE_FILE="@HOME@/config/tb_wallet/@SID@.crt"
    \#PRIVKEY_FILE="@HOME@/config/tb_wallet/@SID@.key"
    \#WALLET_FILE="@HOME@/config/tb_wallet/WALLET"
    \#ILOG_MAP="@HOME@/config/ilog.map"

    TOTAL_SHM_SIZE=4G
    MEMORY_TARGET=8G

    MAX_SESSION_COUNT=50
    ACTIVE_SESSION_TIMEOUT=610
    ```

- (Optional) `${TB_SID}.tip`: Custom configuration, which replaces default `${TB_SID}.tip` file.
  - Default value of `${TB_SID}` is `tibero`, if the environment variable is not set during the img build step.
  - E.g.) `tibero.tip`:
    ```
    DB_NAME=tibero
    LISTENER_PORT=8629
    CONTROL_FILES="/opt/tibero/tibero-home/database/tibero/c1.ctl"
    #CERTIFICATE_FILE="/opt/tibero/tibero-home/config/tb_wallet/tibero.crt"
    #PRIVKEY_FILE="/opt/tibero/tibero-home/config/tb_wallet/tibero.key"
    #WALLET_FILE="/opt/tibero/tibero-home/config/tb_wallet/WALLET"
    #ILOG_MAP="/opt/tibero/tibero-home/config/ilog.map"

    TOTAL_SHM_SIZE=4G
    MEMORY_TARGET=8G

    MAX_SESSION_COUNT=50
    ACTIVE_SESSION_TIMEOUT=610
    ```
