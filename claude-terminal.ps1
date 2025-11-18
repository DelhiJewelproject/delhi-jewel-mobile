# Claude Terminal Launcher - Bypasses execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
& "C:\Program Files\nodejs\npx.cmd" @anthropic-ai/claude-code $args

