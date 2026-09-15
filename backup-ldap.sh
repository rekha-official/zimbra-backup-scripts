#!/bin/bash

set -o pipefail

## Configuration
SCRIPT_BASE="/opt/zimbra/script"
CONFIG="${SCRIPT_BASE}/rkp.cf"
BACKUP_BASE="/opt/zimbra/backup/ldap-backup"
LOG_DIR="${SCRIPT_BASE}/log"
LOG_FILE="${LOG_DIR}/backup-ldap.log"

## Check Telegram Config
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Telegram config not found: $CONFIG"
    exit 1
fi

## Load Configuration
if ! source "$CONFIG"; then
    echo "[ERROR] Failed to load configuration: $CONFIG"
    exit 1
fi

## Create Folder Log
if [ ! -d $LOG_DIR ]; then
	mkdir -p "$LOG_DIR"
fi

## Logging
exec >> "$LOG_FILE" 2>&1

## Sent Notification
send_telegram() {
    curl -s \
    	--connect-timeout "$CONNECT_TIMEOUT" \
    	--max-time "$MAX_TIME" \
    	--retry "$RETRY" \
    	--retry-delay "$RETRY_DELAY" \
    	-X POST "$URL" \
    	-d "chat_id=${CHAT_ID}" \
    	-d "parse_mode=HTML" \
    	--data-urlencode "text=$1" \
    	>/dev/null

    return $?
}

## Host & Date
HOST=$(hostname -f)
DATE=$(date +"%d%m%Y")
START_TIME=$(date +"%H:%M:%S")

## Folder Backup Location
DUMPDIR=${BACKUP_BASE}/ldap-${DATE}

## Create Backup Directory
if [ ! -d $DUMPDIR ]; then
	mkdir -p $DUMPDIR
	chown zimbra:zimbra "$DUMPDIR"
	chmod 750 "$DUMPDIR"
	echo "[INFO] Berhasil membuat folder backup: ${DUMPDIR}"
else
	echo "[ERROR] Gagal membuat folder backup: ${DUMPDIR}"
	send_telegram "[ERROR] Gagal membuat folder backup atau folder sudah ada"
fi

echo "[INFO] Host        : $HOST"
echo "[INFO] backup Dir. : $DUMPDIR"
echo "[INFO] Start Time  : $START_TIME"

## Proses backup ldap

BACKUP_STATUS=0

echo "[INFO] Running zmslapcat..."
if ! su - zimbra -c "/opt/zimbra/libexec/zmslapcat '${DUMPDIR}'"; then
	echo "[ERROR] zmslapcat failed"
	BACKUP_STATUS=1
fi

echo "[INFO] Running zmslapcat -c..."
if ! su - zimbra -c "/opt/zimbra/libexec/zmslapcat -c '${DUMPDIR}'"; then
	echo "[ERROR] zmslapcat -c failed"
	BACKUP_STATUS=1
fi

echo "[INFO] Running zmslapcat -a..."
if ! su - zimbra -c "/opt/zimbra/libexec/zmslapcat -a '${DUMPDIR}'"; then
	echo "[ERROR] zmslapcat -a failed"
	BACKUP_STATUS=1
fi

## Hasil backup
END_TIME=$(date +'%H:%M:%S')

if [ "$BACKUP_STATUS" -eq 0 ]; then
	echo "[SUCCESS] Ldap backup completed.."
	echo "[INFO] End Time : ${END_TIME}"
	
	send_telegram \
		"<b>[LDAP BACKUP]</b>
		<pre>
		Host       : ${HOST}
		Status     : FINISHED
		Start Time : ${START_TIME}
		End Time   : ${END_TIME}
		Backup     : $DUMPDIR</pre>"

else
	echo "[ERROR] LDAP backup failed..."
	echo "[INFO] End Time : ${END_TIME}"
	send_telegram "[LDAP BACKUP]: ${HOST} [FAILED] at ${END_TIME}"

fi

##Menghapus folder backup ldap lebih dari 7 hari
find "$BACKUP_BASE" \
	-mindepth 1 \
	-maxdepth 1 \
	-type d \
	-name "ldap-*" \
	-mtime +7 \
	-print \
	-exec rm -rf {} +;

exit "$BACKUP_STATUS"
