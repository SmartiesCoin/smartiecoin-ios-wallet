# Changelog

## 0.3.1 - 2026-05-12

### Release status

- Submitted `SMT Node` 0.3.1 to App Store review.
- Submitted `SMT Lite` 0.3.1 to App Store review.
- Published sideloading IPAs through the GitHub Release while Apple review is pending.

### Node wallet

- Aligned the native node wallet version and user agent with Smartiecoin Core/network version `0.3.1`.
- Updated Node derivation to Smartiecoin Core coin type `5` while keeping Lite on the legacy web/mobile derivation path.
- Improved SPV peer handling, message parsing, inventory/getdata transaction relay, header syncing, and balance refresh behavior.
- Added yespower native bridge files required by the iOS native wallet target.

### Wallet features

- Added Face ID/Touch ID unlock support with target-specific keychain storage.
- Added wallet lock behavior separate from wallet delete/reset.
- Added recovery phrase reveal flow.
- Added wallet password change flow.
- Added local incoming-balance notification support and production APNs entitlement configuration.

### App Store metadata and packaging

- Added separate Xcode targets for `SMT Node` and `SMT Lite`.
- Updated bundle identifiers, icons, entitlements, and App Store build settings for both iOS apps.
- Fixed app icon catalog sizing issues for iPhone and iPad.
- Added release documentation for users installing the IPAs directly.

### IPA checksums

```text
e19da353d7989fb4d399c98f1bf3cb39ae701ed5de645a97e10fdcd2665311ec  SMT Lite.ipa
92dce2c8cfc9d4d46bdb5128fac3d5116236003e521bdc37145b79a26d29ea9e  SMT Node.ipa
```
