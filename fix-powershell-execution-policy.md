# Fix PowerShell Execution Policy Error

## Problem
```
npx.ps1 cannot be loaded because running scripts is disabled on this system
```

## Solution Options

### Option 1: Bypass for Current Session (Quick Fix)
Run this in your PowerShell terminal:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

Then try again:
```powershell
npx @anthropic-ai/claude-code
```

**Note:** This only works for the current PowerShell session. You'll need to run it again if you open a new terminal.

### Option 2: Change Execution Policy for Current User (Recommended)
Run PowerShell as Administrator, then:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

This allows:
- Local scripts to run
- Downloaded scripts to run if they're signed
- Safe for your user account only

### Option 3: Use Command Prompt Instead
If you prefer not to change PowerShell settings, use Command Prompt (cmd):
```cmd
npx @anthropic-ai/claude-code
```

### Option 4: Use Full Path to npx
Sometimes using the full path works:
```powershell
& "C:\Program Files\nodejs\npx.cmd" @anthropic-ai/claude-code
```

## Quick Fix Command (Copy & Paste)
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process; npx @anthropic-ai/claude-code
```

## Verify Fix
After changing the policy, verify:
```powershell
Get-ExecutionPolicy
```

Should show: `Bypass` (for session) or `RemoteSigned` (for user)

