#!/bin/sh

#   Name:      oelogrot.sh
#   Author:    White Star Software
#   Written:   January 2017
#   Purpose:   Log rotater and archiver for Progress Openedge log files.

#set -x 

# Un-comment following line for debugging
#ECHO=echo

# Change to true to get additional debugging.
debug=false


if [ -z "$PROTOP" ]; then
    echo "PROTOP environment variable not set - exiting"
    exit 1
fi  

. $PROTOP/bin/protopenv

cd ${PROTOP}

TMPDIR=${TMPDIR-$PROTOP/tmp}
LOGDIR=${LOGDIR-$PROTOP/tmp}
LGARCDIR=${LGARCDIR-$PROTOP/tmp}
RLOG=${LOGDIR}/logrotate.log
NOW='date "+%Y.%m.%d %H:%M:%S"'
RENUM='^[0-9]+$'
DBLIST=${PROTOP}/etc/dblist.cfg
					# Check directories exist or create them
[ ! -d ${TMPDIR} ] && mkdir ${TMPDIR}
[ ! -d ${LOGDIR} ] && mkdir ${LOGDIR}
[ ! -d ${LGARCDIR} ] && mkdir ${LGARCDIR}


usage()					# usage function
{
   echo "Usage: $0 all|friendly_name|full_path_to_database -filter(optional)"
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
   ONLINE=
   DBNAME=`basename "$DB"`

   if [ "${DBNAME:(-3)}" == ".db" ]
   then
      DBNAME=${DBNAME:(-3)}
   fi

   echo "$(eval $NOW) Rolling log for $FRNAME" >>"$RLOG" 2>&1

   $ECHO proutil "$DB" -C holder >/dev/null 2>&1
   retcode=$?  # this saves the return code
   case $retcode in
      0)  ;;
      14) echo "The database $DB is locked, logs not rolled"
          echo "The database $DB is locked, logs not rolled" >> "$RLOG" 2>&1
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
      $ECHO cp "${DB}.lg" "${LGARCDIR}/${FRNAME}.lg.${WK}"
      $ECHO prolog "${DB}" $ONLINE;RC=$? 
   } >> ${RLOG} 2>&1

   if ! [ ${RC} = 0 ]
   then
      ${PROTOP}/bin/sendalert.sh $FRNAME -m prolog -type alarm -msg "prolog failed during log roll" 
   else
      ${PROTOP}/bin/sendalert.sh $FRNAME -m prolog -type info -msg "prolog completed successfully"
   fi

   if $FILT = true	# We are filtering
   then
      if [ -f $LOGROTCFG.tmp ]
      then
	 echo Filtering ${LGARCDIR}/${FRNAME}.lg.${WK} to ${LGARCDIR}/${FRNAME}.lgf.${WK} >> "$RLOG" 
         $ECHO grep -v -f $LOGROTCFG.tmp "${LGARCDIR}/${FRNAME}.lg.${WK}" >"${LGARCDIR}/${FRNAME}.lgf.${WK}"
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
   echo Line 130
   echo '${2} = ' ${2}
   echo Filter = $FILT
   read cont
fi

LOGROTCFG=$PROTOP/etc/logrotate.cfg
if [ -f $LOGROTCFG ]
then
   LOGHIST=`grep -i "^loghist" $LOGROTCFG|sed 's/^.*=//'`
   FLOGHIST=`grep -i "^floghist" $LOGROTCFG|sed 's/^.*=//'`
   TMPVAR=`grep -i "^lgarcdir" $LOGROTCFG|sed 's/^.*=//'`
   grep "^(.*)$" $LOGROTCFG >$LOGROTCFG.tmp
   if [ ! -z $TMPVAR ]
   then
      if [ ! -d $TMPVAR ]
      then
         mkdir $TMPVAR
      fi
      if [ -d $TMPVAR ]
      then
         LGARCDIR=$TMPVAR
      fi
   fi
   if [[ ! $LOGHIST =~ $RENUM ]] || [ -z $LOGHIST ]
   then
      LOGHIST=0
   fi
   if [[ ! $FLOGHIST =~ $RENUM ]]
   then
      FLOGHIST=0
   fi
fi

if [ $debug == "true" ]; then
   echo 
   echo After logrotate.cfg
   echo LGARCDIR = $LGARCDIR
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
#   awk -F"|" '/^#/ {next}; /^$/ {next};{ print $1 " " $2 } ' <$DBLIST|while read -r FRNAME DB
   do
      roll_logs "${DB}"
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
      DB="${IP1}"               		# take ${IP1} as the path name
   else
      FRNAME="${IP1}"
   fi

   # Try ${DB} as a path name

   if [ -f "${DB}.db" ]
   then
      roll_logs "${DB}"
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
      echo Cleaning up any archived log files older than $LOGHIST weeks >> "$RLOG" 2>&1
      $ECHO find ${LGARCDIR} -name "*.lg.[0-9]*" -mtime +$LHIST -exec rm {} \; >>"$RLOG" 2>&1
   fi
   if ! [[ "$FLOGHIST" -eq "0" ]]
   then
      LHIST=$((FLOGHIST*7))
      echo "Cleaning up any filtered archived log files older than $FLOGHIST weeks">>"$RLOG" 2>&1
      $ECHO find ${LGARCDIR} -name "*.lgf.[0-9]*" -mtime +$LHIST -exec rm {} \; >>"$RLOG" 2>&1
   fi
fi
