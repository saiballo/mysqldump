#!/bin/bash
#
# Saibal MySQL Backup Script
#
# VER. 2.1 - http://www.lorenzone.it
# Copyright (c) 2019 saibal@lorenzone.it
#
# BY IDEA OF DAVIDE BUZZI AND MR. GLAUCO! Thank you guys
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#=====================================================================

#=====================================================================
# CHANGELOG
#=====================================================================
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
# Aggiunto trasferimento FTP
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
USERNAME='root'

# db password
PASSWORD=''

# a space separated list of db to dump
# lista dei database da salvare (separati da spazio)
DATABASES='mysql phpmyadmin'

# working directory where to store backup folders (no trailing slash). check r/w permissions for the user
# directory dove salvare i backup (senza slash finale). controllare i permessi di scrittura sulla cartella
OUT_DIR='/home/saibal/backupdb'

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
MONTHLY_BACKUP='n'

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
LOGS_DIR=''

# log folder name. check r/w permissions for the user
# cartella dei LOG. controllare i permessi di scrittura sulla cartella
LOGS_FOLDER='dumplog'

# log filename
# nome del file di LOG
LOGS_FILENAME='dump.log'

# max size of the log file (in KB)
# dimensione massima del file di log (in KB)
LOGS_MAXSIZE='900'

#=====================================================================
# Email configuration
# Configurazione invio email
#=====================================================================
# enable email service as notification? (y or n)
# abilitare invio email con risultato delle operazioni? (y oppure n)
EMAIL_SEND='n'

# enable email only for errors? (y or n)
# inviare email solo in caso di errore? (y oppure n)
EMAIL_ONLYERRORS='y'

# email service. usually I use "ssmtp". try with "smtp" or another service but I don't guarantee
# programma da utilizzare
EMAIL_SERVICE='ssmtp'

# email recipient
# destinatario email
EMAIL_RECIVER='email@gmail.com'

# email subject
# soggetto email
EMAIL_SUBJECT='MySQL Backup - resoconto'

#=====================================================================
# Ftp configuration
# Configurazione ftp
#=====================================================================
# enable ftp transfer for backups? (y or n)
# abilitare trasferimento FTP dei backup? (y oppure n)
FTP_TRANSF='n'

# transfer daily backups or last backups? (d or l)
# trasferire backup giornalieri o solo i last? (d oppure l)
FTP_FILES='d'

# ftp host
# indirizzo FTP
FTP_HOST=''

# ftp username
# username FTP
FTP_USER=''

# ftp password
# password FTP
FTP_PASSWORD=''

# working directory for ftp space (no trailing slash).
# directory in cui inserire i file (senza slash finale).
FTP_REMOTEDIR=''

# log file for ftp commands. saved in same directory of common logs configured above
# file temp. per il log dei comandi di console FTP. Il risultato dell'operazione viene invece registrato sul file generale
FTP_LOGS_FILENAME='ftp.log'

#=====================================================================
# Messages configuration
# Configurazione messaggi
#=====================================================================
# result messages writed in log files. NOMEDB is a placeholder.
# messaggi di ritorno per il backup (NOMEDB è un placeholder. se possibile non cancellare)
BACKUP_OK="BACKUP RIUSCITO! | $HOSTNAME | Tutti i backup effettuati con successo"
BACKUP_KO="ERRORE BACKUP!   | $HOSTNAME | I seguenti database: NOMEDB non sono stati copiati e/o compressi"
CONNEC_KO="ERRORE MYSQL!    | $HOSTNAME | Impossibile connettersi ai seguenti database: NOMEDB"
SEMAIL_KO="ERRORE INVIO!    | $HOSTNAME | Impossibile trovare il servizio $EMAIL_SERVICE per inviare messaggi"
FTPPUT_OK="FTP RIUSCITO!    | $HOSTNAME | Tutti i file sono stati trasferiti con successo sul server $FTP_HOST"
FTPPUT_KO="ERRORE FTP!      | $HOSTNAME | Errore procedura FTP. Errore: FTPERR"

########################################
# NOTHING TO EDIT
# NIENTE DA MODIFICARE
########################################

#=========================================
# FUNZIONI VARIE
#=========================================
# funzione per creare una cartella
create_folder() {

	# controllo l'esistenza della cartella
	if [ ! -d "$1" ]
	then
		mkdir -p "$1" > /dev/null 2>&1
	fi

	# se l'operazione non è andata a buon fine
	if [ "$?" -eq 1 ]
	then
		echo "Errore nel creare la cartella \"$1\". Controllare che non esista un file/directory con lo stesso nome"
		exit
	fi
}

# funzione per check connessione al database
check_connection() {

	# testo la connessione
	mysql --user=$USERNAME --password=$PASSWORD --host=$DBHOST "$DB" -e STATUS > /dev/null 2>&1

	# id errore
	CONN_ERROR=$?

	return $CONN_ERROR
}

# funzione per effettuare il dump al db
do_mysqldump() {

	# dump del database
	mysqldump --user=$USERNAME --password=$PASSWORD --host=$DBHOST "$DB" > "$1"

	# registro il risultato dell'operazione mysqldump.
	DUMP_ERROR=$?

	return $DUMP_ERROR
}

# funzione per effettuare la compressione del database
do_compression() {

	# comprimo il tutto con gzip
	gzip -f "$1"

	#risultato operazione gzip
	GZIP_ERROR=$?

	return $GZIP_ERROR
}

# funzione per check invio email
check_email() {

	if [ "$EMAIL_SEND" = "y" ]
	then

		CHECK_MAIL=$(command -v $EMAIL_SERVICE)

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
	echo -e "From: sh-script\nSubject: $3\n\n$4" | $1 "$2"
}

#=========================================
# VARIABILI
#=========================================
# path principali del sistema
PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/mysql/bin:/usr/sbin

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
DATEIT=$(date +\[%d-%m-%Y_%H-%M-%S\])
DATEEN=$(date +\[%Y-%m-%d_%H-%M-%S\])

# formato data per i log
LOGDATE="$(date +%Y/%m/%d) - $(date +%T)"

# contatori di errori
ERROR_CONN_TODB=0
ERROR_COUNT_SINGLE=0
ERROR_COUNT_PERIODIC=0
ERROR_NOMAIL_SERVICE=0
ERROR_FTP_TRANSFER=0

# se non esiste la directory OUTDIR la creo
create_folder "$OUT_DIR"

# se non esiste la directory LAST la creo
create_folder "$OUT_DIR/$LAST_FOLDER"

# se non esiste la directory DAILY la creo
if [ "$DAILY_BACKUP" = "y" ]
then
	create_folder "$OUT_DIR/$DAILY_FOLDER"
fi

# se non esiste la directory MONTHLY la creo
if [ "$MONTHLY_BACKUP" = "y" ]
then
	create_folder "$OUT_DIR/$MONTHLY_FOLDER"
fi

# codice per convertire in LOWERCASE le variabili inserite in questo array
TO_LOWER=("DATE_FORMAT" "MONTHLY_BACKUP" "LOGS_REC" "EMAIL_SEND" "EMAIL_ONLYERRORS" "FTP_TRANSF" "FTP_FILES")

for INPUT in "${TO_LOWER[@]}"
do
	eval "$INPUT"="$(echo ${!INPUT} | tr '[:upper:]' '[:lower:]')"
done

# scelgo la formattazione della data
if [ "$DATE_FORMAT" = "it" ]
then
	DATE="$DATEIT"
else
	DATE="$DATEEN"
fi

# se sono abilitati i logs e non esiste la directory LOGS la creo e calcolo la dimensione massima del file
if [ "$LOGS_REC" = "y" ]
then

	# se la variabile LOGS_DIR non è vuota la imposto altrimenti inserisco la cartella dentro la directory di default
	if [ -n "$LOGS_DIR" ]
	then
		LOGS_DIR="$LOGS_DIR"
	else
		LOGS_DIR="$OUT_DIR"
	fi

	# creo la directory log
	create_folder  "$LOGS_DIR/$LOGS_FOLDER"

	# creo il file di log
	if [ ! -f "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME" ]
	then
		echo -ne > "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
	fi

	# cancello il file log FTP se viene disabilitata la funzione (ma la funzione log generale deve cmq essere attiva!)
	if [ "$FTP_TRANSF" != "y" ]
	then
		rm -f "$LOGS_DIR/$FTP_LOGS_FILENAME"
	fi

	# converto i KB in BYTES dopo aver controllato che la VAR non sia vuota
	if [ -n "$LOGS_MAXSIZE" ]
	then
		LOGS_MAXBYTES=$(( $LOGS_MAXSIZE*1000 ))
	else
		LOGS_MAXBYTES=$(( 1000*1000 ))
	fi
fi

#=========================================
# START BACKUP NOW!!!
#=========================================

# Controllo l'invio delle email. ritorna $MAIL_RESULT
check_email

# inizio il ciclo sui database
for DB in $DATABASES
do

	# funzione per testare la connessione al database. ritorna $CONN_ERROR
	check_connection

	if [ $CONN_ERROR -eq 0 ]
	then

		########################################
		# BACKUP LAST
		########################################

		# rimuovo i vecchi backup
		rm -f "$OUT_DIR/$LAST_FOLDER/${DB}__"*"__last.gz"

		# creo il nome del file da dumpare e comprimere in .gz
		OUTFILE="$OUT_DIR/$LAST_FOLDER/${DB}__${DATE}.sql"

		# ci sbatto dentro il dump. ritorna $DUMP_ERROR
		do_mysqldump "$OUTFILE"

		# comprimo il file. ritorna $GZIP_ERROR
		do_compression "$OUTFILE"

		# se la compressione è ok copio l'ultimo gzip dentro la dir DAILY e MONTHLY
		if [ $GZIP_ERROR -eq 0 ]
		then

			########################################
			# BACKUP GIORNALIERO
			########################################
			if [ "$DAILY_BACKUP" = "y" ]
			then

				# rimuovo i vecchi backup
				rm -f "$OUT_DIR/$DAILY_FOLDER/[${NDAY}]__${DB}__"*"__daily.gz"

				# uso la funzione cp per copiare l'ultimo back dalla cartella "last" a "daily"
				cp "$OUTFILE.gz" "$OUT_DIR/$DAILY_FOLDER/[${NDAY}]__${DB}__${DATE}.sql__daily.gz"

				# se le copia ha generato errori e i log sono attivi
				if [ $? -gt "0" ] && [ "$LOGS_REC" = "y" ]
				then

					# aumento il contatore
					ERROR_COUNT_PERIODIC=$(( ERROR_COUNT_PERIODIC + 1 ))

					# registro i DB nella stessa variabile
					ERROR_DB+="[${DB}__daily] "
				fi
			fi

			########################################
			# BACKUP MENSILE
			########################################
			if [ "$MONTHLY_BACKUP" = "y" ] && [ "$DMON" = "$MONTHLY_BKDAY" ]
			then

				# rimuovo i vecchi backup
				rm -f "$OUT_DIR/$MONTHLY_FOLDER/[${MON}_"*"]__${DB}"*"__monthly.gz"

				# uso la funzione cp per copiare l'ultimo back dalla cartella "last" a "daily"
				cp "$OUTFILE.gz" "$OUT_DIR/$MONTHLY_FOLDER/[${MONYEA}]__${DB}__${DATE}.sql__monthly.gz"

				# se le copia ha generato errori e i log sono attivi
				if [ $? -gt 0 ] && [ "$LOGS_REC" = 'y' ]
				then

					# aumento il contatore
					ERROR_COUNT_PERIODIC=$(( ERROR_COUNT_PERIODIC + 1 ))

					# registro i DB nella stessa variabile
					ERROR_DB+="[${DB}__monthly] "
				fi
			fi
		fi

		# rinomino il vecchio file nella cartella "last" con il suffisso "__last"
		mv "$OUTFILE.gz" "${OUTFILE}__last.gz"

		# uso le VAR di ritorno delle funzioni per gestire gli errori nei log se abilitati
		if [ "$LOGS_REC" = "y" ]
		then

			if [ $DUMP_ERROR -gt 0 ] || [ $GZIP_ERROR -gt 0 ]
			then

				# aumento il contatore
				ERROR_COUNT_SINGLE=$(( ERROR_COUNT_SINGLE + 1 ))

				# registro i DB nella stessa variabile
				ERROR_DB+="[${DB}__last] "
			fi
		fi

	else

		if [ "$LOGS_REC" = 'y' ] || [ $MAIL_RESULT -eq 1 ]
		then

			# aumento il contatore
			ERROR_CONN_TODB=$(( ERROR_CONN_TODB + 1 ))

			# registro i DB nella stessa variabile
			ERROR_CONN_DB+="[${DB}] "
		fi
	fi

done

#=========================================
# LOGS SECTION!!!
#=========================================
if [ "$LOGS_REC" = "y" ]
then

	echo ======================================================================
	echo Saibal MySQL Backup
	echo
	echo Start time: "$TODAY_TIME" - "$TODAY_DATE"
	echo Backup of MySQL Databases \(powered by saibal - saibal@lorenzone.it\)
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
	if [ $ERROR_NOMAIL_SERVICE -gt 0 ]
	then

		SEMAIL_KO="$LOGDATE | $SEMAIL_KO"

		echo "$SEMAIL_KO"
		echo "$SEMAIL_KO" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
	fi

	# se c'è un problema FTP stampo il messaggio
	if [ $ERROR_FTP_TRANSFER -gt 0 ]
	then

		FTPPUT_KO="$LOGDATE | $FTPPUT_KO"
		FTPPUT_KO=${FTPPUT_KO//FTPERR/$ERROR_FTP_RESULT}

		echo "$FTPPUT_KO"
		echo "$FTPPUT_KO" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"

	elif [ "$FTP_TRANSF" = "y" ] && [ "$ERROR_FTP_TRANSFER" -eq "0" ]
	then

		FTPPUT_OK="$LOGDATE | $FTPPUT_OK"

		echo "$FTPPUT_OK"
		echo "$FTPPUT_OK" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
	fi

	# se tutti i dump sono OK stampo il messaggio relativo
	if [ $ERROR_CONN_TODB -eq 0 ] && [ $ERROR_COUNT_SINGLE -eq 0 ] && [ $ERROR_COUNT_PERIODIC -eq 0 ]
	then

		# replace di alcune variabili
		BACKUP_OK="$LOGDATE | $BACKUP_OK"

		echo "$BACKUP_OK"
		echo "$BACKUP_OK" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"

	# se i dump (last/mensile e/o giornaliero) fallisce stampo un determinato messaggio
	else

		if [ $ERROR_COUNT_SINGLE -gt 0 ] || [ $ERROR_COUNT_PERIODIC -gt 0 ]
		then

			BACKUP_KO="$LOGDATE | $BACKUP_KO"
			BACKUP_KO=${BACKUP_KO//NOMEDB/$ERROR_DB}

			echo "$BACKUP_KO"
			echo "$BACKUP_KO" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
		fi

		# se c'è un problema di connessione al database stampo il messaggio
		if [ $ERROR_CONN_TODB -gt 0 ]
		then

			CONNEC_KO="$LOGDATE | $CONNEC_KO"
			CONNEC_KO=${CONNEC_KO//NOMEDB/$ERROR_CONN_DB}

			echo "$CONNEC_KO"
			echo "$CONNEC_KO" >> "$LOGS_DIR/$LOGS_FOLDER/$LOGS_FILENAME"
		fi
	fi
fi

#=========================================
# MAIL SECTION!!!
#=========================================
if [ $MAIL_RESULT -eq 1 ]
then

	# se viene scelto di ricevere una email anche quando le operazioni sono OK
	if [ "$EMAIL_ONLYERRORS" = "n" ]
	then

		# se tutti i dump sono OK invio il messaggio relativo
		if [ $ERROR_CONN_TODB -eq 0 ] && [ $ERROR_COUNT_SINGLE -eq 0 ] && [ $ERROR_COUNT_PERIODIC -eq 0 ]
		then

			#BACKUP_OK="$BACKUP_OK"

			# se è attivo il trasferimento file e non ci sono errori aggiungo una parte di messaggio
			if [ "$FTP_TRANSF" = 'y' ] && [ $ERROR_FTP_TRANSFER -eq 0 ]
			then
				BACKUP_OK="$BACKUP_OK | $FTPPUT_OK"
			fi

			send_mail "$EMAIL_SERVICE" "$EMAIL_RECIVER" "$EMAIL_SUBJECT" "$BACKUP_OK"
		fi
	fi

	# invio email errore backup last, giornaliero o mensile
	if [ $ERROR_COUNT_SINGLE -gt 0 ] || [ $ERROR_COUNT_PERIODIC -gt 0 ]
	then

		#BACKUP_KO="$BACKUP_KO"
		BACKUP_KO=${BACKUP_KO//NOMEDB/$ERROR_DB}

		send_mail "$EMAIL_SERVICE" "$EMAIL_RECIVER" "$EMAIL_SUBJECT" "$BACKUP_KO"
	fi

	# invio email errore connessioni al database
	if [ $ERROR_CONN_TODB -gt 0 ]
	then

		#CONNEC_KO="$CONNEC_KO"
		CONNEC_KO=${CONNEC_KO//NOMEDB/$ERROR_CONN_DB}

		send_mail "$EMAIL_SERVICE" "$EMAIL_RECIVER" "$EMAIL_SUBJECT" "$CONNEC_KO"
	fi

	# invio email errore trasferimento file
	if [ $ERROR_FTP_TRANSFER -gt 0 ]
	then

		#FTPPUT_KO="$FTPPUT_KO"
		FTPPUT_KO=${FTPPUT_KO//FTPERR/$ERROR_FTP_RESULT}

		send_mail "$EMAIL_SERVICE" "$EMAIL_RECIVER" "$EMAIL_SUBJECT" "$FTPPUT_KO"
	fi
fi

#=========================================
# FTP SECTION!!!
#=========================================
if [ "$FTP_TRANSF" = "y" ] && [ $CONN_ERROR -eq 0 ]
then

	if [ "$FTP_FILES" = "d" ]
	then
		FTP_FOLDER="$DAILY_FOLDER"
		MFILENAME="*[${NDAY}]*]*.gz"
	else
		FTP_FOLDER="$LAST_FOLDER"
		MFILENAME="*__last.gz"
	fi

	echo "
			open $FTP_HOST
			user $FTP_USER $FTP_PASSWORD
			binary
			lcd $OUT_DIR/$FTP_FOLDER
			cd $FTP_REMOTEDIR
			mdelete $MFILENAME
			mput $MFILENAME
			close
			quit" | ftp -in -v > "$LOGS_DIR/$LOGS_FOLDER/$FTP_LOGS_FILENAME" 2>&1

	# visto che le funzioni FTP fanno schifo cerco in qualche maniera di intercettare gli errori
	# non connesso
	FTP_TRAPERR=$(grep -i "Not connected." "$LOGS_DIR/$LOGS_FOLDER/$FTP_LOGS_FILENAME")
	if [ $? -eq 0 ]
	then
		# aumento il contatore
		ERROR_FTP_TRANSFER=$(( ERROR_FTP_TRANSFER + 1 ))
		ERROR_FTP_RESULT="${ERROR_FTP_RESULT}Connessione al server FTP fallita | "
	fi

	# autenticazione fallita
	FTP_TRAPERR=$(grep -i "Login authentication failed" "$LOGS_DIR/$LOGS_FOLDER/$FTP_LOGS_FILENAME")
	if [ $? -eq 0 ]
	then
		# aumento il contatore
		ERROR_FTP_TRANSFER=$(( ERROR_FTP_TRANSFER + 1 ))
		ERROR_FTP_RESULT="${ERROR_FTP_RESULT}Autenticazione fallita | "
	fi

	# directory remota non trovata
	FTP_TRAPERR=$(grep -i "change directory to $FTP_REMOTEDIR" "$LOGS_DIR/$LOGS_FOLDER/$FTP_LOGS_FILENAME")
	if [ $? -eq 0 ]
	then
		# aumento il contatore
		ERROR_FTP_TRANSFER=$(( ERROR_FTP_TRANSFER + 1 ))
		ERROR_FTP_RESULT="${ERROR_FTP_RESULT}Directory remota non trovata | "
	fi

	# non trovo i file
	FTP_TRAPERR=$(grep -i "no such" "$LOGS_DIR/$LOGS_FOLDER/$FTP_LOGS_FILENAME")
	if [ $? -eq 0 ]
	then
		# aumento il contatore
		ERROR_FTP_TRANSFER=$(( ERROR_FTP_TRANSFER + 1 ))
		ERROR_FTP_RESULT="${ERROR_FTP_RESULT}File o directory non trovati | "
	fi

	# app chiusa
	FTP_TRAPERR=$(grep -i "killed" "$LOGS_DIR/$LOGS_FOLDER/$FTP_LOGS_FILENAME")
	if [ $? -eq 0 ]
	then
		# aumento il contatore
		ERROR_FTP_TRANSFER=$(( ERROR_FTP_TRANSFER + 1 ))
		ERROR_FTP_RESULT="${ERROR_FTP_RESULT}Processo di trasferimento abbandonato | "
	fi

	# spazio su disco esaurito (come me!! bwuahbwuah)
	FTP_TRAPERR=$(grep -i "space" "$LOGS_DIR/$LOGS_FOLDER/$FTP_LOGS_FILENAME")
	if [ $? -eq 0 ]
	then
		# aumento il contatore
		ERROR_FTP_TRANSFER=$(( ERROR_FTP_TRANSFER + 1 ))
		ERROR_FTP_RESULT="${ERROR_FTP_RESULT}Mancanza di spazio su disco"
	fi
fi

exit 0
