"""Deployment must never embed server credentials or accept local API URLs."""

import unittest

from scripts.build_render_web import public_configuration


class RenderConfigurationTests(unittest.TestCase):
    def settings(self):
        return {
            "FLOODSAFE_API_URL": "https://floodsafe-api.example/",
            "FLOODSAFE_SUPABASE_URL": "https://project.supabase.co",
            "FLOODSAFE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_example",
            "FLOODSAFE_DB_PASSWORD": "server-only-example",
            "FLOODSAFE_ALERT_PRINCIPALS": "server-only-example",
        }

    def test_only_public_allowlisted_values_are_returned(self):
        result = public_configuration(self.settings())
        self.assertEqual(len(result), 3)
        self.assertEqual(result["FLOODSAFE_API_URL"], "https://floodsafe-api.example")
        self.assertNotIn("server-only-example", result.values())

    def test_reject_local_missing_and_credential_bearing_origins(self):
        for value in (
            "",
            "http://example.com",
            "https://localhost",
            "https://127.0.0.1",
            "https://[::1]",
            "https://user:password@example.com",
            "https://example.com?token=private",
            "https://example.com/path",
            "https://example.com:invalid",
        ):
            with self.subTest(value=value):
                settings = self.settings()
                settings["FLOODSAFE_API_URL"] = value
                with self.assertRaises(ValueError):
                    public_configuration(settings)

    def test_reject_secret_key(self):
        settings = self.settings()
        settings["FLOODSAFE_SUPABASE_PUBLISHABLE_KEY"] = "sb_secret_example"
        with self.assertRaises(ValueError):
            public_configuration(settings)


if __name__ == "__main__":
    unittest.main()
