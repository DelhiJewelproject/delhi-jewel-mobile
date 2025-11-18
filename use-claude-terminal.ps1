# Quick script to use Claude in terminal
# Usage: .\use-claude-terminal.ps1 "your question"

param(
    [string]$Question = ""
)

if ($Question -eq "") {
    # Interactive mode
    Write-Host "Starting Claude CLI in interactive mode..." -ForegroundColor Cyan
    Write-Host "Type your questions and press Enter. Type 'exit' to quit.`n" -ForegroundColor Yellow
    npx @anthropic-ai/claude-code
} else {
    # Single question mode
    Write-Host "Asking Claude: $Question`n" -ForegroundColor Cyan
    npx @anthropic-ai/claude-code $Question --print
}

