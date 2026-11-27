"""Checks that every Japanese UI string in Sources has an English translation.

Japanese source strings are the localization keys. `en.lproj` translates them and
`ja.lproj` maps each key to itself so macOS can select Japanese explicitly.
"""
import json
import plistlib
import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
JAPANESE = re.compile(r"[぀-ヿ㐀-鿿！-｠]")
PLACEHOLDER = "\0"
# String.LocalizationValue / LocalizedStringKey interpolations become these specifiers.
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|lf|f)")
ESCAPES = {"n": "\n", "t": "\t", "\"": "\"", "'": "'", "\\": "\\", "0": "\0"}


def swift_literals(source):
    """Yield (template, line) for each single-line string literal, including nested ones.

    Interpolations are replaced with PLACEHOLDER. Comments are skipped.
    """
    i, line, n = 0, 1, len(source)

    def parse_literal(start, start_line):
        # source[start] is the opening quote.
        j, text, nested = start + 1, [], []
        while j < n:
            c = source[j]
            if c == "\"":
                return j + 1, "".join(text), nested
            if c == "\\":
                nxt = source[j + 1]
                if nxt == "(":
                    j, inner = parse_interpolation(j + 2, start_line)
                    nested.extend(inner)
                    text.append(PLACEHOLDER)
                    continue
                text.append(ESCAPES.get(nxt, nxt))
                j += 2
                continue
            text.append(c)
            j += 1
        raise ValueError(f"unterminated literal at line {start_line}")

    def parse_interpolation(j, start_line):
        depth, found = 1, []
        while depth:
            c = source[j]
            if c == "\"":
                j, text, nested = parse_literal(j, start_line)
                found.append((text, start_line))
                found.extend(nested)
                continue
            depth += {"(": 1, ")": -1}.get(c, 0)
            j += 1
        return j, found

    while i < n:
        c = source[i]
        if source.startswith("//", i):
            i = source.find("\n", i)
            i = n if i < 0 else i
            continue
        if source.startswith("/*", i):
            end = source.find("*/", i)
            line += source.count("\n", i, end)
            i = end + 2
            continue
        if c == "\n":
            line += 1
        if c == "\"":
            if source.startswith("\"\"\"", i):
                end = source.find("\"\"\"", i + 3) + 3
                line += source.count("\n", i, end)
                i = end
                continue
            i, text, nested = parse_literal(i, line)
            yield text, line
            yield from nested
            continue
        i += 1


def source_templates():
    found = {}
    for path in sorted((ROOT / "Sources").rglob("*.swift")):
        # The classifier matches Japanese notification text and app names regardless of UI language.
        if path.relative_to(ROOT).as_posix() == "Sources/NotificationCore/Expression.swift":
            continue
        for text, line in swift_literals(path.read_text()):
            if JAPANESE.search(text):
                found.setdefault(text, f"{path.relative_to(ROOT)}:{line}")
    return found


def template_pattern(template):
    parts = (re.escape(part) for part in template.split(PLACEHOLDER))
    return re.compile(SPECIFIER.pattern.join(parts) + r"\Z")


def load_strings(path):
    data = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)],
                          check=True, capture_output=True).stdout
    return json.loads(data)


def specifiers(text):
    # Positional specifiers may reorder arguments; compare the multiset of types.
    return sorted(re.sub(r"\d+\$", "", s) for s in SPECIFIER.findall(text.replace("%%", "")))


class LocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.templates = source_templates()
        cls.en = load_strings(RESOURCES / "en.lproj/Localizable.strings")
        cls.ja = load_strings(RESOURCES / "ja.lproj/Localizable.strings")

    def test_every_source_string_has_an_english_translation(self):
        missing = [f"{where}: {text!r}" for text, where in self.templates.items()
                   if not any(template_pattern(text).match(key) for key in self.en)]
        self.assertEqual(missing, [], "Add these strings to Resources/en.lproj/Localizable.strings")

    def test_no_stale_translations(self):
        patterns = [template_pattern(text) for text in self.templates]
        stale = [key for key in self.en if not any(p.match(key) for p in patterns)]
        self.assertEqual(stale, [], "These keys are no longer used in Sources")

    def test_english_values_are_translated_and_keep_format_arguments(self):
        for key, value in self.en.items():
            with self.subTest(key=key):
                self.assertIsNone(JAPANESE.search(value), value)
                self.assertEqual(specifiers(value), specifiers(key))

    def test_japanese_table_covers_the_same_keys_unchanged(self):
        self.assertEqual(self.ja, {key: key for key in self.en})

    def test_info_plist_declares_bundled_localizations(self):
        info = plistlib.loads((RESOURCES / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleDevelopmentRegion"], "en")
        self.assertEqual(sorted(info["CFBundleLocalizations"]), ["en", "ja"])
        for language in info["CFBundleLocalizations"]:
            strings = load_strings(RESOURCES / f"{language}.lproj/InfoPlist.strings")
            self.assertEqual(set(strings), {"NSAccessibilityUsageDescription"})
        self.assertEqual(load_strings(RESOURCES / "en.lproj/InfoPlist.strings")["NSAccessibilityUsageDescription"],
                         info["NSAccessibilityUsageDescription"])

    def test_extractor_handles_interpolation_and_nested_literals(self):
        found = list(swift_literals('Text("バージョン \\(v ?? String(localized: "開発版"))") // "無視"\n"a\\n\\"b"'))
        self.assertEqual([text for text, _ in found], [f"バージョン {PLACEHOLDER}", "開発版", "a\n\"b"])


if __name__ == "__main__":
    unittest.main()
