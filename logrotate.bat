@ECHO OFF
REM   Name:      logrotate.bat
REM   Author:    White Star Software
REM   Written:   January 2017
REM   Purpose:   Log rotator and archiver for Progress Openedge log files.
REM 
 
REM Set EKKO=echo for debug
set EKKO=
REM Change false to true for verbose debugging displays
SET DEBUG=false
 
REM Delay variable expansion to runtime
Setlocal EnableDelayedExpansion
 
REM Grab the environment variables
REM CALL #ENVPT3#\bin\protopenv.bat
call E:\DBAppraise\bin\protopenv.bat
 
set RLOG=%LOGDIR%\logrotate.log
echo ################### STARTING %DATE% %TIME% ################### >> "%RLOG%"
REM Tailor at deployment
REM Now set from logrotate.cfg. If not found there, will default to this one
SET LGARCDIR=%TMPDIR%
REM Check for logrotate config file
REM If it does not exist then rotate but neither purge nor filter
IF NOT EXIST "%PROTOP%\etc\logrotate.cfg" (
   echo Unable to locate %PROTOP%\etc\logrotate.cfg
   set LOGHIST=0
   set FLOGHIST=0
   set LOGROTCFG=
)  else (
   set LOGROTCFG=%PROTOP%\etc\logrotate.cfg
)
IF "%DEBUG%"=="true" (
   echo PROTOP = %PROTOP%
   echo TMPDIR = %TMPDIR%
   echo LOGDIR = %LOGDIR%
   echo LGARCDIR = %LGARCDIR%
   set /p x=Press enter to continue
)
IF "%PROTOP%"=="" (
   echo Environment variable PROTOP is blank - exiting
   GOTO ABEND
)
IF NOT EXIST "%PROTOP%\" (
   echo %PROTOP% is not a valid directory - exiting
   GOTO ABEND
)
cd "%PROTOP%"
IF NOT EXIST "%TMPDIR%"   %EKKO% md "%TMPDIR%"
IF NOT EXIST "%LOGDIR%"   %EKKO% md "%LOGDIR%"
IF NOT EXIST "%LGARCDIR%" %EKKO% md "%LGARCDIR%"
REM
REM
REM   Main Logic Start
REM
REM   Process Parameters
REM
REM IP1 is either:
REM   - a "friendly name" in etc/dblist.cfg
REM   - the literal "all" (Signifies all of the databases in /etc/dblist.cfg)
REM   - the path to a database
REM
REM IP2 is optional "-filter"
REM
IF "%~1" == "" (
   CALL :SUB_USAGE
   GOTO :ABEND
) else SET IP1=%~1
IF "%2"=="-filter" (
   SET "FILT=true"
   echo Filtering option selected >> "%RLOG%"
) else (
   if NOT "%2" == ""  (
      echo Unknown parameter %2
      GOTO :ABEND
   )
)
IF "%DEBUG%"=="true" (
   echo In Main Logic FILT = %FILT%
   echo LOGROTCFG = %LOGROTCFG%
   echo TMPDIR = %TMPDIR%
   set /p x=Press enter to continue
)
IF NOT "%LOGROTCFG%"=="" (
   grep -i "^loghist" < "%LOGROTCFG%" | sed -e "s/^.*=//" >"%TMPDIR%\tmpfile"
   SET /p LOGHIST=<"%TMPDIR%\tmpfile"
 
   grep -i "^floghist" <"%LOGROTCFG%" | sed -e "s/^.*=//" >"%TMPDIR%\tmpfile"
   SET /p FLOGHIST=<"%TMPDIR%\tmpfile"
   grep -i "^lgarcdir" <"%LOGROTCFG%" | sed -e "s/^.*=//" >"%TMPDIR%\tmpfile"
   SET /p TMPVAR=<"%TMPDIR%\tmpfile"
 
   IF "%DEBUG%"=="true" (
      echo TMPVAR = !TMPVAR!
      set /p x=Press enter to continue
   )
)
 
IF "%DEBUG%"=="true" (
   echo After the greps
   echo TMPVAR = %TMPVAR%
   echo LOGROTCFG = %LOGROTCFG%
   set /p x=Visciously strike the return key to continue
 
)
 
IF NOT "%LOGROTCFG%"=="" (
 
   REM  If we found a valid archive dir on the config file then create it if needed.
   REM  Either way, make sure it exists and it is a directory and not a file
   IF NOT "%TMPVAR%"=="" (
      IF NOT EXIST "%TMPVAR%" (
         MKDIR "%TMPVAR%"
      )
      IF EXIST "%TMPVAR%\." (
         SET LGARCDIR=%TMPVAR%
      )
   )
   REM  Make sure we only have integers in the numbers of weeks to keep
   SET "tester="&for /f "delims=0123456789" %%i in ("%LOGHIST%") do set tester=%%i
   if defined tester (SET LOGHIST=0)
   SET "tester="&for /f "delims=0123456789" %%i in ("%FLOGHIST%") do set tester=%%i
   if defined tester (SET FLOGHIST=0)
   grep "^(.*)$" "%LOGROTCFG%" >"%TMPDIR%\logrotcfg.tmp"
)
 
IF "%DEBUG%"=="true" (
   echo FILT = %FILT%
   echo LOGHIST = %LOGHIST%
   echo FLOGHIST = %FLOGHIST%
   echo LGARCDIR = %LGARCDIR%
   set/p x=Press enter to continue
)
set DB=
set FRNAME=
set WK=
REM   Set up all the date and time fields using localised formats
REM   Specific path below as it was using system date command and hanging
"%PROTOP%\ubin\date.exe" +%%W>"%TMPDIR%\MYWK"
SET /p WK=<"%TMPDIR%\MYWK"
DEL "%TMPDIR%\MYWK"
IF "%DEBUG%"=="true" (
   echo Week Number is %WK%
   set /p x=Press enter to continue
)
REM   First look for the literal "all" to signify all databases in etc/dblist.cfg
REM   then check etc/dblist.cfg for a matching "friendly name"
REM   lastly check to see if $1 is a path name
IF "%IP1%"=="all" (
   IF NOT EXIST "%PROTOP%\etc\dblist.cfg" (
      echo Error: Cannot find %PROTOP%\etc\dblist.cfg - exiting
      GOTO :ABEND
   )
   FOR /F "usebackq tokens=1,2 delims=|" %%A IN ("%PROTOP%\etc\dblist.cfg") DO (
      set FRNAME=%%A
     set DB=%%B
      IF NOT "!FRNAME:~0,1!"=="#" (
         CALL :SUB_ROLL
      )
   )
   GOTO :THIN
)
 
REM   Is it a "friendly name" defined in etc/dblist.cfg
FOR /F "usebackq tokens=1,2 delims=|" %%A IN ("%PROTOP%\etc\dblist.cfg") DO (
   set FRNAME=%%A
   set DB=%%B
   IF "%IP1%"=="!FRNAME!" (
      CALL :SUB_ROLL
      GOTO :THIN
   )
   IF "%DEBUG%"=="true" (
      echo IP1 = %IP1%
      echo FRNAME = !FRNAME!
      set /p x=Press enter to continue
   )
)
 
REM Full DB pathname passed as parameter
IF EXIST "%IP1%" (
   SET DB=%IP1%
   basename "%IP1%" ".db" > "%TMPDIR%\basename.tmp"
   set /p FRNAME=<"%TMPDIR%\basename.tmp"
   del "%TMPDIR%\basename.tmp"
   CALL :SUB_ROLL
   GOTO :THIN
)
 
IF EXIST "%IP1%.db" (
   SET DB=%IP1%
   basename "%IP1%" ".db" > "%TMPDIR%\basename.tmp"
   set /p FRNAME=<"%TMPDIR%\basename.tmp"
   del "%TMPDIR%\basename.tmp"
   CALL :SUB_ROLL
   GOTO :THIN
) else (
   echo Unknown database %IP1%
   GOTO :ABEND
)
REM Are we thinning the herd?
:THIN
IF "%DEBUG%"=="true" (
   echo In :THIN
   echo LOGHIST = %LOGHIST%
   echo FLOGHIST = %FLOGHIST%
   echo RLOG = %RLOG%
   set /p x=Press enter to continue
)
set /a LOGDAYS="%LOGHIST% * 7"
set /a FLOGDAYS="%FLOGHIST% * 7"
IF NOT "%LOGHIST%"=="0" (
   echo Cleaning up any archived log files older than %LOGHIST% weeks >>"%RLOG%" 2>&1
   forfiles /p "%LGARCDIR%" /m *.lg.* /c "cmd /c %EKKO% del @path" /d -%LOGDAYS% 2>NUL
)
IF NOT "%FLOGHIST%"=="0" (
   echo Cleaning up any archived log files older than %FLOGHIST% weeks >>"%RLOG%" 2>&1
   forfiles /p "%LGARCDIR%" /m *.lgf.* /c "cmd /c %EKKO% del @path" /d -%FLOGDAYS% 2>NUL
)
GOTO :END
REM   Usage Function
:SUB_USAGE
   ECHO.
   ECHO Usage: oelogrot.cmd all^|friendlyname^|full_path_to_database -filter (optional)
   ECHO.
   EXIT /B
REM   Roll Logs Function
:SUB_ROLL
   set ONLINE=
   echo %DATE% %TIME% Rolling log for %FRNAME% >>"%RLOG%" 2>&1
   REM Check for .db extension
   if "%DB:~-3%" == ".db" (
      SET DBNAME=%DB:~0,-3%
   ) ELSE SET DBNAME=%DB%
 
   IF "%DEBUG%"=="true" (
      echo DB = %DB%
      echo DBNAME = %DBNAME%
      set /p x=Press enter to continue
   )
   %EKKO% call proutil "%DB%" -C holder >NUL 2>&1
   IF ERRORLEVEL 16 GOTO MULTIUSER
   IF ERRORLEVEL 14 GOTO SINGLEUSER
   IF ERRORLEVEL 0 GOTO CONTINUE
   GOTO :EOF
   :SINGLEUSER
   echo The database $DB is locked, logs not rolled
   echo The database $DB is locked, logs not rolled >> "%RLOG%" 2>&1
   GOTO :EOF
 
   :MULTIUSER
   IF "%DEBUG%"=="true" (
      echo In Multiuser
      echo DB = %DB%
      echo DBNAME = %DBNAME%
      set /p x=Press enter to continue
   )
   SET ONLINE=-online
   IF "%DEBUG%"=="true" (
      echo ONLINE = %ONLINE%
     set /p x=Press enter to continue
   )
 
   :CONTINUE
 
   %EKKO% copy "%DBNAME%.lg" "%LGARCDIR%\%FRNAME%.lg.%WK%" >> "%RLOG%" 2>&1
   IF ERRORLEVEL 1 (
      echo Copy of database log %DBNAME%.lg failed - exiting
      GOTO :EOF
   )
 
   %EKKO% call prolog "%DB%" %ONLINE% >> "%RLOG%" 2>&1
   IF NOT ERRORLEVEL 0 (
      CALL "%PROTOP%\bin\sendalert" %FRNAME% -m prolog -type alarm -msg "prolog failed during log roll"
      GOTO :ABEND
   ) else (
      CALL "%PROTOP%\bin\sendalert" %FRNAME% -m prolog -type info -msg "prolog completed successfully"
   )
 
   IF "%DEBUG%"=="true" (
      echo FILT = %FILT%
      echo pattern = %TMPDIR%\logrotcfg.tmp
      echo logfile = %LGARCDIR%\%FRNAME%.lg
      set /p x=Press enter to continue
   )
   IF "%FILT%"=="true" (
      IF EXIST "%TMPDIR%\logrotcfg.tmp" (
         echo Filtering %LGARCDIR%\%FRNAME%.lg.%WK% to %LGARCDIR%\%FRNAME%.lgf.%WK% >> "%RLOG%"
         grep -v -f "%TMPDIR%\logrotcfg.tmp" "%LGARCDIR%\%FRNAME%.lg.%WK%" > "%LGARCDIR%\%FRNAME%.lgf.%WK%"
      )
   )
   EXIT /B
REM Label ABEND for any abnormal end to script
REM Any error processing can go here
:ABEND
REM Finished - All done - bail out
