# Manual Backend Status Check Instructions

## Quick Status
- ✅ **Server is responding**: HTTP 200 on http://13.202.81.19:9010/
- 📁 **Local file**: 175,538 bytes, modified: 30-01-2026 12:59

## To Check if Backend was Updated:

### Option 1: Using SSH (Recommended)
Open a terminal (PowerShell or CMD) and run:

```bash
ssh -i vbupdated.pem ubuntu@13.202.81.19
```

Once connected, run:
```bash
cd /home/ubuntu/delhi-jewel-mobile/backend

# Check file size and modification time
ls -lh main.py
stat main.py

# Check MD5 checksum
md5sum main.py

# Check service status
sudo systemctl status delhi-jewel-api
# OR
pm2 list
# OR
ps aux | grep uvicorn

# Check recent backups (shows when last deployment happened)
ls -lth main.py.backup.* | head -5
```

### Option 2: Compare Checksums

**Local MD5**: `A3163D4E567A7F271BC4404203588838`

To get server MD5, SSH and run:
```bash
md5sum /home/ubuntu/delhi-jewel-mobile/backend/main.py
```

If the checksums match → Backend is up to date ✅
If they don't match → Backend needs update ⚠️

### Option 3: Check File Modification Time

**Local file modified**: 30-01-2026 12:59

SSH to server and check:
```bash
stat /home/ubuntu/delhi-jewel-mobile/backend/main.py
```

Compare the modification time. If server file is older → needs update.

### Option 4: Check Backup Files

Recent deployments create backup files with timestamps. Check:
```bash
ls -lth /home/ubuntu/delhi-jewel-mobile/backend/main.py.backup.* | head -5
```

The most recent backup shows when the last deployment occurred.

## Quick Test Commands

Test if API is working:
```bash
curl http://13.202.81.19:9010/
```

Check if service is running:
```bash
curl http://13.202.81.19:9010/docs
```

## If Backend Needs Update

Run the deployment script:
```bash
.\deploy_and_restart.bat
```

Or manually:
```bash
scp -i vbupdated.pem main.py ubuntu@13.202.81.19:/home/ubuntu/delhi-jewel-mobile/backend/main.py
ssh -i vbupdated.pem ubuntu@13.202.81.19 "cd /home/ubuntu/delhi-jewel-mobile/backend && sudo systemctl restart delhi-jewel-api"
```
