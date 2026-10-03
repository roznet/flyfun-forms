import Foundation
import CryptoKit
import CommonCrypto

/// Password-based encryption for the "Move my data" file.
///
/// The file leaves the app sandbox (Files, a share sheet, a chat app) and it
/// contains passport numbers, so encryption is the default and the plaintext
/// GDPR export is a separate, explicitly labelled action.
///
/// Must match Android's `DataFileCrypto.kt` byte for byte, so a file written on
/// one platform opens on the other. See designs/future/move-my-data.md §5:
///
///     "FFFORMS" | version 0x01 | salt(16) | nonce(12) | ciphertext ‖ tag(16)
///
/// AES-256-GCM, no AAD, with a PBKDF2-HMAC-SHA256 key (210,000 iterations).
/// CryptoKit has no PBKDF2, hence CommonCrypto for the key.
///
/// The cross-platform fixtures in `app/fixtures/move-my-data/` pin this down:
/// the tests decrypt a file Android wrote, and Android's tests decrypt one
/// written here.
enum DataFileCrypto {

    private static let magic = Data("FFFORMS".utf8)
    private static let version: UInt8 = 1
    private static let saltBytes = 16
    private static let nonceBytes = 12
    private static let tagBytes = 16
    private static let keyBytes = 32

    /// OWASP's 2023 floor for PBKDF2-HMAC-SHA256, as on Android.
    private static let iterations: UInt32 = 210_000

    private static var headerBytes: Int { magic.count + 1 + saltBytes + nonceBytes }

    enum Failure: LocalizedError, Equatable {
        case notOurFile
        case wrongPassphrase
        case keyDerivation

        var errorDescription: String? {
            switch self {
            case .notOurFile:
                return String(localized: "This is not a FlyFun Forms data file.")
            case .wrongPassphrase:
                return String(localized: "That password does not match this file.")
            case .keyDerivation:
                return String(localized: "Could not read that file")
            }
        }
    }

    /// Encrypts `plaintext` with a key derived from `passphrase`.
    ///
    /// The passphrase is normalised here (``normalisePassphrase(_:)``), so a
    /// caller cannot forget to; normalising twice changes nothing.
    static func encrypt(_ plaintext: Data, passphrase: String) throws -> Data {
        let salt = randomBytes(saltBytes)
        let nonce = randomBytes(nonceBytes)
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: nonce))

        var out = magic
        out.append(version)
        out.append(salt)
        out.append(nonce)
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    /// Decrypts a file written by ``encrypt(_:passphrase:)`` on either platform.
    ///
    /// - Throws: ``Failure/notOurFile`` when the header is not ours, and
    ///   ``Failure/wrongPassphrase`` when GCM authentication fails, which is
    ///   the same signal as a tampered file. Either way nothing has been
    ///   decoded, so an import stops before writing anything.
    static func decrypt(_ data: Data, passphrase: String) throws -> Data {
        // Re-based so integer offsets are safe whatever slice we were handed.
        let bytes = Data(data)
        guard bytes.count >= headerBytes + tagBytes,
              bytes.prefix(magic.count) == magic,
              bytes[magic.count] == version else {
            throw Failure.notOurFile
        }
        var offset = magic.count + 1
        let salt = bytes.subdata(in: offset..<offset + saltBytes); offset += saltBytes
        let nonce = bytes.subdata(in: offset..<offset + nonceBytes); offset += nonceBytes
        let ciphertext = bytes.subdata(in: offset..<bytes.count - tagBytes)
        let tag = bytes.subdata(in: bytes.count - tagBytes..<bytes.count)

        let key = try deriveKey(passphrase: passphrase, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag
            )
            return try AES.GCM.open(box, using: key)
        } catch {
            throw Failure.wrongPassphrase
        }
    }

    /// Whether `data` starts with our header, so an import can tell an
    /// encrypted file from plaintext JSON without a passphrase.
    static func looksEncrypted(_ data: Data) -> Bool {
        data.count > magic.count && Data(data.prefix(magic.count)) == magic
    }

    /// The exact characters fed to the key derivation, on export and import.
    ///
    /// Surrounding whitespace is dropped and Unicode is NFC-normalised, so an
    /// accented letter typed on iOS gives the same UTF-8 bytes as on Android.
    /// Case is kept. Same rule as Android's `normalisePassphrase`.
    static func normalisePassphrase(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    /// A passphrase the user reads off one device and types into the other:
    /// three words from the same list as Android, joined by "-". Short enough
    /// to fit on one line and to remember; the file is meant to be imported
    /// and deleted (SECURITY_AUDIT.md N5, accepted).
    static func generatePassphrase(words: Int = 3) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<words)
            .map { _ in wordList.randomElement(using: &generator)! }
            .joined(separator: "-")
    }

    /// Copied from Android's `DataFileCrypto.WORDS`, in the same order.
    /// Short, aviation-flavoured, and free of easily confused pairs.
    static let wordList = [
        "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel",
        "india", "juliet", "kilo", "lima", "mike", "november", "oscar", "papa",
        "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey",
        "xray", "yankee", "zulu", "runway", "taxiway", "apron", "hangar",
        "compass", "rudder", "aileron", "throttle", "cockpit", "propeller",
    ]

    // MARK: - Primitives

    private static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        let password = Array(normalisePassphrase(passphrase).utf8)
        var key = [UInt8](repeating: 0, count: keyBytes)
        let status = password.withUnsafeBufferPointer { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                passwordBuffer.withMemoryRebound(to: CChar.self) { passwordChars in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordChars.baseAddress, passwordChars.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress, saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        &key, keyBytes
                    )
                }
            }
        }
        guard status == Int32(kCCSuccess) else { throw Failure.keyDerivation }
        return SymmetricKey(data: key)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
