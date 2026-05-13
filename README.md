# Smartiecoin iOS Wallet

Native iOS wallets for Smartiecoin.

- **SMT Node** (`com.smartiecoin.node`): native wallet with SPV networking for direct Smartiecoin network connectivity.
- **SMT Lite** (`com.smartiecoin.lite`): lightweight wallet mode connected through Smartiecoin web/API services.

Current iOS release: **0.3.1**.

## Sideloading while App Store review is pending

Download the latest `.ipa` files from the GitHub Release for `v0.3.1`.

- `SMT Node.ipa` is for users who want native SPV network connectivity.
- `SMT Lite.ipa` is for users who want the lightweight wallet connected to the web/API wallet service.

Users can install the IPA with their preferred iOS sideloading workflow, such as Apple Configurator, AltStore, Sideloadly, or an Apple developer account. iOS may require the device owner to trust the signing profile before launching the app.

## Development

Open `SmartiecoinWallet.xcodeproj` in Xcode.

Available schemes:

- `SmartiecoinNode`
- `SmartiecoinLite`

Both targets use marketing version `0.3.1`. Release builds use the production APNs entitlement through `SmartiecoinWallet/SmartiecoinWallet.entitlements`.
