@echo off
rem spine_service.cmd — keep the Mikee spine running permanently on this PC.
rem Registered as the "MikeeSpine" scheduled task (runs at logon, survives any
rem terminal/Claude Code session ending — the failure that kept taking the
rem admin app "offline"). Restarts the spine 5s after any exit; tsx watch mode
rem also keeps the touch-index.ts reload flow working after IP repoints.
rem Log: spine\spine_service.log
cd /d "%~dp0..\spine"
:loop
echo [%date% %time%] starting spine >> spine_service.log
call npm.cmd run dev >> spine_service.log 2>&1
echo [%date% %time%] spine exited ^(code %errorlevel%^) - restart in 5s >> spine_service.log
timeout /t 5 /nobreak > nul
goto loop
