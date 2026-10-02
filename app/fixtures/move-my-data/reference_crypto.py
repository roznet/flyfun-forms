#!/usr/bin/env python3
"""Reference implementation of the "move my data" file encryption.

A third, independent reading of the layout in designs/future/move-my-data.md §5,
used to check the Android and iOS implementations against each other and to
produce a fixture where neither app can run (a Linux CI box, a cloud session).

    FFFORMS | 0x01 | salt(16) | nonce(12) | ciphertext || tag(16)
    key = PBKDF2-HMAC-SHA256(passphrase, salt, 210_000, 32)
    passphrase bytes = UTF-8 of NFC(strip(passphrase)), case kept

Usage:
    reference_crypto.py decrypt <file> <passphrase>            # plaintext to stdout
    reference_crypto.py encrypt <plain> <out> <passphrase>

Needs the `cryptography` package.
"""

import hashlib
import os
import sys
import unicodedata

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAGIC = b"FFFORMS"
VERSION = 1
ITERATIONS = 210_000


def normalise(passphrase: str) -> bytes:
    return unicodedata.normalize("NFC", passphrase.strip()).encode("utf-8")


def derive_key(passphrase: str, salt: bytes) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", normalise(passphrase), salt, ITERATIONS, 32)


def encrypt(plaintext: bytes, passphrase: str) -> bytes:
    salt, nonce = os.urandom(16), os.urandom(12)
    body = AESGCM(derive_key(passphrase, salt)).encrypt(nonce, plaintext, None)
    return MAGIC + bytes([VERSION]) + salt + nonce + body


def decrypt(data: bytes, passphrase: str) -> bytes:
    if not data.startswith(MAGIC) or data[len(MAGIC)] != VERSION:
        raise ValueError("not a FlyFun Forms data file")
    offset = len(MAGIC) + 1
    salt, nonce = data[offset:offset + 16], data[offset + 16:offset + 28]
    return AESGCM(derive_key(passphrase, salt)).decrypt(nonce, data[offset + 28:], None)


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "decrypt" and len(sys.argv) == 4:
        with open(sys.argv[2], "rb") as f:
            sys.stdout.buffer.write(decrypt(f.read(), sys.argv[3]))
    elif command == "encrypt" and len(sys.argv) == 5:
        with open(sys.argv[2], "rb") as f:
            blob = encrypt(f.read(), sys.argv[4])
        with open(sys.argv[3], "wb") as f:
            f.write(blob)
    else:
        sys.exit(__doc__)
