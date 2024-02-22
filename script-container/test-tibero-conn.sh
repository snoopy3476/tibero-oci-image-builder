#!/bin/sh

RAND_STR="$(tr -cd '[:alnum:]' < /dev/urandom | head -c63)"

printf "select 'TIBERO_RUNNING_%s' from dual;\n" "${RAND_STR}" | tbsql / | grep -q "TIBERO_RUNNING_${RAND_STR}" >/dev/null 2>/dev/null || false
