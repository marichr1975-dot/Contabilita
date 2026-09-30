@echo off
setlocal EnableExtensions
cls
title CONTABILITA - PUSH GITHUB

cd /d "%~dp0"

echo ==========================================
echo       CONTABILITA - PUSH SU GITHUB
echo ==========================================
echo.

if not exist ".git" (
    echo ERRORE: cartella Git non trovata.
    echo Metti questo BAT nella cartella principale di Contabilita.
    pause
    exit /b 1
)

if not exist "ios\project.yml" (
    echo ERRORE: ios\project.yml non trovato.
    echo Controlla di aver sovrascritto correttamente i file dello ZIP.
    pause
    exit /b 1
)

echo ==========================================
echo CONFIGURO IDENTITA GIT
echo ==========================================
echo.

REM Identita usata SOLO in questo repository.
REM Non modifica la configurazione Git globale del PC.
git config user.name "Christian Marini"
git config user.email "marichr1975-dot@users.noreply.github.com"

REM Assicura il repository GitHub corretto.
git remote set-url origin https://github.com/marichr1975-dot/Contabilita.git 2>nul
if errorlevel 1 git remote add origin https://github.com/marichr1975-dot/Contabilita.git

git branch -M main

echo Nome: Christian Marini
echo Email Git: marichr1975-dot@users.noreply.github.com
echo.
echo Remote:
git remote -v
echo.

echo ==========================================
echo AGGIUNGO TUTTI I FILE
echo ==========================================
echo.

git add -A

echo FILE PRONTI PER IL COMMIT:
echo ------------------------------------------
git status --short
echo ------------------------------------------
echo.

git diff --cached --quiet
if %errorlevel%==0 (
    echo NESSUNA MODIFICA DA INVIARE.
    echo.
    echo Se hai appena copiato i file dello ZIP,
    echo controlla di essere nella cartella corretta.
    echo.
    pause
    exit /b 0
)

echo ==========================================
echo CREAZIONE COMMIT
echo ==========================================
echo.

git commit -m "Contabilita: fotocamera OCR e analisi intelligente"

if errorlevel 1 (
    echo.
    echo *** ERRORE DURANTE IL COMMIT ***
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
    echo ==========================================
    echo *** ERRORE DURANTE IL PUSH ***
    echo ==========================================
    echo.
    echo Il commit e' stato creato localmente,
    echo ma GitHub non ha accettato il push.
    echo.
    pause
    exit /b 1
)

echo.
echo ==========================================
echo       PUSH COMPLETATO CORRETTAMENTE
echo ==========================================
echo.

echo COMMIT INVIATO:
git rev-parse --short HEAD
echo.

echo VERIFICA GITHUB:
git ls-remote origin refs/heads/main

echo.
echo ==========================================
echo Il progetto e' stato inviato a GitHub.
echo Ora il workflow GitHub Actions puo' partire.
echo ==========================================
echo.
pause
endlocal
