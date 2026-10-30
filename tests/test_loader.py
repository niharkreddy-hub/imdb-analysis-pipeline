"""Boundary tests for real TSV failure modes; no database or pandas required."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("loader", Path(__file__).parents[1] / "python/load_staging.py")
loader = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(loader)


class TSVValidationTests(unittest.TestCase):
    def inspect(self, content, header=("id", "title", "characters")):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.tsv"
            path.write_bytes(content)
            return loader.inspect_file(path, list(header))

    def test_literal_quotes_json_na_and_null_sentinel(self):
        raw = b'id\ttitle\tcharacters\ntt1\t"A quoted title"\t["A", "B"]\ntt2\tNA\t\\N\n'
        result = self.inspect(raw)
        self.assertEqual(result["rows"], 2)
        self.assertEqual(result["sha256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(result["bytes"], len(raw))

    def test_header_is_exact(self):
        with self.assertRaisesRegex(ValueError, "unexpected header"):
            self.inspect(b'id\twrong\tcharacters\ntt1\tA\t\\N\n')

    def test_wrong_width_is_never_skipped(self):
        for body in [b'tt1\tshort\n', b'tt1\ttoo\tmany\tfields\n']:
            with self.subTest(body=body), self.assertRaisesRegex(ValueError, "fields"):
                self.inspect(b'id\ttitle\tcharacters\n' + body)

    def test_empty_files(self):
        for raw in [b'', b'id\ttitle\tcharacters\n']:
            with self.subTest(raw=raw), self.assertRaisesRegex(ValueError, "no data rows"):
                self.inspect(raw)

    def test_invalid_encoding_and_control_bytes(self):
        for raw in [b'\x00', b'\x08', b'\r']:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                self.inspect(b'id\ttitle\tcharacters\ntt1\tA'+raw+b'B\t\\N\n')
        with self.assertRaises(UnicodeDecodeError):
            self.inspect(b'id\ttitle\tcharacters\ntt1\t\xff\t\\N\n')

    def test_copy_quotes_local_path_and_disables_csv_quoting(self):
        stmt = loader.copy_statement(Path("someone's data/title.basics.tsv"), "title_basics")
        self.assertIn("someone''s data", stmt)
        self.assertIn("QUOTE E'\\b'", stmt)
        self.assertIn("NULL '\\N'", stmt)

    def test_copy_rejects_newline_paths(self):
        with self.assertRaises(ValueError):
            loader.copy_statement(Path("bad\npath.tsv"), "title_basics")


if __name__ == "__main__":
    unittest.main()
