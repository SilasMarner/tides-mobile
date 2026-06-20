#!/usr/bin/env python3
"""Replace the Google Play listing's hi-res app icon (512x512).

upload_to_play.py only handles the AAB; the store listing graphics use a
different endpoint (edits.images). This pushes docs/icon-512.png as the
listing's `icon` for the given language.
"""
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
    ap = argparse.ArgumentParser()
    ap.add_argument("image", nargs="?",
                    default=os.path.join(os.path.dirname(__file__), "docs/icon-512.png"))
    ap.add_argument("--language", default="en-US")
    ap.add_argument("--image-type", default="icon")
    args = ap.parse_args()
    if not os.path.exists(args.image):
        sys.exit(f"Image not found: {args.image}")

    creds = service_account.Credentials.from_service_account_file(KEY_FILE, scopes=SCOPES)
    service = build("androidpublisher", "v3", credentials=creds)
    edits = service.edits()

    edit = edits.insert(packageName=PACKAGE_NAME).execute()
    edit_id = edit["id"]
    print(f"Opened edit: {edit_id}")

    # Clear the existing image of this type, then upload the new one.
    edits.images().deleteall(
        packageName=PACKAGE_NAME, editId=edit_id,
        language=args.language, imageType=args.image_type,
    ).execute()
    print(f"Cleared existing {args.image_type} ({args.language})")

    media = MediaFileUpload(args.image, mimetype="image/png", resumable=True)
    resp = edits.images().upload(
        packageName=PACKAGE_NAME, editId=edit_id,
        language=args.language, imageType=args.image_type,
        media_body=media,
    ).execute()
    print(f"Uploaded {args.image} -> sha={resp.get('image', {}).get('sha256', '?')[:12]}")

    edits.commit(packageName=PACKAGE_NAME, editId=edit_id).execute()
    print("Edit committed — listing icon is live.")


if __name__ == "__main__":
    main()
