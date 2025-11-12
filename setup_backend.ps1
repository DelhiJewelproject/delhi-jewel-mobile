# PowerShell script to setup Python backend
Write-Host "Delhi Jewel - Backend Setup" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan
Write-Host ""

# Check if Python is installed
$pythonInstalled = Get-Command python -ErrorAction SilentlyContinue

if (-not $pythonInstalled) {
    Write-Host "Python is not installed!" -ForegroundColor Red
    Write-Host "Please install Python 3.8 or higher from https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

Write-Host "Python version:" -ForegroundColor Green
python --version
Write-Host ""

# Navigate to backend directory
Set-Location backend

# Create virtual environment
Write-Host "Creating virtual environment..." -ForegroundColor Cyan
if (-not (Test-Path "venv")) {
    python -m venv venv
    Write-Host "Virtual environment created!" -ForegroundColor Green
} else {
    Write-Host "Virtual environment already exists." -ForegroundColor Yellow
}

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Cyan
& .\venv\Scripts\Activate.ps1

# Install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Cyan
pip install -r requirements.txt

Write-Host ""
Write-Host "Backend setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "To run the backend server:" -ForegroundColor Cyan
Write-Host "  cd backend" -ForegroundColor White
Write-Host "  .\venv\Scripts\Activate.ps1" -ForegroundColor White
Write-Host "  python main.py" -ForegroundColor White

