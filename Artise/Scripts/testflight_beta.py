#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Puts a TestFlight build in Artise's public beta, through the App Store Connect API.

Run by the Artise workflow (job "Public beta"), never by hand: the key and the reviewer's account are repository
secrets. Every step checks first, so running it again is safe:

1. The beta description, feedback email and links, in English and Spanish (Artise/store/beta).
2. Beta App Review's contact and the reviewer account, with the notes (review_notes.txt).
3. "What to Test" for this build.
4. The external group "Artise beta", with this build.
5. Beta App Review for this build, if it hasn't been sent yet.
6. The group's public link, once Apple allows it (after the first approved build). The link is printed.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (base64 of the .p8 file), BETA_BUILD (the build number),
BETA_CONTACT_FIRST_NAME, BETA_CONTACT_LAST_NAME, BETA_CONTACT_PHONE, BETA_CONTACT_EMAIL, BETA_REVIEW_USERNAME,
BETA_REVIEW_PASSWORD, BETA_REVIEW_RECOVERY_KEY.
"""
from __future__ import annotations

import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "co.artise.app"
GROUP_NAME = "Artise beta"
LOCALES = ("en-US", "es-MX")
MARKETING_URL = "https://artise.co"
PRIVACY_URL = "https://artise.co/privacy.html"
TEXTS = pathlib.Path(__file__).resolve().parent.parent / "store" / "beta"
TEXT_LIMIT = 4000  # Apple's limit for the description, "What to Test" and the reviewer notes.
SECRETS = ("BETA_CONTACT_FIRST_NAME", "BETA_CONTACT_LAST_NAME", "BETA_CONTACT_PHONE", "BETA_CONTACT_EMAIL",
           "BETA_REVIEW_USERNAME", "BETA_REVIEW_PASSWORD", "BETA_REVIEW_RECOVERY_KEY")
# Beta review states after which the build must not be sent again.
SENT_STATES = {"WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW", "BETA_APPROVED", "READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}


class BetaError(Exception):
    """Something to fix before the beta can go on; the message says what."""


def text(locale: str, name: str) -> str:
    """One of the beta texts, checked against Apple's limit."""
    value = (TEXTS / locale / f"{name}.txt").read_text(encoding="utf-8").strip()
    if not value or len(value) > TEXT_LIMIT:
        raise BetaError(f"{locale}/{name}.txt must have 1 to {TEXT_LIMIT} characters.")
    return value


def review_notes(env: dict) -> str:
    """The notes for Apple's reviewer, with the demo account filled in."""
    notes = (TEXTS / "review_notes.txt").read_text(encoding="utf-8").strip().format(
        username=env["BETA_REVIEW_USERNAME"], password=env["BETA_REVIEW_PASSWORD"],
        recovery_key=env["BETA_REVIEW_RECOVERY_KEY"])
    if len(notes) > TEXT_LIMIT:
        raise BetaError(f"review_notes.txt is longer than {TEXT_LIMIT} characters once filled in.")
    return notes


def missing_secrets(env: dict) -> list:
    return [name for name in SECRETS if not env.get(name, "").strip()]


def token(key_id: str, issuer_id: str, p8_base64: str) -> str:
    """A 20-minute App Store Connect token (ES256)."""
    import jwt  # Only the workflow needs it; the tests don't.
    key = base64.b64decode(p8_base64).decode()
    now = int(time.time())
    return jwt.encode({"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})


class AppStoreConnect:
    """The few App Store Connect calls the beta needs."""

    def __init__(self, bearer: str):
        self.bearer = bearer

    def call(self, method: str, path: str, body: dict | None = None) -> dict:
        request = urllib.request.Request(API + path, method=method,
                                         data=json.dumps(body).encode() if body is not None else None,
                                         headers={"Authorization": f"Bearer {self.bearer}",
                                                  "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            details = error.read().decode(errors="replace")
            raise ApiError(error.code, details) from None
        return json.loads(raw) if raw else {}


class ApiError(Exception):
    def __init__(self, status: int, details: str):
        super().__init__(f"App Store Connect answered {status}: {details}")
        self.status = status


def query(path: str, **params) -> str:
    return path + "?" + urllib.parse.urlencode(params)


def relationship(kind: str, identifier: str) -> dict:
    return {"data": {"type": kind, "id": identifier}}


def find_app(api) -> str:
    apps = api.call("GET", query("/v1/apps", **{"filter[bundleId]": BUNDLE_ID}))["data"]
    if not apps:
        raise BetaError(f"There's no app with the bundle ID {BUNDLE_ID} in App Store Connect.")
    return apps[0]["id"]


def find_build(api, app_id: str, number: str, wait_seconds: int = 1800, sleep=time.sleep) -> dict:
    """The build once Apple has processed it. A build just uploaded can take a few minutes to appear."""
    waited = 0
    while True:
        builds = api.call("GET", query("/v1/builds", **{"filter[app]": app_id, "filter[version]": number,
                                                       "sort": "-uploadedDate", "limit": "1"}))["data"]
        state = builds[0]["attributes"].get("processingState") if builds else None
        if state == "VALID":
            if builds[0]["attributes"].get("expired"):
                raise BetaError(f"Build {number} has expired. Upload a new one.")
            return builds[0]
        if state in ("FAILED", "INVALID"):
            raise BetaError(f"Apple couldn't process build {number} ({state}).")
        if waited >= wait_seconds:
            raise BetaError(f"Build {number} isn't ready in App Store Connect after {wait_seconds // 60} minutes.")
        print(f"Build {number}: {state or 'not there yet'}, waiting…")
        sleep(60)
        waited += 60


def upsert_localizations(api, existing_path: str, kind: str, parent: str, parent_id: str, values: dict) -> None:
    """Sets each locale's attributes, adding the locales that aren't there yet."""
    existing = {item["attributes"]["locale"]: item["id"] for item in api.call("GET", existing_path)["data"]}
    for locale, attributes in values.items():
        if locale in existing:
            api.call("PATCH", f"/v1/{kind}/{existing[locale]}",
                     {"data": {"type": kind, "id": existing[locale], "attributes": attributes}})
        else:
            api.call("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": {"locale": locale, **attributes},
                                                      "relationships": {parent: relationship(parent + "s", parent_id)}}})


def set_test_information(api, app_id: str, env: dict) -> None:
    upsert_localizations(api, f"/v1/apps/{app_id}/betaAppLocalizations", "betaAppLocalizations", "app", app_id, {
        locale: {"description": text(locale, "description"), "feedbackEmail": env["BETA_CONTACT_EMAIL"],
                 "marketingUrl": MARKETING_URL, "privacyPolicyUrl": PRIVACY_URL}
        for locale in LOCALES})
    detail = api.call("GET", f"/v1/apps/{app_id}/betaAppReviewDetail")["data"]
    api.call("PATCH", f"/v1/betaAppReviewDetails/{detail['id']}", {"data": {
        "type": "betaAppReviewDetails", "id": detail["id"], "attributes": {
            "contactFirstName": env["BETA_CONTACT_FIRST_NAME"], "contactLastName": env["BETA_CONTACT_LAST_NAME"],
            "contactPhone": env["BETA_CONTACT_PHONE"], "contactEmail": env["BETA_CONTACT_EMAIL"],
            "demoAccountRequired": True, "demoAccountName": env["BETA_REVIEW_USERNAME"],
            "demoAccountPassword": env["BETA_REVIEW_PASSWORD"], "notes": review_notes(env)}}})


def set_what_to_test(api, build_id: str) -> None:
    upsert_localizations(api, f"/v1/builds/{build_id}/betaBuildLocalizations", "betaBuildLocalizations", "build",
                         build_id, {locale: {"whatsNew": text(locale, "what_to_test")} for locale in LOCALES})


def beta_group(api, app_id: str) -> dict:
    groups = api.call("GET", query("/v1/betaGroups", **{"filter[app]": app_id, "filter[name]": GROUP_NAME}))["data"]
    external = [group for group in groups if not group["attributes"].get("isInternalGroup")]
    if external:
        return external[0]
    return api.call("POST", "/v1/betaGroups", {"data": {
        "type": "betaGroups", "attributes": {"name": GROUP_NAME, "feedbackEnabled": True},
        "relationships": {"app": relationship("apps", app_id)}}})["data"]


def add_build(api, group_id: str, build: dict) -> None:
    if build["attributes"].get("usesNonExemptEncryption") is None:
        # Info.plist says so already (ITSAppUsesNonExemptEncryption = NO): Matrix uses standard encryption only.
        api.call("PATCH", f"/v1/builds/{build['id']}", {"data": {
            "type": "builds", "id": build["id"], "attributes": {"usesNonExemptEncryption": False}}})
    api.call("POST", f"/v1/betaGroups/{group_id}/relationships/builds", {"data": [{"type": "builds", "id": build["id"]}]})


def submit_for_review(api, build_id: str) -> str:
    """Sends the build to Beta App Review unless it's there already. Returns its beta review state."""
    detail = api.call("GET", f"/v1/builds/{build_id}/buildBetaDetail")["data"]
    state = detail["attributes"].get("externalBuildState")
    if state in SENT_STATES:
        return state
    api.call("POST", "/v1/betaAppReviewSubmissions", {"data": {
        "type": "betaAppReviewSubmissions", "relationships": {"build": relationship("builds", build_id)}}})
    return "WAITING_FOR_BETA_REVIEW"


def enable_public_link(api, group: dict) -> str | None:
    """Turns on the group's public link, with no tester limit. Apple only allows it once a build is approved."""
    attributes = group["attributes"]
    if attributes.get("publicLinkEnabled") and attributes.get("publicLink"):
        return attributes["publicLink"]
    try:
        updated = api.call("PATCH", f"/v1/betaGroups/{group['id']}", {"data": {
            "type": "betaGroups", "id": group["id"],
            "attributes": {"publicLinkEnabled": True, "publicLinkLimitEnabled": False}}})["data"]
    except ApiError as error:
        if error.status not in (409, 422):
            raise
        print(f"The public link isn't on yet. {error}")
        return None
    return updated["attributes"].get("publicLink")


def run(api, env: dict, sleep=time.sleep) -> str | None:
    """Every step for the build in BETA_BUILD; returns the public link once there is one."""
    missing = missing_secrets(env)
    if missing:
        raise BetaError("Missing repository secrets: " + ", ".join(missing) + " (see Artise/store/README.md).")
    app_id = find_app(api)
    build = find_build(api, app_id, env["BETA_BUILD"], sleep=sleep)
    set_test_information(api, app_id, env)
    set_what_to_test(api, build["id"])
    group = beta_group(api, app_id)
    add_build(api, group["id"], build)
    state = submit_for_review(api, build["id"])
    print(f"Build {env['BETA_BUILD']} is in \"{GROUP_NAME}\". Beta App Review: {state}.")
    link = enable_public_link(api, group)
    if link:
        print(f"::notice title=Public link::{link}")
    else:
        print("::notice title=Public link::Not yet: Apple turns it on after the first approved build. "
              "Run this job again once Beta App Review approves the build.")
    return link


def main() -> int:
    env = dict(os.environ)
    try:
        api = AppStoreConnect(token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_P8"]))
        run(api, env)
    except (BetaError, ApiError) as error:
        print(f"::error title=Public beta::{error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
