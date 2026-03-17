@echo off
echo =======================================================
echo     NSE Option Chain Bot - GitHub Push Helper
echo =======================================================

cd /d "%~dp0"

set "GIT_CMD=git"

echo Checking for Git...
where git >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Git not in system PATH. Checking common locations...
    
    if exist "C:\Program Files\Git\cmd\git.exe" (
        set "GIT_CMD=C:\Program Files\Git\cmd\git.exe"
    ) else if exist "C:\Program Files (x86)\Git\cmd\git.exe" (
        set "GIT_CMD=C:\Program Files (x86)\Git\cmd\git.exe"
    ) else if exist "%LocalAppData%\Programs\Git\cmd\git.exe" (
        set "GIT_CMD=%LocalAppData%\Programs\Git\cmd\git.exe"
    ) else (
        echo Checking for GitHub Desktop Git...
        for /d %%d in ("%LocalAppData%\GitHubDesktop\app-*") do (
            if exist "%%d\resources\app\git\cmd\git.exe" (
                set "GIT_CMD=%%d\resources\app\git\cmd\git.exe"
            )
        )
    )
)

if "%GIT_CMD%"=="git" (
    where git >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        echo [WARNING] Git was not found anywhere on your system.
        echo Please download Git from https://git-scm.com/ 
        echo or install GitHub Desktop to fix this automatically.
        pause
        exit /b
    )
)

echo [SUCCESS] Git found using: %GIT_CMD%

echo Initializing Git repository if needed...
if not exist .git (
    "%GIT_CMD%" init
    echo Git initialized.
) else (
    echo Git repository already exists.
)

echo Adding files...
"%GIT_CMD%" add .

echo Creating initial commit...
"%GIT_CMD%" commit -m "Initial commit - NSE Option Chain Bot"

echo Adding remote repository...
"%GIT_CMD%" remote add origin https://github.com/mybullandbear/RiteshPersonalChart 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo Remote 'origin' already exists, updating URL...
    "%GIT_CMD%" remote set-url origin https://github.com/mybullandbear/RiteshPersonalChart
)

echo Pushing to GitHub (main branch)...
"%GIT_CMD%" branch -M main

:: Using force push to resolve any "unrelated histories" crashes
"%GIT_CMD%" push -u origin main --force

echo =======================================================
echo [DONE] Push attempt completed.
echo If you get a login prompt, please authenticate.
echo =======================================================
pause
