@echo off
echo =============================================
echo  browser-control - One-Click Install
echo =============================================
echo.

where node >/dev/null 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Node.js not found.
    pause & exit /b 1
)
echo [OK] Node.js

where python >/dev/null 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python not found.
    pause & exit /b 1
)
echo [OK] Python

echo.
echo [1/3] Installing Node.js packages...
call npm install -g agent-browser chrome-devtools-mcp
echo [2/3] Installing Python packages...
call pip install nodriver cloakbrowser
echo [3/3] Configuring agent-browser...
echo { "headed": true } > "%USERPROFILE%\agent-browser.json"

echo.
echo =============================================
echo  Done. Use with Claude Code: /browser-control
echo =============================================
pause
