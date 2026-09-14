@echo off
cls
title CONTABILITA - PUSH GITHUB

echo ==========================================
echo       CONTABILITA - PUSH SU GITHUB
echo ==========================================
echo.

cd /d "%~dp0"

if not exist ".git" (
    echo Inizializzo il repository...
    git init
    git branch -M main
    git remote add origin https://github.com/marichr1975-dot/Contabilita.git
) else (
    git remote get-url origin >nul 2>&1
    if errorlevel 1 git remote add origin https://github.com/marichr1975-dot/Contabilita.git
)

echo.
echo Aggiungo i file...
git add .

echo.
echo Creo il commit...
git commit -m "Prima versione Contabilita"

echo.
echo PUSH SU GITHUB...
git push -u origin main

echo.
echo ==========================================
echo              OPERAZIONE TERMINATA
echo ==========================================
echo.
pause
