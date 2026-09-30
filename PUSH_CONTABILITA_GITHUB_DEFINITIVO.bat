@echo off
setlocal EnableExtensions
cls
title CONTABILITA - PUSH GITHUB DEFINITIVO

cd /d "%~dp0"

echo ==========================================
echo   CONTABILITA - PUSH GITHUB DEFINITIVO
echo ==========================================
echo.

if not exist ".git" (
    echo ERRORE: cartella Git non trovata.
    pause
    exit /b 1
)

if not exist "ios\project.yml" (
    echo ERRORE: ios\project.yml non trovato.
    echo Controlla di essere nella cartella principale di Contabilita.
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
echo 1 - SALVO I FILE DEL PROGETTO
echo ==========================================
echo.

git add -A

git diff --cached --quiet
if %errorlevel%==0 (
    echo Nessuna modifica nuova da committare.
) else (
    git commit -m "Contabilita: fotocamera OCR e analisi intelligente"
    if errorlevel 1 (
        echo.
        echo *** ERRORE COMMIT ***
        pause
        exit /b 1
    )
)

echo.
echo ==========================================
echo 2 - RECUPERO GITHUB
echo ==========================================
echo.

git fetch origin main
if errorlevel 1 (
    echo *** ERRORE FETCH GITHUB ***
    pause
    exit /b 1
)

echo.
echo ==========================================
echo 3 - UNISCO LE DUE STORIE
echo ==========================================
echo.
echo GitHub e il PC hanno storie separate.
echo Mantengo i FILE DEL PC come versione attuale.
echo.

git merge origin/main --allow-unrelated-histories -X ours --no-edit

if errorlevel 1 (
    echo.
    echo *** MERGE NON RIUSCITO ***
    echo.
    echo NON E' STATO FATTO ALCUN FORCE PUSH.
    echo Controllo lo stato Git:
    echo.
    git status --short
    echo.
    pause
    exit /b 1
)

echo.
echo ==========================================
echo 4 - CONTROLLO FINALE DEI FILE
echo ==========================================
echo.

git status --short

echo.
echo ==========================================
echo 5 - PUSH SU GITHUB
echo ==========================================
echo.

git push -u origin main

if errorlevel 1 (
    echo.
    echo ==========================================
    echo *** PUSH FALLITO ***
    echo ==========================================
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
echo PROGETTO CONTABILITA SINCRONIZZATO
echo ==========================================
echo.
pause
endlocal
