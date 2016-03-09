#!/bin/bash
#title           :backup.sh
#description     :This is a bash backup script for folders and Databases whith history.
#author          :HanzPhoks 
#date            :2015-12-09
#version         :0.2
#usage           :bash backup.sh
#notes           :Change the settings in the "Parameters" section as you need.

# for backupninja
# when = everyday at 02

set -e
startedAt=$(date +%s)

# ------------------------------------
#    parameters that you can change
# ------------------------------------
# list here the folders to backup
foldersToBackup=("/var/www/" "/var/backups/postgres/")

# postgresql only suports localhost witohut password, if you have a solution, please tell me
dbType="postgresql" #mysql or postgresql 
dbHost="localhost"
databases="all" # all or databases names in array like: databases=("dbname1" "dbname2" "dbname3")
exludedDatabases="(Database|information_schema|test)" # useles databases to skip
backupEachDBTable="yes" # if set to yes, it will create a backup file per db table, else it will create a file per database
dbRoot="root" # root or <username> whith sufficient rights

$passwdFile="/root/.p" # you can change the file, this script will automatically change the rights to 400
dbPasswd=$(cat $passwdFile)
chown root $passwdFile
chmod 100 $passwdFile

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

# Fichiers log
if [ -s $logFile ]; then rm $logFile; else touch $logFile; fi
if [ -s $debugLogFile ]; then rm $debugLogFile; else touch $debugLogFile; fi
if [ -s $errorLogFile ]; then rm $errorLogFile; else touch $errorLogFile; fi
exec >> $debugLogFile
exec 2>> $errorLogFile

# creation des dossiers
if [ ! -s $localBackupFolder ];then mkdir $localBackupFolder;fi
if [ ! -s $remoteBackupFolder ];then mkdir $remoteBackupFolder;fi

echo "Starting backup of $dbType databases" > $logFile
#db backup
case $dbType in
    "mysql")
            mkdir "/tmp/mysql"
            foldersToBackup+=("/tmp/mysql/")
            if [ $databases = "all" ] ;then 
                    databases=$(mysql -u $dbRoot -p$dbPasswd -h $dbHost -e "show databases;" | tr -d "|" | grep -Ev "$exludedDatabases")
            fi
            for db in $databases; do
                    if [ $backupEachDBTable = "yes" ]; then
                            tables=$(mysql -u $dbRoot -p$dbPasswd -h $dbHost $db -e "show tables;" | tr -d "|" | grep -v "Tables")
                            for table in $tables; do 
                                    mysqldump --opt -u $dbRoot -p$dbPasswd -h $dbHost $db $table > /tmp/mysql/${db}/${table}.sql
                            done
                    else
                            mysqldump --opt -u $dbRoot -p$dbPasswd -h $dbHost $db > /tmp/mysql/${db}.sql
                    fi
            done
            ;;
    "postgresql")
        mkdir "/tmp/postgresql"
        foldersToBackup+=("/tmp/postgresql/")
        if [ $databases = "all" ] ;then
            databases=$(psql -At -c "select datname from pg_database where not datistemplate and datallowconn;" postgres $dbRoot)
        fi

        for db in $databases
        do
            if 
            if ! pg_dump -Fp "$db" | gzip > $dossier_sauvegarde"$db".sql.gz.in_progress; then
                echo $date" --> !! Sauvegarde de $db incomplète, voir $dossier_sauvegarde"$db".sql.gz.in_progress" >> $fichier_log
            else
                mv $dossier_sauvegarde"$db".sql.gz.in_progress $dossier_sauvegarde"$db".sql.gz
                echo $date" --> Sauvegarde de la base $db complète, voir $dossier_sauvegarde"$db".sql.gz" >> $fichier_log
            fi
        done
        for db in $databases; do
            if [ $backupEachDBTable = "yes" ]; then
                tables=$(mysql -u $dbRoot -p$dbPasswd -h $dbHost $db -e "show tables;" | tr -d "|")
                for table in $tables; do
                    mysqldump --opt -u $dbRoot -p$dbPasswd -h $dbHost $db $table > /tmp/mysql/${db}/${table}.sql
                done
            else
                    mysqldump --opt -u $dbRoot -p$dbPasswd -h $dbHost $db > /tmp/mysql/${db}.sql
            fi
        done
        ;;
    *)
        echo "Error: unsuported database type. Please change the dbType parameter." >> $errorLogFile
        ;;
esac

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
