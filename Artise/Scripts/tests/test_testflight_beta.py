#
# Copyright 2026 Artise.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Tests for testflight_beta.py. Run: python3 -m unittest discover -s Artise/Scripts/tests"""
import pathlib
import sys
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))

import testflight_beta as beta  # noqa: E402

ENV = {"BETA_BUILD": "113", "BETA_CONTACT_FIRST_NAME": "Ana", "BETA_CONTACT_LAST_NAME": "Pérez",
       "BETA_CONTACT_PHONE": "+52 55 0000 0000", "BETA_CONTACT_EMAIL": "beta@example.com",
       "BETA_REVIEW_USERNAME": "demo", "BETA_REVIEW_PASSWORD": "pw-123", "BETA_REVIEW_RECOVERY_KEY": "EsT0 abcd"}
LINK = "https://testflight.apple.com/join/AbCdEf12"


class TextTests(unittest.TestCase):
    def test_texts_exist_in_both_languages_within_apple_limits(self):
        """Scenario: the committed beta texts. Expected: both languages have a description and "What to Test", each within 4,000 characters."""
        for locale in beta.LOCALES:
            for name in ("description", "what_to_test"):
                self.assertLessEqual(len(beta.text(locale, name)), beta.TEXT_LIMIT)

    def test_review_notes_carry_the_demo_account(self):
        """Scenario: notes filled in with the secrets. Expected: workspace, username, password and recovery key appear, no placeholder is left."""
        notes = beta.review_notes(ENV)
        for value in ("artise.co", "demo", "pw-123", "EsT0 abcd"):
            self.assertIn(value, notes)
        self.assertNotIn("{", notes)

    def test_missing_secrets_are_named(self):
        """Scenario: no password and an empty phone. Expected: both secrets are named, nothing is called."""
        env = dict(ENV, BETA_CONTACT_PHONE=" ")
        del env["BETA_REVIEW_PASSWORD"]
        api = FakeConnect()
        with self.assertRaises(beta.BetaError) as raised:
            beta.run(api, env)
        self.assertIn("BETA_CONTACT_PHONE", str(raised.exception))
        self.assertIn("BETA_REVIEW_PASSWORD", str(raised.exception))
        self.assertEqual(api.calls, [])


class RunTests(unittest.TestCase):
    def test_first_run_sets_everything_and_submits(self):
        """Scenario: nothing set up yet. Expected: texts in both languages, review details, a new external group with the build, a review submission; no link before approval."""
        api = FakeConnect()
        self.assertIsNone(beta.run(api, ENV, sleep=lambda _: None))
        posted = [path for method, path, _ in api.calls if method == "POST"]
        self.assertEqual(posted.count("/v1/betaAppLocalizations"), 2)
        self.assertEqual(posted.count("/v1/betaBuildLocalizations"), 2)
        self.assertIn("/v1/betaGroups", posted)
        self.assertIn("/v1/betaGroups/group-1/relationships/builds", posted)
        self.assertIn("/v1/betaAppReviewSubmissions", posted)
        group = api.body("POST", "/v1/betaGroups")["data"]["attributes"]
        self.assertEqual(group["name"], "Artise beta")
        review = api.body("PATCH", "/v1/betaAppReviewDetails/review-1")["data"]["attributes"]
        self.assertEqual((review["demoAccountName"], review["demoAccountPassword"]), ("demo", "pw-123"))
        self.assertTrue(review["demoAccountRequired"])
        spanish = [body for method, path, body in api.calls if path == "/v1/betaAppLocalizations" and method == "POST"
                   and body["data"]["attributes"]["locale"] == "es-MX"][0]["data"]["attributes"]
        self.assertEqual(spanish["feedbackEmail"], "beta@example.com")
        self.assertIn("Artise", spanish["description"])
        compliance = api.body("PATCH", "/v1/builds/build-113")["data"]["attributes"]
        self.assertEqual(compliance, {"usesNonExemptEncryption": False})

    def test_second_run_updates_and_turns_on_the_link(self):
        """Scenario: run again after approval. Expected: texts are updated in place, the build isn't sent again, the existing group is reused, and its public link is returned."""
        api = FakeConnect(localized=True, group=True, review_state="BETA_APPROVED", link_allowed=True, encryption=False)
        self.assertEqual(beta.run(api, ENV, sleep=lambda _: None), LINK)
        posted = [path for method, path, _ in api.calls if method == "POST"]
        self.assertEqual(posted, ["/v1/betaGroups/group-1/relationships/builds"])
        link = api.body("PATCH", "/v1/betaGroups/group-1")["data"]["attributes"]
        self.assertEqual(link, {"publicLinkEnabled": True, "publicLinkLimitEnabled": False})

    def test_waits_for_processing(self):
        """Scenario: the build is still processing for two checks. Expected: it waits a minute each time, then carries on."""
        slept = []
        api = FakeConnect(processing_checks=2)
        beta.run(api, ENV, sleep=slept.append)
        self.assertEqual(slept, [60, 60])

    def test_a_build_apple_rejected_stops(self):
        """Scenario: Apple couldn't process the build. Expected: a clear error, and nothing is changed."""
        api = FakeConnect(processing_state="INVALID")
        with self.assertRaises(beta.BetaError):
            beta.run(api, ENV, sleep=lambda _: None)
        self.assertFalse([call for call in api.calls if call[0] != "GET"])


class FakeConnect:
    """App Store Connect as the script sees it: answers by method and path, and records every call."""

    def __init__(self, localized=False, group=False, review_state="READY_FOR_BETA_SUBMISSION", link_allowed=False,
                 encryption=None, processing_checks=0, processing_state="VALID"):
        self.localized = localized
        self.group = group
        self.review_state = review_state
        self.link_allowed = link_allowed
        self.encryption = encryption
        self.processing_checks = processing_checks
        self.processing_state = processing_state
        self.calls = []

    def body(self, method, path):
        return next(body for m, p, body in self.calls if m == method and p == path)

    def call(self, method, path, body=None):
        self.calls.append((method, path, body))
        if method == "GET":
            return self.get(path)
        if method == "PATCH" and path == "/v1/betaGroups/group-1":
            if not self.link_allowed:
                raise beta.ApiError(409, "STATE_ERROR")
            return {"data": {"id": "group-1", "attributes": {"publicLinkEnabled": True, "publicLink": LINK}}}
        if method == "POST" and path == "/v1/betaGroups":
            return {"data": {"id": "group-1", "attributes": {"name": "Artise beta", "isInternalGroup": False}}}
        return {}

    def get(self, path):
        if path.startswith("/v1/apps?"):
            return {"data": [{"id": "app-1"}]}
        if path.startswith("/v1/builds?"):
            if self.processing_checks:
                self.processing_checks -= 1
                return {"data": [{"id": "build-113", "attributes": {"processingState": "PROCESSING"}}]}
            return {"data": [{"id": "build-113", "attributes": {
                "processingState": self.processing_state, "expired": False, "usesNonExemptEncryption": self.encryption}}]}
        if path.endswith("/betaAppLocalizations") or path.endswith("/betaBuildLocalizations"):
            items = [{"id": f"loc-{locale}", "attributes": {"locale": locale}} for locale in beta.LOCALES]
            return {"data": items if self.localized else []}
        if path.endswith("/betaAppReviewDetail"):
            return {"data": {"id": "review-1", "attributes": {}}}
        if path.startswith("/v1/betaGroups?"):
            internal = {"id": "internal", "attributes": {"name": "Artise beta", "isInternalGroup": True}}
            external = {"id": "group-1", "attributes": {"name": "Artise beta", "isInternalGroup": False}}
            return {"data": [internal, external] if self.group else [internal]}
        if path.endswith("/buildBetaDetail"):
            return {"data": {"id": "detail", "attributes": {"externalBuildState": self.review_state}}}
        raise AssertionError(f"Unexpected GET {path}")


if __name__ == "__main__":
    unittest.main()
