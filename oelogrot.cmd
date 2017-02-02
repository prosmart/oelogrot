@ECHO off

::   Name:      oelogrot.cmd
::   Author:    Nigel Allen, Open Edge Solutions
::   Written:   January 2017
::   Purpose:   Log rotater and archiver for Progress Openedge log files.
::		based on original protop script


:: Delay variable expansion to runtime

Setlocal EnableDelayedExpansion

:: Grab environment vars


IF NOT EXIST "%ENVPT3%\bin\protopenv.bat" (
   ECHO Unable to locate %ENVPT3%\bin\protopenv.bat
   GOTO :ABEND
)

CALL %ENVPT3%\bin\protopenv.bat

REM @ECHO ON

if "%PROTOP%"=="" (
   ECHO ERROR: PROTOP environment variable not set - exiting 
   GOTO :ABEND
)

IF "%TMPDIR%"=="" (
   ECHO ERROR: TMPDIR not set - exiting
   GOTO :ABEND
)

IF "%LOGDIR%"=="" (
   ECHO ERROR: LOGDIR not set - exiting
   GOTO :ABEND
)

IF "%LGARCDIR%"=="" (
   ECHO ERROR: LGARCDIR not set - exiting
   GOTO :ABEND
)

cd "%PROTOP%"

IF NOT EXIST "%TMPDIR%" md "%TMPDIR%"
IF NOT EXIST "%LOGDIR%" md "%LOGDIR%"
IF NOT EXIST "%LGARCDIR%" md "%LGARCDIR%"

::
::
::	Main Logic Start
::
::   	Process Parameters
:
:: IP1 is either:
::   - a "friendly name" in etc/dblist.cfg
::   - the literal "all" (Signifies all of the databases in /etc/dblist.cfg)
::   - the path to a database
::


IF [%1] == [] (
   CALL :SUB_USAGE
   GOTO :ABEND
)

SET IP1=%1

IF "IP1"=="" (
   CALL :SUB_USAGE
   GOTO :ABEND
)

set DB=
set FRNAME=

::	Set up all the date and time fields using localised formats

for /F "usebackq tokens=1,2 delims==" %%i in (`wmic os get LocalDateTime /VALUE 2^>NUL`) do if '.%%i.'=='.LocalDateTime.' set ldt=%%j
set yy=%ldt:~0,4%&set mm=%ldt:~4,2%&set dd=%ldt:~6,2%
set hr=%ldt:~8,2%&set mn=%ldt:~10,2%&set ss=%ldt:~12,2%&set ms=%ldt:~15,3%

::	Convert today to the ISO week number

CALL :D2WN %yy% %mm% %dd% WK

::	First look for the literal "all" to signify all databases in etc/dblist.cfg
::	then check etc/dblist.cfg for a matching "friendly name"
::	lastly check to see if $1 is a path name

IF "%IP1%"=="all" (
   IF NOT EXIST "%PROTOP%\etc\dblist.cfg" (
      echo Error: Cannot find %PROTOP%\etc\dblist.cfg - exiting
      GOTO :ABEND
   )
   FOR /F "tokens=1,2 delims=|" %%A IN (%PROTOP%\etc\dblist.cfg) DO (
      set FRNAME=%%A
      set DB=%%B
REM   echo FRNAME = [!FRNAME!]
REM   echo DB = [!DB!]
REM   echo First Char = [!FRNAME:~0,1!]
REM   pause
      IF NOT "!FRNAME:~0,1!"=="#" CALL :SUB_ROLL
   )
   GOTO :END
)

::	Is it a "friendly name" defined in etc/dblist.cfg?
FOR /F "tokens=1,2 delims=|" %%A IN (%PROTOP%\etc\dblist.cfg) DO (
   set FRNAME=%%A
   set DB=%%B
   echo IP1 = [%IP1%]
   echo FRNAME = [!FRNAME!]
   echo DB = [!DB!]
   pause
   IF "%IP1%"=="!FRNAME!" (
      CALL :SUB_ROLL
   )
)

IF EXIST %IP1% (
   SET DB=%IP1%
   CALL :SUB_ROLL
)
   
GOTO :END

::	Usage Function

:SUB_USAGE

   ECHO.
   ECHO Usage: oelogrot.cmd all^|friendlyname^|full path to database
   ECHO.
   EXIT /B


:: Date To ISO Week Number

:D2WN %yy% %mm% %dd% WN
  
:: Func: Converts date components into Week Numbers as per ISO 8601. Weeks
:: start on a Monday. Functionally equivalent to the Excel function
:: WEEKNUM. For NT4/2K/XP.
::
:: Args: %1 year component to be converted, 2 or 4 digits (by val)
:: %2 month component to be converted, leading zero ok (by val)
:: %3 date component to be converted, leading zero ok (by val)
:: %4 Var to receive Week Number in the range 01-53 (by ref)
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

setlocal ENABLEEXTENSIONS
set D2WN.yy=%1&set D2WN.mm=%2&set D2WN.dd=%3
if 1%D2WN.yy% LSS 200 if 1%D2WN.yy% LSS 180^
(set D2WN.yy=20%D2WN.yy%) else (set D2WN.yy=19%D2WN.yy%)
set /a D2WN.dd=100%D2WN.dd%%%100,D2WN.mm=100%D2WN.mm%%%100
set /a D2WN.z=14-D2WN.mm,D2WN.z/=12,D2WN.y=D2WN.yy+4800-D2WN.z
set /a D2WN.m=D2WN.mm+12*D2WN.z-3,D2WN.JDN=153*D2WN.m+2
set /a D2WN.JDN=D2WN.JDN/5+D2WN.dd+D2WN.y*365+^
D2WN.y/4-D2WN.y/100+D2WN.y/400-32045
set /a D2WN.a=D2WN.JDN%%7,D2WN.a=D2WN.JDN+31741-D2WN.a
set /a D2WN.a=D2WN.a%%146097%%36524%%1461,D2WN.l=D2WN.a/1460
set /a D2WN.b=D2WN.a-D2WN.l,D2WN.b=D2WN.a%%365
set /a D2WN.b+=D2WN.l,D2WN.WN=D2WN.b/7,D2WN.WN+=1
if %D2WN.WN% LSS 10 set D2WN.WN=0%D2WN.WN%
endlocal&set %4=%D2WN.WN%&goto :EOF


::	Roll Logs Function

:SUB_ROLL

:: @echo on
:: echo In SUB_ROLL
:: set/p x=Press enter to continue
   set RLOG=%LOGDIR%\logrotate.log
   set ONLINE=

   echo Rolling log for %FRNAME%
   FOR /F %%i in ("%DB%") DO @set DBNAME=%%~nxi

   call proutil %DB% -C holder >NUL 2>&1

   IF ERRORLEVEL 16 GOTO MULTIUSER
   IF ERRORLEVEL 14 GOTO SINGLEUSER
   IF ERRORLEVEL 0 GOTO CONTINUE
   GOTO :EOF

   :SINGLEUSER
   echo The database $DB is locked, logs not rolled
   GOTO :EOF

   :MULTIUSER
   SET ONLINE=-online

   :CONTINUE

   copy %DB%.lg %LGARCDIR%\%FRNAME%.lg.%WK% >NUL 2>&1

   IF ERRORLEVEL 1 (
      echo Copy of database log %DB%.lg failed - exiting
      GOTO :EOF
   )

   call prolog %DB% %ONLINE% >> %RLOG% 2>&1

   IF NOT ERRORLEVEL 0 (
      %PROTOP%\bin\sendalert %FRNAME% -msg="prolog failed during log roll"
   )


   EXIT /B


:ABEND

:END

