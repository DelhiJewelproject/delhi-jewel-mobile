"""
Database configuration helper
"""
import os
from dotenv import load_dotenv

load_dotenv()

def get_database_url():
    """
    Get database URL and fix any double @ symbols
    """
    db_url = os.getenv("DATABASE_URL", "")
    # Fix double @ in connection string (common issue with passwords containing @)
    if db_url.count("@") > 1:
        # Find the position after the password and before the host
        # Format: postgresql://user:password@host:port/db
        parts = db_url.split("@")
        if len(parts) > 2:
            # Reconstruct: first part + @ + rest joined with @
            # This handles passwords with @ symbols
            db_url = parts[0] + "@" + "@".join(parts[1:])
    return db_url

# For direct use: DATABASE_URL = get_database_url()

