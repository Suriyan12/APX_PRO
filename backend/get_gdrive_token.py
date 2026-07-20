"""
One-time helper: obtain a Google Drive OAuth refresh token for APX PRO.

Use this when the Google account is a personal Gmail (no Workspace/Shared
Drive). Files will be stored in — and count against the quota of — the
Google account you sign in with here.

Steps:
  1. Google Cloud Console → APIs & Services → Credentials
     → Create Credentials → OAuth client ID → Application type: "Desktop app"
     → download the JSON and save it as: backend/oauth_client.json
     (First time only: configure the OAuth consent screen, add your own
      Gmail address as a Test user.)
  2. Run:  venv\\Scripts\\python.exe get_gdrive_token.py
  3. A browser opens — sign in with the Google account that should hold the
     medical records and approve access.
  4. Copy the three printed lines into backend/.env

Requires:  pip install google-auth-oauthlib
"""
import json
import os
import sys

CLIENT_FILE = os.path.join(os.path.dirname(__file__), "oauth_client.json")
SCOPES = ["https://www.googleapis.com/auth/drive"]


def main():
    if not os.path.isfile(CLIENT_FILE):
        print(f"ERROR: {CLIENT_FILE} not found.")
        print("Download an OAuth client (Desktop app) JSON from Google Cloud "
              "Console → Credentials and save it as oauth_client.json.")
        sys.exit(1)

    try:
        from google_auth_oauthlib.flow import InstalledAppFlow
    except ImportError:
        print("ERROR: run  pip install google-auth-oauthlib  first.")
        sys.exit(1)

    flow = InstalledAppFlow.from_client_secrets_file(CLIENT_FILE, SCOPES)
    creds = flow.run_local_server(port=0, prompt="consent")

    client = json.load(open(CLIENT_FILE))["installed"]
    print("\nAdd these lines to backend/.env:\n")
    print(f"GDRIVE_OAUTH_CLIENT_ID={client['client_id']}")
    print(f"GDRIVE_OAUTH_CLIENT_SECRET={client['client_secret']}")
    print(f"GDRIVE_OAUTH_REFRESH_TOKEN={creds.refresh_token}")


if __name__ == "__main__":
    main()
