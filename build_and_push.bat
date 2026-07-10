@echo off
REM ============================================
REM  Build Script: Push to GitHub & Trigger Build
REM  Chay file nay de push code len GitHub
REM  GitHub Actions se tu dong build file .ipa
REM ============================================

echo.
echo ==========================================
echo   OCR Server Legacy - iOS 12 Build Script
echo ==========================================
echo.

cd /d "%~dp0"

REM Check if git is available
git --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Git chua duoc cai dat!
    echo Tai git tai: https://git-scm.com/download/win
    pause
    exit /b 1
)

echo [1/4] Checking git status...
git status

echo.
echo [2/4] Adding all files...
git add OcrServerLegacy/
git add .github/workflows/build-legacy.yml
git add project.yml

echo.
echo [3/4] Creating commit...
git commit -m "Add iOS 12 Legacy version - UIKit rewrite"

echo.
echo [4/4] Pushing to GitHub...
git push origin main

echo.
echo ==========================================
echo   DONE! Kiem tra build tai:
echo   https://github.com/YOUR_USERNAME/iOS-OCR-Server/actions
echo.
echo   Sau khi build xong (~5 phut):
echo   1. Vao tab Actions tren GitHub
echo   2. Click vao build moi nhat
echo   3. Cuon xuong phan Artifacts
echo   4. Tai file OcrServerLegacy-iOS12-IPA
echo   5. Giai nen ra file .ipa
echo   6. Dung Sideloadly de cai len iPhone
echo ==========================================
pause
