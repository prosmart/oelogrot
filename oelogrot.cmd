@ECHO off

::   Name:      oelogrot.cmd
::   Author:    Nigel Allen, Open Edge Solutions
::   Written:   January 2017
::   Purpose:   Log rotater and archiver for Progress Openedge log files.
::		based on original protop script

REM Uncomment next line to debug
REM set EKKO=echo


:: Delay variable expansion to runtime

Setlocal EnableDelayedExpansion

:: Grab environment vars

if "%PROTOP%"=="" (
   ECHO ERROR: PROTOP environment variable not set - exiting 
   GOTO :ABEND
)


IF NOT EXIST "%PROTOP%\bin\protopenv.bat" (
   ECHO Unable to locate %PROTOP%\bin\protopenv.bat
   GOTO :ABEND
)

CALL %PROTOP%\bin\protopenv.bat


IF "%TMPDIR%"=="" (
   ECHO ERROR: Temporary Directory TMPDIR not set - exiting
   GOTO :ABEND
)

IF "%LOGDIR%"=="" (
   ECHO ERROR: Logging Directory LOGDIR not set - exiting
   GOTO :ABEND
)

IF "%LGARCDIR%"=="" (
   ECHO ERROR: Log file Archive Directory LGARCDIR not set - exiting
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
set WK=

%PROTOP%\ubin\date.exe +%%W>MYWK
set /p WK=<MYWK
del MYWK

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
      IF NOT "!FRNAME:~0,1!"=="#" CALL :SUB_ROLL
   )
   GOTO :END
)

::	Is it a "friendly name" defined in etc/dblist.cfg?
FOR /F "tokens=1,2 delims=|" %%A IN (%PROTOP%\etc\dblist.cfg) DO (
   set FRNAME=%%A
   set DB=%%B
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


::	Roll Logs Function

:SUB_ROLL

   set RLOG=%LOGDIR%\logrotate.log
   set ONLINE=

   echo %DATE% %TIME% Rolling log for %FRNAME%
   echo %DATE% %TIME% Rolling log for %FRNAME% >>%RLOG% 2>&1

   FOR /F %%i in ("%DB%") DO @set DBNAME=%%~nxi

   %EKKO% call proutil %DB% -C holder >NUL 2>&1

   IF ERRORLEVEL 16 GOTO MULTIUSER
   IF ERRORLEVEL 14 GOTO SINGLEUSER
   IF ERRORLEVEL 0 GOTO CONTINUE
   GOTO :EOF

   :SINGLEUSER
   echo The database $DB is locked, logs not rolled
   echo The database $DB is locked, logs not rolled >> %RLOG% 2>&1
   GOTO :EOF

   :MULTIUSER
   SET ONLINE=-online

   :CONTINUE

   %EKKO% copy %DB%.lg %LGARCDIR%\%FRNAME%.lg.%WK% >NUL 2>&1

   IF ERRORLEVEL 1 (
      echo Copy of database log %DB%.lg failed - exiting
      GOTO :EOF
   )

   %EKKO% call prolog %DB% %ONLINE% >> %RLOG% 2>&1

   IF NOT ERRORLEVEL 0 (
      %PROTOP%\bin\sendalert %FRNAME% -msg="prolog failed during log roll"
   )


   EXIT /B


:ABEND

:END

