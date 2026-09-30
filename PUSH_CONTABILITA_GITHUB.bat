@echo off
cls
title CONTABILITA - PUSH GITHUB

echo ==========================================
echo       CONTABILITA - PUSH SU GITHUB
echo ==========================================
echo.

cd /d "%~dp0"

echo CARTELLA REPOSITORY:
cd
echo.

if not exist ".git" (
    echo ERRORE: questa cartella non e' un repository Git.
    echo.
    pause
    exit /b 1
)

echo ==========================================
echo CONTROLLO MODIFICHE
echo ==========================================
echo.

git status --short
echo.

echo ==========================================
echo AGGIUNGO I FILE
echo ==========================================
echo.

git add .

echo.
echo FILE PRONTI PER IL COMMIT:
echo.
git status --short

echo.
echo ==========================================
echo CREO IL COMMIT
echo ==========================================
echo.

git commit -m "Aggiornamento Contabilita"

if errorlevel 1 (
    echo.
    echo *** ERRORE: COMMIT NON CREATO ***
    echo.
    pause
    exit /b 1
)

echo.
echo ==========================================
echo ALLINEAMENTO CON GITHUB
echo ==========================================
echo.

git pull --rebase origin main

if errorlevel 1 (
    echo.
    echo *** ERRORE DURANTE IL PULL/REBASE ***
    echo.
    echo Controlla eventuali conflitti Git.
    echo.
    pause
    exit /b 1
)

echo.
echo ==========================================
echo PUSH SU GITHUB
echo ==========================================
echo.

git push -u origin main

if errorlevel 1 (
    echo.
    echo *** ERRORE DURANTE IL PUSH ***
    echo.
    pause
    exit /b 1
)

echo.
echo ==========================================
echo   PUSH COMPLETATO CORRETTAMENTE
echo ==========================================
echo.
echo Il workflow GitHub Actions dovrebbe partire
echo automaticamente.
echo.
pause
