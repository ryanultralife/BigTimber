@echo off
REM Build the Big Timber place file and open it in Roblox Studio.
setlocal

set ROJO=%USERPROFILE%\.local\bin\rojo.exe
set PLACE=BigTimber.rbxlx

if not exist "%ROJO%" (
    echo Rojo not found at %ROJO%
    echo Download from https://github.com/rojo-rbx/rojo/releases
    exit /b 1
)

echo Building %PLACE%...
"%ROJO%" build default.project.json --output %PLACE%
if errorlevel 1 (
    echo Build failed.
    exit /b 1
)

echo Opening %PLACE% in Roblox Studio...
start "" "%PLACE%"
endlocal
