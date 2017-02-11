#!/bin/sh

#   Name:      oelogrot.sh
#   Author:    Nigel Allen, Open Edge Solutions
#   Written:   January 2017
#   Purpose:   Log rotater and archiver for Progress Openedge log files.
#		based on original protop script

#set -x 

# Un-comment following line for debugging
# ECHO=echo

# Change to true to get additional debugging.
debug=false


if [ -z "$PROTOP" ]; then
    echo "PROTOP environment variable not set - exiting"
    exit 1
fi  

. $PROTOP/bin/protopenv

cd ${PROTOP}

TMPDIR=${TMPDIR-/tmp}
LOGDIR=${LOGDIR-/tmp}
LGARCDIR=${LGARCDIR-/tmp}
NOW='date "+%Y.%m.%d %H:%M:%S"'
RENUM='^[0-9]+$'
DBLIST=${PROTOP}/etc/dblist.cfg
					# Check directories exist or create them
[ ! -d ${TMPDIR} ] && mkdir ${TMPDIR}
[ ! -d ${LOGDIR} ] && mkdir ${LOGDIR}
[ ! -d ${LGARCDIR} ] && mkdir ${LGARCDIR}


usage()					# usage function
{
   echo "Usage: $0 all|friendly_name|full_path_to_database"
   exit 1
}

errmsg()				# error message function
{
   echo ""
   echo "${1}"
   echo ""
}

roll_logs()				# roll the logs function
{
   WK=`date +%W`
   RLOG=${LOGDIR}/logrotate.log
   ONLINE=
   DBNAME=`basename $DB`


   $ECHO proutil $DB -C holder >/dev/null 2>&1
   retcode=$?  # this saves the return code
   case $retcode in
      0)  ;;
      14) echo "The database $DB is locked, logs not rolled"
          return $retcode
          ;;
      16) ONLINE="-online"
          ;;
      *)  errmsg "proutil on $DB failed with return code of $retcode"
          return $retcode
          ;;
   esac
      echo $(eval $NOW) Starting log rotation for $DB
   {
      echo $(eval $NOW) Starting log rotation for $DB
      $ECHO cp ${DB}.lg ${LGARCDIR}/${FRNAME}.lg.${WK}
      $ECHO prolog ${DB} $ONLINE;RC=$? 
   } >> ${RLOG} 2>&1

   if ! [ ${RC} = 0 ]
   then
      ${PROTOP}/bin/sendalert.sh $FRNAME -msg="prolog failed during log roll" 
   fi

   if $FILT = true	# We are filtering
   then
      if [ -f $LOGROTCFG.tmp ]
      then
         $ECHO grep -v -f $LOGROTCFG.tmp ${LGARCDIR}/${FRNAME}.lg.${WK} >${LGARCDIR}/${FRNAME}.lgf.${WK}
      fi
   fi
}

#
#
#	Main Logic Start
#
# IP1 is either:
#   - a "friendly name" in etc/dblist.cfg
#   - the literal "all" (Signifies all of the databases in /etc/dblist.cfg)
#   - the path to a database
#

IP1=${1}

if [ -z "${IP1}" ]			# did we forget the target?
then
   usage
fi

# Are we filtering?

if [ ! -z "${2}" ]  && [ "${2}" = "-filter" ]
then
   FILT=true
else
   FILT=false
fi

if [ $debug == "true" ]; then
   echo '${2} = ' ${2}
   echo Filter = $FILT
   read cont
fi

LOGROTCFG=$PROTOP/etc/logrotate.cfg
if $FILT = true 
then
   if [ -f $LOGROTCFG ]
   then
      LOGHIST=`grep -i "^loghist" $LOGROTCFG|sed 's/^.*=//'`
      FLOGHIST=`grep -i "^floghist" $LOGROTCFG|sed 's/^.*=//'`
      grep "^(.*)$" $LOGROTCFG >$LOGROTCFG.tmp
      if [[ ! $LOGHIST =~ $RENUM ]] || [ -z $LOGHIST ]
      then
         LOGHIST=0
      fi
      if [[ ! $FLOGHIST =~ $RENUM ]]
      then
         FLOGHIST=0
      fi
   fi
fi

if [ $debug == "true" ]; then
   echo After logrotate.cfg
   echo LOGHIST = $LOGHIST
   echo FLOGHIST = $FLOGHIST
   read x
fi

DB=

# First look for the literal "all" to signify all databases in etc/dblist.cfg
# then check etc/dblist.cfg for a matching "friendly name"
# lastly check to see if $1 is a path name
#

if [ "${IP1}" = "all" ]
then

   if ! [ -f $DBLIST ]
   then
      errmsg "'all' option used and no dblist.cfg present"
      exit 1
   fi
   grep -v -e "^#" -e "^ " -e "^$" $DBLIST | while IFS="|" read -r FRNAME DB col3andtherest
   do
      roll_logs ${DB}
   done

else

   # Is it a "friendly name" defined in etc/dblist.cfg?

   if [ -f $DBLIST ]   # search using "pipe" as the delimiter
   then
      DB=`grep "^${IP1}|" $DBLIST | awk -F"|" '{print $2}' 2>/dev/null`
   fi

   # If DB has a value then we found a friendly name and the path is held in DB
   # otherwise we presume the input parameter is the path name

   if [ -z "${DB}" ]               	# no friendly name so pathtodb is empty
   then
      DB=${IP1}               		# take ${IP1} as the path name
   else
      FRNAME=${IP1} 
   fi

   # Try ${DB} as a path name

   if [ -f ${DB}.db ]
   then
      roll_logs ${DB}
   else
      errmsg "${DB} does not exist."
   fi

fi

if [ $debug == "true" ]; then
   echo "FILT = $FILT"
   echo "LOGHIST = $LOGHIST"
   echo "FLOGHIST = $FLOGHIST"
   read x
fi

if $FILT = true
then
   if ! [[ "$LOGHIST" -eq "0" ]]
   then
      LHIST=$((LOGHIST*7))
      echo "Cleaning up any archived log files older than $LOGHIST weeks"
      $ECHO find ${LGARCDIR} -name "*.lg.[0-9]*" -mtime +$LHIST -exec rm {} \;
   fi
   if ! [[ "$FLOGHIST" -eq "0" ]]
   then
      LHIST=$((FLOGHIST*7))
      echo "Cleaning up any filtered archived log files older than $FLOGHIST weeks"
      $ECHO find ${LGARCDIR} -name "*.lgf.[0-9]*" -mtime +$LHIST -exec rm {} \;
   fi
fi
