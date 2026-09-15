#!/bin/bash

set -o pipefail

## Konfigurasi
DATE=$(date +"%d%m%y")
SCRIPT_BASE="/opt/zimbra/script"
CONFIG="${SCRIPT_BASE}/rkp.cf"
BACKUP_BASE="/opt/zimbra/backup"
BACKUP_DIR="${BACKUP_BASE}/mailbox-backup"
DUMPDIR="${BACKUP_DIR}/mailbox_full-$DATE"
LOG_DIR="${SCRIPT_BASE}/log"
LOG_FILE="${LOG_DIR}/mailbox_full_backup.log"
HOST=$(hostname -f)
FORMAT=tgz

## Cek konfigurasi Telegram
if [ ! -f "$CONFIG" ]; then
    echo "[ERROR]: Konfigurasi Telegram tidak ditemukan: $CONFIG"
    exit 1
fi

## Memuat Telegram
if ! source "$CONFIG"; then
    echo "[ERROR]: Gagal memuat konfigurasi: $CONFIG"
    exit 1
fi

## Fungis Kirim Notifikasi ke Telegram
send_telegram() {
    curl -s \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    --retry "$RETRY" \
    --retry-delay "$RETRY_DELAY" \
    -X POST "$URL" \
    -d "chat_id=${CHAT_ID}" \
    -d "parse_mode=HTML" \
    --data-urlencode "text=$1" >/dev/null
}

## Fungsi untuk mencatat log
write_log() {
        echo "$(date +"%Y%m%d_%H:%M:%S") : $1" >> "$LOG_FILE"
}

## zmmailbox location
ZMBOX=/opt/zimbra/bin/zmmailbox

## Cek kapasitas disk
FREE_SPACE=$(df -BG "$BACKUP_BASE" | awk 'NR==2 {gsub("G","",$4); print $4}')
if [ "$FREE_SPACE" -lt 20 ]; then
    send_telegram "[INFO]: Backup dibatalkan karena Free space tersisa ${FREE_SPACE}GB."
    exit 1
fi

START_TIME=$(date +"%H:%M:%S")

### Backup Option ###
if [ ! -d "$DUMPDIR" ]; then
    mkdir -p "$DUMPDIR"
    chown zimbra:zimbra "$DUMPDIR"
fi

## Kirim Notifikasi Telegram Saat Mulai & Catat Ke Log
write_log "[INFO]: Full Mailbox Backup [STARTED]..."

## Looping Account Zimbra
for account in $(su - zimbra -c "zmprov -l gaa -s ${HOST}")
 do
   echo "Processing mailbox $account backup..."
   ## Mencatat progress akun yang sedang dibackup ke file log
   write_log "[INFO]: Processing mailbox $account backup..."

   if $ZMBOX -z -m $account getRestURL "//?fmt=${FORMAT}" > "$DUMPDIR/$account.${FORMAT}"
   then
        write_log "${account}"
    else
        write_log "${account}"
    fi
 done

END_TIME=$(date +"%H:%M:%S")
 echo "[INFO]: Full Mailbox Backup [FINISHED]..."

## Kirim notifikasi Telegram saat selesai dan catat ke log
write_log "[INFO]: Full Mailbox Backup [FINISHED]..."
send_telegram \
"<b>[FULL MAILBOX BACKUP]</b>
<pre>
Hostname      : ${HOST}
Status        : FINISHED
Start Time    : ${START_TIME}
End Time      : ${END_TIME}
Backup Folder : ${DUMPDIR}
</pre>"

## Pembersihan data lama yang lebih dari 30 hari
find "$DUMPDIR" \
    -maxdepth 1 \
    -type d \
    -name "mailbox_full*" \
    -mtime +30 \
    -exec rm -rf {} \;
