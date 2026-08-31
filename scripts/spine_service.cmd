@echo off
rem spine_service.cmd - keep the Mikee spine running permanently on this PC.
rem Launched (hidden) by the "MikeeSpine" scheduled task at every logon, so it
rem survives any terminal/Claude Code session ending - the failure that kept
rem taking the admin app "offline". Restarts the spine 5s after any exit; tsx
rem watch mode also keeps the touch-index.ts reload flow working.
rem Log: spine\spine_service.log
cd /d "%~dp0..\spine"
:loop
echo [%date% %time%] starting spine >> spine_service.log
call npm.cmd run dev >> spine_service.log 2>&1
echo [%date% %time%] spine exited ^(code %errorlevel%^) - restart in 5s >> spine_service.log
rem ping = console-free 5s sleep. timeout /t needs stdin; under the hidden
rem launch it returned instantly and the loop spun thousands of times at logoff.
ping -n 6 127.0.0.1 > nul
goto loop
