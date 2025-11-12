# PowerShell script to help install Flutter on Windows
Write-Host "Delhi Jewel - Flutter Installation Helper" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Flutter is already installed
$flutterInstalled = Get-Command flutter -ErrorAction SilentlyContinue

if ($flutterInstalled) {
    Write-Host "Flutter is already installed!" -ForegroundColor Green
    flutter --version
} else {
    Write-Host "Flutter is not installed." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To install Flutter:" -ForegroundColor Cyan
    Write-Host "1. Download Flutter SDK from: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor White
    Write-Host "2. Extract the zip file to a location (e.g., C:\src\flutter)" -ForegroundColor White
    Write-Host "3. Add Flutter to your PATH environment variable" -ForegroundColor White
    Write-Host "4. Run 'flutter doctor' to verify installation" -ForegroundColor White
    Write-Host ""
    Write-Host "Alternatively, you can use Chocolatey:" -ForegroundColor Cyan
    Write-Host "choco install flutter" -ForegroundColor White
    Write-Host ""
    Write-Host "Or use Git to clone Flutter:" -ForegroundColor Cyan
    Write-Host "git clone https://github.com/flutter/flutter.git -b stable" -ForegroundColor White
}

Write-Host ""
Write-Host "After installing Flutter, run:" -ForegroundColor Cyan
Write-Host "  cd frontend" -ForegroundColor White
Write-Host "  flutter pub get" -ForegroundColor White
Write-Host "  flutter run" -ForegroundColor White

