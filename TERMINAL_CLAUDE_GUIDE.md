# Using Claude in Terminal (Not GUI)

## Problem
When you type `claude`, it opens the GUI application instead of working in the terminal.

## Solution

### Option 1: Use npx (Recommended)
Always use `npx` to run the CLI version:

```powershell
# Interactive mode (terminal-based)
npx @anthropic-ai/claude-code

# Ask a question and get response in terminal
npx @anthropic-ai/claude-code "your question here" --print

# Login
npx @anthropic-ai/claude-code /login
```

### Option 2: Create an Alias
Add this to your PowerShell profile to create a `claude-cli` command:

```powershell
# Open your profile
notepad $PROFILE

# Add this line:
function claude-cli { npx @anthropic-ai/claude-code $args }
```

Then reload:
```powershell
. $PROFILE
```

Now use:
```powershell
claude-cli "your question"
```

### Option 3: Use the Wrapper Script
I've created a `claude-cli.ps1` script. You can use it:

```powershell
.\claude-cli.ps1 "your question"
```

Or add it to your PATH and use it from anywhere.

## Quick Examples

```powershell
# Start interactive terminal session
npx @anthropic-ai/claude-code

# Ask a question (prints response and exits)
npx @anthropic-ai/claude-code "What is Flutter?" --print

# Login to Claude
npx @anthropic-ai/claude-code /login

# Continue last conversation
npx @anthropic-ai/claude-code --continue

# Resume a specific session
npx @anthropic-ai/claude-code --resume
```

## Key Flags for Terminal Use

- `--print` or `-p`: Print response and exit (for scripts/pipes)
- `--output-format text`: Plain text output (default)
- `--output-format json`: JSON output
- `--continue` or `-c`: Continue most recent conversation
- `--resume [sessionId]`: Resume a specific conversation

## Why This Happens

You have two Claude installations:
1. **GUI App**: `C:\Users\oliva\AppData\Local\AnthropicClaude\claude.exe` (opens window)
2. **CLI Tool**: `@anthropic-ai/claude-code` npm package (terminal-based)

Windows finds the GUI `.exe` first in PATH, so it runs that instead of the CLI.

## Permanent Fix

To make `claude` always use the CLI, you can:

1. **Rename the GUI executable** (not recommended - might break other things)
2. **Use npx** (recommended - always works)
3. **Create an alias** (convenient for daily use)

