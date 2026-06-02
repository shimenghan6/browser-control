@echo off
setlocal enabledelayedexpansion
chcp 65001 >/dev/null 2>&1
title browser-control 安装

echo.
echo   =============================================
echo    browser-control — 浏览器操控
echo   =============================================
echo.

echo [检测] Node.js...
where node >/dev/null 2>&1
if !errorlevel! neq 0 (
    echo   [错误] 未找到 Node.js
    pause
    exit /b 1
)
for /f "tokens=*" %%i in ('node -v') do echo   [完成] Node.js %%i

echo [检测] Python...
where python >/dev/null 2>&1
if !errorlevel! neq 0 (
    echo   [错误] 未找到 Python
    pause
    exit /b 1
)
for /f "tokens=*" %%i in ('python --version 2^>^&1') do echo   [完成] Python %%i

echo.
echo [1/3] 安装 Node.js 依赖...
call npm install -g agent-browser chrome-devtools-mcp
if !errorlevel! neq 0 (
    echo   [警告] npm 安装失败
)

echo [2/3] 安装 Python 依赖...
call pip install nodriver cloakbrowser
if !errorlevel! neq 0 (
    echo   [警告] pip 安装失败
)

echo [3/3] 配置 agent-browser...
echo { "headed": true } > "%USERPROFILE%gent-browser.json"
echo   [完成] agent-browser 已配置

:: 安装 SKILL.md
if exist "%~dp0SKILL.md" (
    if not exist "%USERPROFILE%\.claude\skillsrowser-control" mkdir "%USERPROFILE%\.claude\skillsrowser-control" 2>nul
    copy /Y "%~dp0SKILL.md" "%USERPROFILE%\.claude\skillsrowser-control\SKILL.md" >/dev/null 2>&1
    echo   [完成] SKILL.md 已安装
)

echo.
echo   =============================================
echo    安装完成！重启 Claude Code 即可使用。
echo    说："打开浏览器搜索 xxx"
echo   =============================================
echo.

endlocal
pause
