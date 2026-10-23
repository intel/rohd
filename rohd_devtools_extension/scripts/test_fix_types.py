import unittest

from fix_types import remove_obvious_types


class RemoveObviousTypesTest(unittest.TestCase):
    def test_preserves_string_literal_delimiters(self):
        literals = [
            "'hello'",
            '"hello"',
            "''",
            '""',
            "'say \"hello\"'",
            '"say \'hello\'"',
            r"'it\'s hello'",
            r'"say \"hello\""',
            "'''hello\nworld'''",
            '"""hello\nworld"""',
        ]
        for literal in literals:
            with self.subTest(literal=literal):
                source = f"final String label = {literal};"
                expected = f"final label = {literal};"
                self.assertEqual(remove_obvious_types(source), expected)
                self.assertEqual(remove_obvious_types(expected), expected)

    def test_preserves_other_type_removal(self):
        source = "final bool enabled = true;\nfinal int count = 42;"
        expected = "final enabled = true;\nfinal count = 42;"
        self.assertEqual(remove_obvious_types(source), expected)


if __name__ == "__main__":
    unittest.main()
