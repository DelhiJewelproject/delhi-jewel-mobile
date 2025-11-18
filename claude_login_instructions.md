# Claude CLI Login Instructions

## ✅ Claude Code is Already Installed

Claude Code CLI is installed on your system via npm.

## 🔐 How to Login

### Method 1: Direct Login Command

Open PowerShell and run:

```powershell
claude /login
```

This will:
1. Open a browser window
2. Show a login URL
3. Allow you to authenticate with your Claude account

### Method 2: Interactive Login

Simply run:

```powershell
claude
```

This opens an interactive session. If you're not logged in, it will prompt you to login.

## 📝 Usage Examples

Once logged in, you can use Claude from terminal:

```powershell
# Ask a question
claude "What is Flutter?"

# Interactive mode
claude

# Get help
claude --help
```

## ⚠️ Note About Cache Errors

The cache errors you see are non-critical warnings. They won't prevent Claude from working. If they bother you, you can:

1. Run PowerShell as Administrator
2. Or ignore them - they don't affect functionality

## 🔍 Verify Installation

Check if Claude is installed:
```powershell
claude --version
```

Check if you're logged in:
```powershell
claude status
```

## 🆘 Troubleshooting

If login doesn't work:

1. **Clear cache:**
   ```powershell
   Remove-Item -Recurse -Force "$env:APPDATA\claude-code" -ErrorAction SilentlyContinue
   ```

2. **Reinstall:**
   ```powershell
   npm uninstall -g @anthropic-ai/claude-code
   npm install -g @anthropic-ai/claude-code
   ```

3. **Run as Administrator** if permission issues persist

## 📚 Official Documentation

Visit: https://docs.claude.com/en/docs/claude-code/quickstart


