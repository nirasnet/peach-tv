#!/usr/bin/env python3
"""
Shares Peach Remote with family through TestFlight (external testing, so a plain email invite works).

  python3 scripts/testflight_invite.py                         # newest build → "Family" group, invite the default tester
  python3 scripts/testflight_invite.py --email someone@x.com --first Name

Upload a build first (scripts/upload-testflight.sh). The script waits for Apple to process it, fills the
TestFlight test information, adds the build and the tester to the "Family" group and submits the build for
Beta App Review (needed once per version for external testers; usually under a day). Apple emails the
tester when the build is approved.

Needs: pip install pyjwt cryptography requests; the API key in ~/.appstoreconnect/private_keys.
"""
import argparse, os, sys, time
import jwt, requests

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
BUNDLE = os.environ.get("BUNDLE_ID", "com.example.PeachRemote")
GROUP = "Family"
BASE = "https://api.appstoreconnect.apple.com"
CONTACT = {"contactFirstName": os.environ["CONTACT_FIRST"], "contactLastName": os.environ["CONTACT_LAST"],
           "contactEmail": os.environ["CONTACT_EMAIL"], "contactPhone": os.environ["CONTACT_PHONE"]}
DESCRIPTION = ("Peach TV is the Look Peach Family remote for our own Android TV. It shows whether the TV is on, "
               "locks it or turns it off, takes a snapshot of the screen, keeps a daily viewing history and "
               "enforces family TV hours and screen-time limits.")
REVIEW_NOTES = ("This app controls one specific family TV that runs our own agent app on the home network "
                "(or over Tailscale). Without that TV the app opens normally and shows the TV as offline; "
                "no account or login is involved. It is shared only with family members.")
_key = open(os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")).read()


def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now - 10, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      _key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def api(method, path, ok=(), **kw):
    r = requests.request(method, BASE + path, headers={"Authorization": "Bearer " + token(),
                                                       "Content-Type": "application/json"}, **kw)
    if r.status_code >= 400 and r.status_code not in ok:
        sys.exit(f"{method} {path} → {r.status_code}\n{r.text[:1500]}")
    return r.json() if r.text else {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--email", required=True)
    ap.add_argument("--first", default="Family")
    ap.add_argument("--last", default="Member")
    ap.add_argument("--build", help="build number to wait for (default: the newest uploaded)")
    args = ap.parse_args()

    apps = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"]
    if not apps:
        sys.exit(f"No app record for {BUNDLE}. Create it in App Store Connect: Apps → + → New App "
                 f"(iOS, name e.g. 'Peach TV Family', bundle ID {BUNDLE}, SKU peachremote).")
    app = apps[0]["id"]

    # The given (or newest) build, once processed. A fresh upload takes a few minutes to show up.
    query = f"&filter[version]={args.build}" if args.build else ""
    while True:
        builds = api("GET", f"/v1/builds?filter[app]={app}{query}&sort=-uploadedDate&limit=1")["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "NOT UPLOADED"
        if state == "VALID":
            break
        if state in ("FAILED", "INVALID"):
            sys.exit(f"Build processing {state}")
        print(f"waiting for the build ({state})…", flush=True)
        time.sleep(30)
    build = builds[0]["id"]
    print("build", builds[0]["attributes"]["version"])
    if builds[0]["attributes"].get("usesNonExemptEncryption") is None:
        api("PATCH", f"/v1/builds/{build}", json={"data": {"type": "builds", "id": build,
                                                           "attributes": {"usesNonExemptEncryption": False}}})

    # Test information.
    locs = api("GET", f"/v1/apps/{app}/betaAppLocalizations")["data"]
    attrs = {"description": DESCRIPTION, "feedbackEmail": CONTACT["contactEmail"]}
    if locs:
        api("PATCH", f"/v1/betaAppLocalizations/{locs[0]['id']}",
            json={"data": {"type": "betaAppLocalizations", "id": locs[0]["id"], "attributes": attrs}})
    else:
        api("POST", "/v1/betaAppLocalizations", json={"data": {"type": "betaAppLocalizations",
            "attributes": dict(attrs, locale="en-US"),
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
    detail = api("GET", f"/v1/apps/{app}/betaAppReviewDetail")["data"]
    api("PATCH", f"/v1/betaAppReviewDetails/{detail['id']}", json={"data": {"type": "betaAppReviewDetails",
        "id": detail["id"], "attributes": dict(CONTACT, demoAccountRequired=False, notes=REVIEW_NOTES)}})
    print("test information set")

    # External group with the build and the tester.
    groups = [g for g in api("GET", f"/v1/apps/{app}/betaGroups")["data"] if g["attributes"]["name"] == GROUP]
    if groups:
        group = groups[0]["id"]
    else:
        group = api("POST", "/v1/betaGroups", json={"data": {"type": "betaGroups", "attributes": {"name": GROUP},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]["id"]
    api("POST", f"/v1/betaGroups/{group}/relationships/builds",
        json={"data": [{"type": "builds", "id": build}]})
    found = api("GET", f"/v1/betaTesters?filter[email]={args.email}&filter[apps]={app}")["data"]
    if found:
        # 409 = already in the group.
        api("POST", f"/v1/betaGroups/{group}/relationships/betaTesters", ok=(409,),
            json={"data": [{"type": "betaTesters", "id": found[0]["id"]}]})
    else:
        api("POST", "/v1/betaTesters", json={"data": {"type": "betaTesters",
            "attributes": {"email": args.email, "firstName": args.first, "lastName": args.last},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group}]}}}})
    print(f"{args.email} is in the {GROUP} group")

    # Beta App Review (409 = already submitted or approved).
    r = api("POST", "/v1/betaAppReviewSubmissions", ok=(409,), json={"data": {"type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build}}}}})
    if r.get("data"):
        print("submitted for Beta App Review:", r["data"]["attributes"].get("betaReviewState"))
    else:
        print("already submitted/approved:", (r.get("errors") or [{}])[0].get("detail", ""))
    print("Apple emails the invite once the build is approved for testing.")


if __name__ == "__main__":
    main()
