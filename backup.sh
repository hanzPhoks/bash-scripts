#!/bin/bash
# when = everyday at 02
# for backupninja

set -e
startedAt=$(date +%s)

# ------------------------------------
#    parameters that you can change
# ------------------------------------
# list here the folders to backup
foldersToBackup=("/var/www/" "/var/backups/postgres/")
localBackupFolder="/var/backups/history"
remoteBackupFolder="/mnt/nas/history"
logFile="/var/log/backup.log"
debugLogFile="/var/log/backup-debug.log"
errorLogFile="/var/log/backup-error.log"
keepLocalBackups=10
keepRemoteBackups=10
emailTo="jar@cesncf-stra.org"
emailLogs="always"
# debug always error
# debug will send the whole debug log
# always will only send a short text on sucess or failure
# error will only send if the script failed

backupFolderName="backup-$(hostname -f)-$(date +%d-%m-%Y-%H:%M:%S)"
backupFolderFullName="$localBackupFolder/$backupFolderName"
# ------------------------------------
#  End of parameters
# ------------------------------------


# ------------------------------------
# Script
# ------------------------------------

# Fichier log
if [ -s $logFile ]; then rm $logFile; else touch $logFile; fi
if [ -s $debugLogFile ]; then rm $debugLogFile; else touch $debugLogFile; fi
if [ -s $errorLogFile ]; then rm $errorLogFile; else touch $errorLogFile; fi

exec >> $debugLogFile
exec 2>> $errorLogFile

# creation des dossiers
if [ ! -s $localBackupFolder ];then mkdir $localBackupFolder;fi
if [ ! -s $remoteBackupFolder ];then mkdir $remoteBackupFolder;fi

echo "Starting backup of ${foldersToBackup[@]}" > $logFile

# copie des dossiers a sauvegarder
for folder in "${foldersToBackup[@]}"; do
        echo "Copying $folder " >> $logFile
        cp -v -R -- $folder $backupFolderFullName
done

# Compressing, copy to to remote and remove
echo "Compressing to $backupFolderFullName.tar " >> $logFile
tar -cvf "$backupFolderFullName.tar" -C "$backupFolderFullName/" .
echo "Copying to the NFS mounted NAS " >> $logFile
cp -v "$backupFolderFullName.tar" $remoteBackupFolder
echo "Removing the folder $backupFolderFullName " >> $logFile
rm -v -rf $backupFolderFullName

# Removing old files
echo "Removing the archives older than $keepRemoteBackups days on NAS storage " >> $logFile
files=($(find $remoteBackupFolder -mtime +$keepRemoteBackups))
rm -rfv "${files[@]}"
echo "Removing the archives older than $keepLocalBackups days on local storage " >> $logFile
files=($(find $localBackupFolder -mtime +$keepLocalBackups))
rm -rfv "${files[@]}"


# Time of execution
endedAt=$(date +%s)
executionTime=$(echo $endedAt-$startedAt | bc )

if [  $executionTime -gt 60 ]; then
        minutes=$(echo $executionTime / 60 | bc)
        seconds=$(echo $executionTime % 60 | bc)
        echo "The script took $minutes minutes and $seconds seconds " >> $logFile
        echo "The script took $minutes minutes and $seconds seconds " >> $debugLogFile
else
        echo "The script took $executionTime seconds " >> $logFile
        echo "The script took $executionTime seconds " >> $debugLogFile
fi

case $emailLogs in
"debug")
        cat $errorLogFile $debugLogFile | mail -s "Backup debug result from $(hostname -f)" $emailTo;;
"always")
        cat $logFile | mail -s "Backup result from $(hostname -f)" $emailTo;;
"error")
        if [ -s $errorLogFile ]; then cat $errorLogFile | mail -s "An error occured while backup at $(hostname -f)" $emailTo; fi;;
*)
        echo "You may have a configuration error in the backup script parameters. Please check the emailLog parameter" | mail -s "Backup for srvwan error log" $emailTo;;
esac

set +e
