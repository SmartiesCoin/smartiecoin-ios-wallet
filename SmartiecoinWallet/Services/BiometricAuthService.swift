import Foundation
import LocalAuthentication
import Security

enum BiometricAuthError: LocalizedError {
    case notAvailable
    case noStoredCredential
    case keychainFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Face ID is not available on this device"
        case .noStoredCredential:
            return "Unlock once with your password to enable Face ID"
        case .keychainFailed:
            return "Face ID unlock failed"
        }
    }
}

enum BiometricAuthService {
    #if WALLET_MODE_SPV
    private static let service = "com.smartiecoin.wallet.node.biometric"
    #else
    private static let service = "com.smartiecoin.wallet.lite.biometric"
    #endif

    private static let account = "unlock_password"

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "Touch ID" : "Face ID"
    }

    static var isBiometrySupported: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var hasStoredCredential: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true

        var query = baseQuery()
        query[kSecReturnData as String] = false
        query[kSecUseAuthenticationContext as String] = context

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static var canUnlock: Bool {
        isBiometrySupported && hasStoredCredential
    }

    static func saveUnlockPassword(_ password: String) throws {
        guard isBiometrySupported else { throw BiometricAuthError.notAvailable }
        guard let data = password.data(using: .utf8) else { return }

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw BiometricAuthError.notAvailable
        }

        SecItemDelete(baseQuery() as CFDictionary)

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessControl as String] = access

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BiometricAuthError.keychainFailed(status)
        }
    }

    static func loadUnlockPassword() throws -> String {
        guard isBiometrySupported else { throw BiometricAuthError.notAvailable }
        guard hasStoredCredential else { throw BiometricAuthError.noStoredCredential }

        let context = LAContext()
        context.localizedReason = "Unlock your Smartiecoin wallet"

        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw BiometricAuthError.keychainFailed(status)
        }

        return password
    }

    static func deleteCredential() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
