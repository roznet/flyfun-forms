# Move my data: cross-platform fixtures

Files shared by the iOS and Android tests, so each platform proves it can read
what the other writes. Spec: `designs/future/move-my-data.md` §4 and §5.

All data here is self-describing dummy data (CLAUDE.md): `Fixture` people,
`TESTDOC…` document numbers, `ZZ-…` registrations, `example.invalid` emails.

| File | Written by | Read by |
|---|---|---|
| `android-plain.json` | Android `MoveMyDataFixturesTest` | iOS `MoveMyDataTests` (decode, import) and Android (drift guard) |
| `android-encrypted.ffdata` | Android `DataFileCrypto`, from `android-plain.json` | iOS `DataFileCryptoTests`, `DataTransferTests` |
| `ios-plain.json` | iOS `InterchangeFormatTests.iosFixture` | Android `MoveMyDataFixturesTest` (decode, tombstone merge), iOS (drift guard) |
| `ios-encrypted.ffdata` | iOS `DataFileCrypto`, from `ios-plain.json` | Android `MoveMyDataFixturesTest` |
| `reference_crypto.py` | | An independent Python implementation of §5, for checking either side |

Passphrase for both encrypted files: `Fixture-Café-rudder-alpha` (the `é` is
NFC-composed, so it also checks that both sides normalise alike).

## Regenerating

Each pair must be written together: the encrypted file is the plaintext file,
encrypted.

- **Android:** from `app/android`,
  `WRITE_MOVE_MY_DATA_FIXTURES=1 ./gradlew :core-logic:test --tests '*MoveMyDataFixturesTest*'`
- **iOS:** from `app/flyfun-forms`,
  `TEST_RUNNER_WRITE_MOVE_MY_DATA_FIXTURES=1 xcodebuild test -scheme flyfun-forms -project flyfun-forms.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:flyfun-formsTests/InterchangeFormatTests`

Then run the other platform's tests against the new files.

## Provenance of the current `ios-*` files

The first `ios-plain.json` and `ios-encrypted.ffdata` were written without
Xcode (the change was made in a Linux session): the JSON by hand in the shape
the Swift encoder produces, and encrypted with `reference_crypto.py`. The iOS
tests check the JSON decodes to exactly `InterchangeFormatTests.iosFixture` and
that `DataFileCrypto.swift` decrypts the file. Regenerate them from iOS (above)
once on a Mac, so the file Android decrypts is one Swift actually encrypted, and
delete this section.
