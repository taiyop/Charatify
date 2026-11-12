import CryptoKit
import Foundation

// Only the public key is passed here. Catch a mismatched CI signing key before publishing.
do {
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
    guard let publicKey = Data(base64Encoded: CommandLine.arguments[2]),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    guard key.isValidSignature(signature, for: archive) else {
        fputs("Update signature does not match SPARKLE_PUBLIC_ED_KEY\n", stderr)
        exit(1)
    }
    print("Verified update signature")
} catch {
    fputs("Cannot verify update: \(error.localizedDescription)\n", stderr)
    exit(1)
}
