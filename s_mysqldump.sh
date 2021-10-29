#!/bin/bash
#
# Filename: s_mysqldump.sh V 3.0
#
# Created: 21/10/2021 (07:52:49)
# Created by: Lorenzo Saibal Forti <lorenzo.forti@gmail.com>
#
# Last Updated: 24/10/2021 (13:27:13)
# Updated by: Lorenzo Saibal Forti <lorenzo.forti@gmail.com>
#
# Comments: bash 4 required
#
# Copyleft: 2021 - Tutti i diritti riservati
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#=====================================================================

#=====================================================================
# CHANGELOG
#=====================================================================
# Versione 3.0
# Code refactoring

# Versione 2.1
# Code refactoring

# Versione 2.0
# Creazione funzione controllo cartelle
# Creazione funzione email per supportare anche ssmtp
# Ottimizzazione del codice per renderlo più leggero (eliminato un ciclo di dump e compress)
# Gestione più leggera dei log

# Versione 1.1
# Separazione funzioni dump e compressione
# Aggiunti controlli sulla creazione delle cartelle e dei file
# Sostituzione funzione touch con echo -e per la creazione del file di log
# Sostituzione del comando LET per le operazioni di incremento contatori
# Rivisitazione generale del codice

# Versione 1.0
# Aggiunto invio log per email
# Controllo generale del codice
#
# Versione 0.5
# Aggiunto backup giornaliero
# Aggiunto backup mensile
# Aggiunta registrazione dei log

#=====================================================================
# Promemoria
#=====================================================================
# 1) nelle operazioni per aumentare i contatori potrei usare il comando "let". Es.: 'let CONTA++' aumenta di 1 il contatore
# Si però tratta di un "bashismo" che non mi assicura la compatibilità su altre shell.
# Per questo motivo utilizzo l'espasione classica. Es.: CONTA=$(( CONTA + 1 )).
#
# 2) Per creare un file potrei usare "touch" ma per avere un corretto return-code ($?) se esiste una dir
# con lo stesso nome uso 'echo -n'.

#=====================================================================
# General config
# Configurazione generale
#=====================================================================
# db host. e.g.: localhost
DBHOST='localhost'

# db username
USERNAME=''

# db password
PASSWORD=''

# login path
MYSQL_LOGIN_PATH='my_personal_sqldump'

# a space separated list of db to dump
# lista dei database da salvare (separati da spazio)
DATABASES='mysql my_db my_other_db'

# working directory where to store backup folders (no trailing slash). check r/w permissions for the user
# directory dove salvare i backup (senza slash finale). controllare i permessi di scrittura sulla cartella
OUT_DIR='/var/local/backup'

# data format (it or en)
# formato data (it oppure en)
DATE_FORMAT='it'

# "last backup" folder name
# cartella ultimo backup
LAST_FOLDER='last'

# daily backup? (y or n)
# backup giornaliero? (y oppure n)
DAILY_BACKUP='y'

# "daily backup" folder name. check r/w permissions for the user
# cartella backup giornalieri. controllare i permessi di scrittura sulla cartella
DAILY_FOLDER='daily'

# daily backup? (y or n)
# backup mensile? (y oppure n)
MONTHLY_BACKUP='y'

# "monthly backup" folder name. check r/w permissions for the user
# cartella backup mensili. controllare i permessi di scrittura sulla cartella
MONTHLY_FOLDER='monthly'

# day of month of monthly backup (e.g. 01 02 03 ... 29 30 31). usefull if crontab runs every day
# giorno del mese in cui effettuare il backup mensile (formato 01, 02, 03, etc)
MONTHLY_BKDAY='01'

#=====================================================================
# Log Configuration
# Configurazione logs
#=====================================================================
# save log? (y or n)
# registrazione dei log? (y oppure n)
LOGS_REC='y'

# directory where to store log files. if empty value, it uses backup's directory (no trailing slash).
# directory dove salvare i LOG. Se lasciata vuota sarà la stessa dei backup (senza slash finale).
LOGS_DIR='/var/local/custom_scripts_log'

# log folder name. check r/w permissions for the user
# cartella dei LOG. controllare i permessi di scrittura sulla cartella
LOGS_FOLDER='[log]'

# log filename
# nome del file di LOG
LOGS_FILENAME='mysqldump.log'

# max size of the log file (in KB)
# dimensione massima del file di log (in KB)
LOGS_MAXSIZE='900'

#=====================================================================
# Email configuration
# Configurazione invio email
#=====================================================================
# enable email service as notification? (y or n)
# abilitare invio email con risultato delle operazioni? (y oppure n)
EMAIL_SEND='y'

# enable email only for errors? (y or n)
# inviare email solo in caso di errore? (y oppure n)
EMAIL_ONLYERRORS='y'

# email service. usually I use "ssmtp". try with "smtp" or another service but I don't guarantee
# programma da utilizzare
EMAIL_SERVICE='ssmtp'

# email recipient
# destinatario email
EMAIL_RECIVER='myemail@gmail.com'

# email subject
# soggetto email
EMAIL_SUBJECT='MySQL Backup - Report'

#=====================================================================
# Messages configuration
# Configurazione messaggi
#=====================================================================
# result messages writed in log files. NOMEDB is a placeholder.
# messaggi di ritorno per il backup (IP e NOMEDB sono placeholder)
BACKUP_OK="BACKUP RIUSCITO! | IP | Tutti i backup effettuati con successo"
BACKUP_KO="ERRORE BACKUP!   | IP | I seguenti database: NOMEDB non sono stati copiati e/o compressi"
CONNEC_KO="ERRORE MYSQL!    | IP | Impossibile connettersi ai seguenti database: NOMEDB"
DELETE_KO="ERRORE RIMOZIONE!| IP | Impossibile rimuovere il file SQL per NOMEDB"
SEMAIL_KO="ERRORE INVIO!    | IP | Impossibile trovare il servizio $EMAIL_SERVICE per inviare messaggi"

########################################
# NOTHING TO EDIT
# NIENTE DA MODIFICARE
########################################

# di default hostname utilizza il trattino come separatore. cambio con il punto
IP=$(hostname -I | cut -d ' ' -f1)

BACKUP_OK=${BACKUP_OK//IP/$IP}
BACKUP_KO=${BACKUP_KO//IP/$IP}
CONNEC_KO=${CONNEC_KO//IP/$IP}
DELETE_KO=${DELETE_KO//IP/$IP}
SEMAIL_KO=${SEMAIL_KO//IP/$IP}

#=========================================
# FUNZIONI VARIE
#=========================================
# crea una cartella. $1 è il nome della cartella
create_folder() {

	# controllo l'esistenza della cartella
	if [ ! -d "$1" ]
	then

		if ! mkdir -p "$1" > /dev/null 2>&1
		then

			echo "Errore nel creare la cartella \"$1\". Controllare che non esista un file/directory con lo stesso nome"
			exit
		fi
	fi
}

# check connessione al db. $1 è il nome del db
check_connection() {

	# testo la connessione
	if [ ! -z "$MYSQL_LOGIN_PATH" ]
	then

		mysql --login-path="$MYSQL_LOGIN_PATH" "$1" -e STATUS > /dev/null 2>&1

	else

		mysql --user="$USERNAME" --password="$PASSWORD" --host="$DBHOST" "$1" -e STATUS > /dev/null 2>&1
	fi

	# id errore
	CONN_ERROR=$?

	return $CONN_ERROR
}

# effettua il dump al db. $1 è il nome del db. $2 è il path con nome del file come output
do_mysqldump() {

	# dump del database
	if [ ! -z "$MYSQL_LOGIN_PATH" ]
	then

		mysqldump --login-path="$MYSQL_LOGIN_PATH" "$1" > "$2"
	
	else

		mysqldump --user="$USERNAME" --password="$PASSWORD" --host="$DBHOST" "$1" > "$2"	
	fi

	# registro il risultato dell'operazione mysqldump.
	DUMP_ERROR=$?

	return $DUMP_ERROR
}

# effettua la compressione del file o folder passato come parametro $1. $2 è il nome output del file. in questo è necessario cancellare manualmente l'input
# gzip è più adatto ai singoli file sql. tar per default mantiene la struttura delle directory e non rimuove il file originario (solo con param --remove-files)
create_archive() {

	# comprimo il tutto con gzip
	gzip -f -c "$1" > "$2"

	#risultato operazione
	ARCHIVE_ERROR=$?

	return $ARCHIVE_ERROR
}

# funzione per check invio email
check_email_service() {

	if [ "${EMAIL_SEND,,}" = 'y' ]
	then

		CHECK_MAIL=$(command -v "$EMAIL_SERVICE")

		if [ -n "$CHECK_MAIL" ]
		then
			MAIL_RESULT=1
		else
			MAIL_RESULT=0
			# aumento il contatore
			ERROR_NOMAIL_SERVICE=$(( ERROR_NOMAIL_SERVICE + 1 ))
		fi

	else
		MAIL_RESULT=0
	fi

	return $MAIL_RESULT
}

# funzione per inviare email | eliminato il campo From: per problemi con google come proxy. anche il campo To va tolto
# $1 $EMAIL_SERVICE | $2 $EMAIL_RECIVER | $3 SOGGETTO | $4 $EMAIL_MSG
send_mail() {

	# alternativa
	echo -e "From: sh-script\nSubject: $3\n\n$4" | "$1" "$2"
}

#=========================================
# VARIABILI
#=========================================
# path principali del sistema
PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/mysql/bin:/usr/sbin

# estensione per il file compresso. senza punto iniziale
ARCHIVE_EXT='gz'

# data di oggi
TODAY_DATE=$(date +%d/%m/%Y)

# ora di oggi
TODAY_TIME=$(date +%T)

# giorno della settimana (1 Lunedì, 2 Martedì, 3 Mercoledì etc etc)
NDAY=$(date +%u)

# giorno del mese (formato 01, 02, 03, etc)
DMON=$(date +%d)

# mese
MON=$(date +%m)

# mese - anno
MONYEA=$(date +%m_%Y)

# date esecuzione backup nei due formati
DATEIT=$(date +\[%d-%m-%Y_%H:%M:%S\])
DATEEN=$(date +\[%Y-%m-%d_%H:%M:%S\])

# formato data per i log
LOGDATE="$(date +%Y/%m/%d) - $(date +%T)"

# contatori di errori
ERROR_DB_CONN=0
ERROR_REMOVE_DUMP=0
ERROR_COUNT_SINGLE=0
ERROR_COPY=0
ERROR_NOMAIL_SERVICE=0

# se non esiste la directory LAST la creo
create_folder "$OUT_DIR/$LAST_FOLDER"

# se non esiste la directory DAILY la creo
if [ "$DAILY_BACKUP" = 'y' ]
then
	create_folder "$OUT_DIR/$DAILY_FOLDER"
fi

# se non esiste la directory MONTHLY la creo
if [ "${MONTHLY_BACKUP,,}" = 'y' ]
then
	create_folder "$OUT_DIR/$MONTHLY_FOLDER"
fi

# scelgo la formattazione della data
if [ "${DATE_FORMAT,,}" = 'it' ]
then
	DATE="$DATEIT"
else
	DATE="$DATEEN"
fi

# se sono abilitati i logs e non esiste la directory LOGS la creo e calcolo la dimensione massima del file
if [ "${LOGS_REC,,}" = 'y' ]
then

	# se la variabile LOGS_DIR è vuota inserisco la cartella dentro la directory di default
	if [ -z "$LOGS_DIR" ]
	then
		LOGS_DIR="$OUT_DIR"
	fi

	# creo la directory log
	create_folder "$LOGS_DIR/$LOGS_FOLDER"

	# creo il file di log
	if [ ! -f "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME" ]
	then
		echo -ne > "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
	fi

	# converto i KB in BYTES dopo aver controllato che la VAR non sia vuota
	if [ -n "$LOGS_MAXSIZE" ]
	then
		LOGS_MAXBYTES=$(( LOGS_MAXSIZE*1000 ))
	else
		LOGS_MAXBYTES=$(( 1000*1000 ))
	fi
fi

#=========================================
# START BACKUP NOW!!!
#=========================================

# Controllo l'invio delle email. ritorna $MAIL_RESULT
check_email_service

# inizio il ciclo sui database
for db in $DATABASES
do

	# funzione per testare la connessione al database. ritorna $CONN_ERROR
	check_connection "$db"

	if [ "$CONN_ERROR" -eq 0 ]
	then

		########################################
		# BACKUP LAST
		########################################

		# rimuovo i vecchi backup
		rm -f "$OUT_DIR/$LAST_FOLDER/${db}__[last]"*".${ARCHIVE_EXT}"

		# nome file sql
		OUTFILE_DUMP="$OUT_DIR/$LAST_FOLDER/${db}__${DATE}.sql"

		# nome file gzip
		LASTFILE_ARCHIVE="$OUT_DIR/$LAST_FOLDER/${db}__[last]__${DATE}.${ARCHIVE_EXT}"

		# faccio il dump e lo sbatto nel file sql. ritorna $DUMP_ERROR
		do_mysqldump "$db" "$OUTFILE_DUMP"

		# creo lo gzip rinominandolo
		create_archive "$OUTFILE_DUMP" "$LASTFILE_ARCHIVE"

		# se la compressione è ok copio l'ultimo gzip dentro la dir DAILY e MONTHLY
		if [ "$ARCHIVE_ERROR" -eq 0 ]
		then

			########################################
			# BACKUP GIORNALIERO
			########################################
			if [ "${DAILY_BACKUP,,}" = 'y' ]
			then

				# rimuovo i vecchi backup
				rm -f "$OUT_DIR/$DAILY_FOLDER/${db}__[day-${NDAY}]"*".${ARCHIVE_EXT}"

				# uso la funzione cp per copiare l'ultimo back dalla cartella "last" a "daily"
				cp "$LASTFILE_ARCHIVE" "$OUT_DIR/$DAILY_FOLDER/${db}__[day-${NDAY}]__${DATE}.${ARCHIVE_EXT}"

				# se le copia ha generato errori e i log sono attivi
				if [ $? -ne 0 ] && [ "${LOGS_REC,,}" = 'y' ]
				then

					# aumento il contatore
					ERROR_COPY=$(( ERROR_COPY + 1 ))

					# registro i DB nella stessa variabile
					ERROR_RESULT+="[${db}__day-${NDAY}] "
				fi
			fi

			########################################
			# BACKUP MENSILE
			########################################
			if [ "${MONTHLY_BACKUP,,}" = 'y' ] && [ "$DMON" = "$MONTHLY_BKDAY" ]
			then

				# rimuovo i vecchi backup
				rm -f "$OUT_DIR/$MONTHLY_FOLDER/${db}__[month-${MON}_"*".${ARCHIVE_EXT}"

				# uso la funzione cp per copiare l'ultimo back dalla cartella "last" a "daily"
				cp "$LASTFILE_ARCHIVE" "$OUT_DIR/$MONTHLY_FOLDER/${db}__[month-${MONYEA}]__${DATE}.${ARCHIVE_EXT}"

				# se le copia ha generato errori e i log sono attivi
				if [ $? -ne 0 ] && [ "${LOGS_REC,,}" = 'y' ]
				then

					# aumento il contatore
					ERROR_COPY=$(( ERROR_COPY + 1 ))

					# registro i DB nella stessa variabile
					ERROR_RESULT+="[${db}__month-${MONYEA}] "
				fi
			fi
		fi

		# rimuovo il file dump originario
		if ! rm "$OUTFILE_DUMP"
		then

			# aumento il contatore
			ERROR_REMOVE_DUMP=$(( ERROR_REMOVE_DUMP + 1 ))

			# registro i DB nella stessa variabile
			ERROR_RESULT+="[${db}__last.sql] "
		fi

		# uso le VAR di ritorno delle funzioni per gestire gli errori nei log se abilitati
		if [ "${LOGS_REC,,}" = 'y' ]
		then

			if [ "$DUMP_ERROR" -ne 0 ] || [ "$ARCHIVE_ERROR" -ne 0 ]
			then

				# aumento il contatore
				ERROR_COUNT_SINGLE=$(( ERROR_COUNT_SINGLE + 1 ))

				# registro i DB nella stessa variabile
				ERROR_RESULT+="[${db}__last] "
			fi
		fi

	else

		if [ "${LOGS_REC,,}" = 'y' ] || [ "$MAIL_RESULT" -eq 1 ]
		then

			# aumento il contatore
			ERROR_DB_CONN=$(( ERROR_DB_CONN + 1 ))

			# registro i DB nella stessa variabile
			ERROR_CONN_DB+="[${db}] "
		fi
	fi

done

#=========================================
# LOGS SECTION!!!
#=========================================
if [ "${LOGS_REC,,}" = 'y' ]
then

	echo ======================================================================
	echo Saibal MySQL Backup
	echo
	echo Start time: "$TODAY_TIME" - "$TODAY_DATE"
	echo Backup of MySQL Databases \(powered by saibal - lorenzo.forti@gmail.com\)
	echo ======================================================================
	echo Result:
	echo

	# dimensione del file per vedere quando troncarlo
	LOG_SIZE=$( stat -c %s "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME")

	# se la misura attuale è più grande di quella massima tronco il file e ricomincio
	if [ "$LOG_SIZE" -gt "$LOGS_MAXBYTES" ]
	then

		# con il parametro -n non metto una riga vuota nel file
		echo -ne > "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
	fi

	# se vengono rilevati errori nel servizio di posta
	if [ "$ERROR_NOMAIL_SERVICE" -ne 0 ]
	then

		SEMAIL_KO="$LOGDATE | $SEMAIL_KO"

		echo "$SEMAIL_KO"
		echo "$SEMAIL_KO" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
	fi

	# se tutti i dump sono OK stampo il messaggio relativo
	if [ "$ERROR_DB_CONN" -eq 0 ] && [ "$ERROR_COUNT_SINGLE" -eq 0 ] && [ "$ERROR_COPY" -eq 0 ]
	then

		# replace di alcune variabili
		BACKUP_OK="$LOGDATE | $BACKUP_OK"

		echo "$BACKUP_OK"
		echo "$BACKUP_OK" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"

	# se i dump (last/mensile e/o giornaliero) fallisce stampo un determinato messaggio
	else

		if [ "$ERROR_COUNT_SINGLE" -ne 0 ] || [ "$ERROR_COPY" -ne 0 ]
		then

			BACKUP_KO="$LOGDATE | $BACKUP_KO"
			BACKUP_KO=${BACKUP_KO//NOMEDB/$ERROR_RESULT}

			echo "$BACKUP_KO"
			echo "$BACKUP_KO" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
		fi

		# se c'è un problema di connessione al database stampo il messaggio
		if [ "$ERROR_DB_CONN" -ne 0 ]
		then

			CONNEC_KO="$LOGDATE | $CONNEC_KO"
			CONNEC_KO=${CONNEC_KO//NOMEDB/$ERROR_CONN_DB}

			echo "$CONNEC_KO"
			echo "$CONNEC_KO" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
		fi
	fi

	# se c'è un problema con la cancellazione del dump
	if [ "$ERROR_REMOVE_DUMP" -ne 0 ]
	then

		DELETE_KO="$LOGDATE | $DELETE_KO"
		DELETE_KO=${DELETE_KO//NOMEDB/$ERROR_RESULT}

		echo "$DELETE_KO"
		echo "$DELETE_KO" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
	fi

fi

#=========================================
# MAIL SECTION!!!
#=========================================
if [ $MAIL_RESULT -eq 1 ]
then

	# se viene scelto di ricevere una email anche quando le operazioni sono OK
	if [ "${EMAIL_ONLYERRORS,,}" = 'n' ]
	then

		# se tutti i dump sono OK invio il messaggio relativo
		if [ "$ERROR_DB_CONN" -eq 0 ] && [ "$ERROR_COUNT_SINGLE" -eq 0 ] && [ "$ERROR_COPY" -eq 0 ]
		then

			send_mail "$EMAIL_SERVICE" "$EMAIL_RECIVER" "$EMAIL_SUBJECT" "$BACKUP_OK"
		fi
	fi

	# invio email errore backup last, giornaliero o mensile
	if [ $ERROR_COUNT_SINGLE -ne 0 ] || [ $ERROR_COPY -ne 0 ]
	then

		BACKUP_KO=${BACKUP_KO//NOMEDB/$ERROR_RESULT}

		send_mail "$EMAIL_SERVICE" "$EMAIL_RECIVER" "$EMAIL_SUBJECT" "$BACKUP_KO"
	fi

	# invio email errore cancellazione dump
	if [ "$ERROR_REMOVE_DUMP" -ne 0 ]
	then

		DELETE_KO=${DELETE_KO//NOMEDB/$ERROR_RESULT}

		send_mail "$EMAIL_SERVICE" "$EMAIL_RECIVER" "$EMAIL_SUBJECT" "$DELETE_KO"
	fi

	# invio email errore connessioni al database
	if [ "$ERROR_DB_CONN" -ne 0 ]
	then

		CONNEC_KO=${CONNEC_KO//NOMEDB/$ERROR_CONN_DB}

		send_mail "$EMAIL_SERVICE" "$EMAIL_RECIVER" "$EMAIL_SUBJECT" "$CONNEC_KO"
	fi

fi

exit 0
