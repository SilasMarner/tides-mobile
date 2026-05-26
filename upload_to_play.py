#!/usr/bin/env python3
"""Upload a signed AAB to Google Play as a new internal-track release."""

import argparse
import os
import sys
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

PACKAGE_NAME = "com.mattbettinger.tides"
KEY_FILE = os.path.join(os.path.dirname(__file__), "play-service-account.json")
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]


def main():
    parser = argparse.ArgumentParser(description="Upload AAB to Google Play")
    parser.add_argument("aab", nargs="?", help="Path to the signed .aab file (omit with --promote)")
    parser.add_argument("--track", default="internal",
                        choices=["internal", "alpha", "beta", "production"],
                        help="Release track (default: internal)")
    parser.add_argument("--promote", metavar="VERSION_CODE", type=int,
                        help="Promote an existing version code to --track instead of uploading")
    parser.add_argument("--release-notes", default="Bug fixes and improvements",
                        help="Release notes text (English)")
    args = parser.parse_args()

    if not args.promote and not args.aab:
        sys.exit("Provide an AAB path or use --promote VERSION_CODE")
    if args.aab and not os.path.exists(args.aab):
        sys.exit(f"AAB not found: {args.aab}")

    creds = service_account.Credentials.from_service_account_file(KEY_FILE, scopes=SCOPES)
    service = build("androidpublisher", "v3", credentials=creds)
    edits = service.edits()

    # Open edit
    edit = edits.insert(packageName=PACKAGE_NAME).execute()
    edit_id = edit["id"]
    print(f"Opened edit: {edit_id}")

    if args.promote:
        version_code = args.promote
        print(f"Promoting existing versionCode {version_code} to {args.track}")
    else:
        # Upload bundle
        print(f"Uploading {args.aab} ...")
        media = MediaFileUpload(args.aab, mimetype="application/octet-stream", resumable=True)
        bundle = edits.bundles().upload(
            packageName=PACKAGE_NAME,
            editId=edit_id,
            media_body=media,
        ).execute()
        version_code = bundle["versionCode"]
        print(f"Uploaded bundle — versionCode: {version_code}")

    # Assign to track
    edits.tracks().update(
        packageName=PACKAGE_NAME,
        editId=edit_id,
        track=args.track,
        body={
            "track": args.track,
            "releases": [{
                "versionCodes": [version_code],
                "status": "completed",
                "releaseNotes": [{"language": "en-US", "text": args.release_notes}],
            }],
        },
    ).execute()
    print(f"Assigned to track: {args.track}")

    # Commit
    edits.commit(packageName=PACKAGE_NAME, editId=edit_id).execute()
    print("Edit committed — release is live on the track.")


if __name__ == "__main__":
    main()
