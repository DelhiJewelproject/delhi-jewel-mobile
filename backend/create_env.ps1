# PowerShell script to create .env file
$envContent = @"
DATABASE_URL=postgresql://postgres.uhmorjigojfxchpmzyxy:Munna2003@@aws-1-ap-south-1.pooler.supabase.com:5432/postgres
"@

$envContent | Out-File -FilePath ".env" -Encoding utf8
Write-Host ".env file created successfully!" -ForegroundColor Green
Write-Host "Database URL configured with password: Munna2003@" -ForegroundColor Yellow

