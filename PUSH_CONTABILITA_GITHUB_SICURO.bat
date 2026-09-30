@echo off
setlocal EnableExtensions
cls
title CONTABILITA - PUSH GITHUB SICURO

cd /d "%~dp0"

echo ==========================================
echo   CONTABILITA - PUSH GITHUB SICURO
echo ==========================================
echo.

if not exist ".git" (
    echo ERRORE: repository Git non trovato.
    pause
    exit /b 1
)

if not exist "ios\project.yml" (
    echo ERRORE: ios\project.yml non trovato.
    echo Controlla la cartella del progetto.
    pause
    exit /b 1
)

git config user.name "Christian Marini"
git config user.email "marichr1975-dot@users.noreply.github.com"
git remote set-url origin https://github.com/marichr1975-dot/Contabilita.git 2>nul
if errorlevel 1 git remote add origin https://github.com/marichr1975-dot/Contabilita.git
git branch -M main

echo.
echo ==========================================
echo 1 - SALVO LE MODIFICHE DELLO ZIP
echo ==========================================
echo.

git add -A

git diff --cached --quiet
if %errorlevel%==0 (
    echo Nessuna modifica nuova da committare.
    echo.
    goto PULL
)

git commit -m "Contabilita: fotocamera OCR e analisi intelligente"
if errorlevel 1 (
    echo ERRORE NEL COMMIT.
    pause
    exit /b 1
)

:PULL
echo.
echo ==========================================
echo 2 - RECUPERO AGGIORNAMENTI DA GITHUB
echo ==========================================
echo.

git fetch origin main
if errorlevel 1 (
    echo ERRORE: impossibile recuperare GitHub.
    pause
    exit /b 1
)

echo.
echo ==========================================
echo 3 - CONTROLLO SE GITHUB E' AVANTI
echo ==========================================
echo.

git merge-base --is-ancestor HEAD origin/main
if %errorlevel%==0 (
    echo La copia locale contiene gia' GitHub.
    goto PUSH
)

git merge-base --is-ancestor origin/main HEAD
if %errorlevel%==0 (
    echo GitHub non ha modifiche nuove.
    goto PUSH
)

echo GitHub e il PC hanno entrambi modifiche.
echo.
echo Tento il merge automatico senza cancellare i tuoi file.
echo.

git merge origin/main --no-edit
if errorlevel 1 (
    echo.
    echo ==========================================
    echo *** CONFLITTO GIT ***
    echo ==========================================
    echo.
    echo NON E' STATO FATTO ALCUN FORCE PUSH.
    echo I tuoi file NON vengono cancellati.
    echo.
    echo Ecco i file in conflitto:
    git status --short
    echo.
    echo Risolvi i conflitti e poi esegui nuovamente questo BAT.
    pause
    exit /b 1
)

:PUSH
echo.
echo ==========================================
echo 4 - PUSH SU GITHUB
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
echo       PUSH COMPLETATO CORRETTAMENTE
echo ==========================================
echo.

echo COMMIT LOCALE:
git rev-parse --short HEAD
echo.

echo COMMIT PRESENTE SU GITHUB:
git ls-remote origin refs/heads/main

echo.
echo ==========================================
echo Fine. Il progetto e' stato sincronizzato.
echo ==========================================
echo.
pause
endlocal
