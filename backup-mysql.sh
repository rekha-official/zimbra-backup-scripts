##!/bin/bash

set -o pipefail

## Configuration
SCRIPT_BASE="/opt/zimbra/script"
CONFIG="${SCRIPT_BASE}/rkp.cf"
BACKUP_BASE="/opt/zimbra/backup/mysql-backup"
LOG_DIR="${SCRIPT_BASE}/log"
LOG_FILE="${LOG_DIR}/mysql-backup.log"

## Check user
if [ "$(whoami)" != "zimbra" ];then
	echo "Error: Script ini harus dijalankan sebagai user zimbra."
	exit 1
fi

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

## Cek Folder Log
if [ ! -d $LOG_DIR ]; then
	echo "[INFO]: Folder $LOG_DIR belum ada.."
	exit 1
fi

## eksekusi ke file log
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
    	-d parse_mode="HTML" \
    	--data-urlencode "text=$1" \
		>/dev/null

	return $?
}

## Load MySQL
source ~/bin/zmshutil ;
zmsetvars

## Folder name for backup and using date
DATE=$(date +"%d%m%y")

## Host
HOST=$(hostname -f)

## Backup location separate by date
DUMPDIR=${BACKUP_BASE}/mysql-$DATE

### Backup Option ###
if [ ! -d $DUMPDIR ]; then
   mkdir -p $DUMPDIR
   chown zimbra:zimbra
fi

START_TIME=$(date +"%H:%M:%S")

## List Database
/opt/zimbra/bin/mysql --batch --skip-column-names -e "show databases" | grep -e mbox -e zimbra -e chat > $DUMPDIR/mysql.db.list;

## Starting Backup MySQL
# Old Version
#for db in `cat $DUMPDIR/mysql.db.list`; do
#	~/common/bin/mysqldump $db -S $mysql_socket -u root --password=$mysql_root_password > $DUMPDIR/$db.sql;
#	echo "Dumped $db";
#done

# New Version
BACKUP_STATUS="SUCCESS"

while read -r db; do
	if ! ~/common/bin/mysqldump \
		"$db" \
		-S "$mysql_socket" \
		-u root \
		--password="$mysql_root_password" \
		> "$DUMPDIR/$db.sql"
	then
		BACKUP_STATUS="FAILED"
	fi
		echo "Dumped $db";
done < "$DUMPDIR/mysql.db.list"

END_TIME=$(date +"%H:%M:%S")
send_telegram \
"<b>[MYSQL BACKUP]</b>
<pre>
Host       : $HOST
Status     : $BACKUP_STATUS
Start Time : ${START_TIME}
End Time   : ${END_TIME}
Backup     : $DUMPDIR
</pre>"

## Pembersihan data backup yang lebih dari 7 hari
find "$BACKUP_BASE" \
	-mindepth 1 \
	-maxdepth 1 \
	-type d \
	-name "mysql-*" \
	-mtime +7 \
	-print \
	-exec rm -rf {} +
