#!/bin/sh

#   Name:      oelogrot.sh
#   Author:    Nigel Allen, Open Edge Solutions
#   Written:   January 2017
#   Purpose:   Log rotater and archiver for Progress Openedge log files.
#		based on original protop script

#set -x 

. /pt3n/bin/protopenv

cd ${PROTOP}

TMPDIR=${TMPDIR-/tmp}
LOGDIR=${LOGDIR-/tmp}
LGARCDIR=${LGARCDIR-/tmp}
					# Check directories exist or create them
[ ! -d ${TMPDIR} ] && mkdir ${TMPDIR}
[ ! -d ${LOGDIR} ] && mkdir ${LOGDIR}
[ ! -d ${LGARCDIR} ] && mkdir ${LGARCDIR}


usage()					# usage function
{
   echo "Usage: $0 full_path_to_database"
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

   proutil $DB -C holder >/dev/null 2>&1
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
   { cp ${DB}.lg ${LGARCDIR}/${FRNAME}.lg.${WK};prolog ${DB} $ONLINE;RC=$?; } > ${RLOG} 2>&1
   if ! [ ${RC} = 0 ]
   then
      ${PROTOP}/bin/sendalert.sh $FRNAME -msg="prolog failed during log roll" 
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

DB=

# First look for the literal "all" to signify all databases in etc/dblist.cfg
# then check etc/dblist.cfg for a matching "friendly name"
# lastly check to see if $1 is a path name
#

if [ "${IP1}" = "all" ]
then

   if ! [ -f ${PROTOP}/etc/dblist.cfg ]
   then
      errmsg "'all' option used and no dblist.cfg present"
      exit 1
   fi
   grep -v -e "^#" -e "^ " -e "^$" ${PROTOP}/etc/dblist.cfg | while IFS="|" read -r FRNAME DB col3andtherest
   do
      roll_logs ${DB}
   done

else

   # Is it a "friendly name" defined in etc/dblist.cfg?

   if [ -f ${PROTOP}/etc/dblist.cfg ]   # search using "pipe" as the delimiter
   then
      DB=`grep "^${IP1}|" ${PROTOP}/etc/dblist.cfg | awk -F"|" '{print $2}' 2>/dev/null`
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
