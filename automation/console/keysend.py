#!/usr/bin/env python3
"""Send keystrokes to a libvirt VM console via virsh send-key (US QWERTY only).

Usage:
  keysend.py <domain> type "<string>"   # type literal text (no Enter)
  keysend.py <domain> key <name> [name...]   # e.g. enter, ctrl-c, down, tab, esc
  keysend.py <domain> screenshot <path>
"""
import subprocess
import sys
import time

# US QWERTY: char -> (keycode, needs_shift)
_LOWER = "qwertyuiopasdfghjklzxcvbnm"
_LOWER_CODES = [16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
                30, 31, 32, 33, 34, 35, 36, 37, 38,
                44, 45, 46, 47, 48, 49, 50]
_DIGIT_CODES = {"1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8, "8": 9, "9": 10, "0": 11}
_SHIFT_DIGIT_SYMBOLS = {"!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
                        "^": "6", "&": "7", "*": "8", "(": "9", ")": "0"}
_SYMBOL_CODES = {
    ".": 52, ",": 51, "/": 53, "-": 12, "=": 13, ";": 39, "'": 40,
    "[": 26, "]": 27, "\\": 43, "`": 41, " ": 57,
}
_SHIFT_SYMBOL_CODES = {
    ">": 52, "<": 51, "?": 53, "_": 12, "+": 13, ":": 39, '"': 40,
    "{": 26, "}": 27, "|": 43, "~": 41,
}

_NAMED_KEYS = {
    "enter": [28], "backspace": [14], "tab": [15], "esc": [1],
    "down": [108], "up": [103], "left": [105], "right": [106],
    "space": [57], "ctrl-c": [29, 46],
}

KEYCODE = {c: (code, False) for c, code in zip(_LOWER, _LOWER_CODES)}
KEYCODE.update({c: (code, True) for c, code in zip(_LOWER, _LOWER_CODES)})  # placeholder, overwritten below
for c, code in zip(_LOWER, _LOWER_CODES):
    KEYCODE[c] = (code, False)
    KEYCODE[c.upper()] = (code, True)
for d, code in _DIGIT_CODES.items():
    KEYCODE[d] = (code, False)
for sym, digit in _SHIFT_DIGIT_SYMBOLS.items():
    KEYCODE[sym] = (_DIGIT_CODES[digit], True)
for c, code in _SYMBOL_CODES.items():
    KEYCODE[c] = (code, False)
for c, code in _SHIFT_SYMBOL_CODES.items():
    KEYCODE[c] = (code, True)

SHIFT = 42


def send_key(domain: str, codes: list[int], holdtime: int = 60) -> None:
    cmd = ["sudo", "-n", "virsh", "send-key", domain, "--codeset", "linux",
           "--holdtime", str(holdtime)] + [str(c) for c in codes]
    subprocess.run(cmd, check=True, capture_output=True)


def type_string(domain: str, text: str, delay: float = 0.08) -> None:
    for ch in text:
        if ch not in KEYCODE:
            raise SystemExit(f"Unsupported character: {ch!r}")
        code, shift = KEYCODE[ch]
        codes = [SHIFT, code] if shift else [code]
        send_key(domain, codes)
        time.sleep(delay)


def send_named_keys(domain: str, names: list[str]) -> None:
    for name in names:
        codes = _NAMED_KEYS.get(name.lower())
        if codes is None:
            raise SystemExit(f"Unknown key name: {name}")
        send_key(domain, codes)
        time.sleep(0.15)


def screenshot(domain: str, path: str) -> None:
    subprocess.run(["sudo", "-n", "virsh", "screenshot", domain, path, "--screen", "0"],
                    check=True, capture_output=True)


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        raise SystemExit(2)
    domain, action, *rest = sys.argv[1:]
    if action == "type":
        type_string(domain, rest[0])
    elif action == "key":
        send_named_keys(domain, rest)
    elif action == "screenshot":
        screenshot(domain, rest[0])
    else:
        raise SystemExit(f"Unknown action: {action}")


if __name__ == "__main__":
    main()
