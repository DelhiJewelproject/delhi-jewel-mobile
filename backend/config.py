# """
# Database configuration helper
# """
# import os
# from pathlib import Path
# from urllib.parse import urlparse, parse_qs, urlencode, urlunparse
# from dotenv import load_dotenv

# # Get the directory where this config file is located
# BASE_DIR = Path(__file__).resolve().parent

# # Load .env file from the backend directory
# env_path = BASE_DIR / '.env'
# if env_path.exists():
#     # Try loading with dotenv first
#     load_dotenv(dotenv_path=env_path, override=True)
    
#     # If still not loaded, read file directly as fallback
#     if not os.getenv("DATABASE_URL"):
#         try:
#             # Try utf-8-sig to handle BOM, fallback to utf-8
#             try:
#                 with open(env_path, 'r', encoding='utf-8-sig') as f:
#                     content = f.read()
#             except:
#                 with open(env_path, 'r', encoding='utf-8') as f:
#                     content = f.read()
            
#             for line in content.splitlines():
#                 line = line.strip()
#                 if line and not line.startswith('#') and '=' in line:
#                     key, value = line.split('=', 1)
#                     os.environ[key.strip()] = value.strip()
#             print(f"Loaded .env directly from: {env_path}")
#         except Exception as e:
#             print(f"Error reading .env file: {e}")
#     else:
#         print(f"Loaded .env via dotenv from: {env_path}")
# else:
#     # Try loading from current directory as fallback
#     load_dotenv(override=True)
#     print(f".env file not found at {env_path}, trying current directory")

# # Debug: Check if DATABASE_URL is loaded
# db_url = os.getenv("DATABASE_URL", "")
# if db_url:
#     print(f"DATABASE_URL loaded successfully (length: {len(db_url)})")
# else:
#     print("WARNING: DATABASE_URL not found in environment variables")

# def get_database_url():
#     """
#     Get database URL and properly handle passwords with special characters
#     """
#     db_url = os.getenv("DATABASE_URL", "")
    
#     if not db_url:
#         raise ValueError("DATABASE_URL environment variable is not set")
    
#     # Parse the URL
#     parsed = urlparse(db_url)
    
#     # If password contains @, it might cause issues
#     # Check if there are multiple @ symbols (password@host)
#     if "@" in parsed.netloc and parsed.netloc.count("@") > 1:
#         # Split by @ and reconstruct properly
#         parts = parsed.netloc.split("@")
#         # First part should be user:password, rest is host:port
#         auth_part = parts[0]
#         host_part = "@".join(parts[1:])
#         parsed = parsed._replace(netloc=f"{auth_part}@{host_part}")
#         db_url = urlunparse(parsed)
    
#     return db_url

# def get_db_connection_params():
#     """
#     Parse database URL and return connection parameters for psycopg
#     This is more reliable than using the URL string directly
#     """
#     from urllib.parse import unquote
    
#     db_url = get_database_url()
#     parsed = urlparse(db_url)
    
#     # URL-decode the password (in case it was URL-encoded)
#     password = unquote(parsed.password) if parsed.password else None
    
#     # Extract connection parameters
#     # psycopg3 uses 'dbname' instead of 'database'
#     params = {
#         'host': parsed.hostname,
#         'port': parsed.port or 5432,
#         'dbname': parsed.path.lstrip('/'),
#         'user': parsed.username,
#         'password': password,
#     }
    
#     # Add SSL mode for Supabase
#     if parsed.hostname and ('supabase' in parsed.hostname or 'pooler' in parsed.hostname):
#         params['sslmode'] = 'require'
    
#     return params

# # For direct use: DATABASE_URL = get_database_url()

import os
import re
from pathlib import Path
from urllib.parse import urlparse, parse_qs, unquote

from dotenv import load_dotenv

ROOT_DIR = Path(__file__).resolve().parent
ENV_PATH = ROOT_DIR / ".env"

_ENV_LOADED = False


def _load_env():
    """
    Load the .env file, falling back to manual parsing if python-dotenv fails.
    This handles cases where the file has a BOM or otherwise unsupported syntax.
    """
    global _ENV_LOADED

    if _ENV_LOADED:
        return

    if ENV_PATH.exists():
        load_dotenv(dotenv_path=ENV_PATH, override=True)

        if not os.getenv("DATABASE_URL"):
            try:
                try:
                    contents = ENV_PATH.read_text(encoding="utf-8-sig")
                except UnicodeDecodeError:
                    contents = ENV_PATH.read_text(encoding="utf-8")

                pattern = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*[:=]\s*(.*)$")
                for line in contents.splitlines():
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue

                    if line.startswith("export "):
                        line = line[len("export ") :].strip()

                    match = pattern.match(line)
                    if not match:
                        continue

                    key, value = match.groups()
                    os.environ[key] = value.strip().strip("'\"")
            except Exception as exc:  # pragma: no cover - best-effort loader
                print(f"Failed to read .env manually: {exc}")
    else:
        load_dotenv(override=True)

    _ENV_LOADED = True


_load_env()

def get_database_url():
    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        raise ValueError("DATABASE_URL environment variable is not set")
    return db_url

def get_db_connection_params():
    db_url = get_database_url()
    parsed = urlparse(db_url)

    # Parse sslmode=? from query
    query_params = parse_qs(parsed.query)
    ssl_mode = query_params.get("sslmode", ["require"])[0]

    return {
        "host": parsed.hostname,
        "port": parsed.port or 5432,
        "dbname": parsed.path.lstrip("/"),
        "user": parsed.username,
        "password": unquote(parsed.password) if parsed.password else None,
        "sslmode": ssl_mode,
    }
