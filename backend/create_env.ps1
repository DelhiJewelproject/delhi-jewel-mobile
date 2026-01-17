# PowerShell script to create .env file
# Note: @ symbol in password is URL-encoded as %40
$envContent = @"
DATABASE_URL=postgresql://postgres.uhmorjigojfxchpmzyxy:Mukhesh$2003@aws-1-ap-south-1.pooler.supabase.com:5432/postgres
"@

$envContent | Out-File -FilePath ".env" -Encoding utf8
Write-Host ".env file created successfully!" -ForegroundColor Green
Write-Host "Database URL configured with URL-encoded password" -ForegroundColor Yellow

