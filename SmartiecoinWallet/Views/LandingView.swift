import SwiftUI

struct LandingView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let onCreateWallet: () -> Void
    let onImportWallet: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: sizeClass == .regular ? 120 : 60)

                    // Logo & Title
                    VStack(spacing: 16) {
                        Image("AppIconDisplay")
                            .resizable()
                            .scaledToFit()
                            .frame(width: sizeClass == .regular ? 140 : 100,
                                   height: sizeClass == .regular ? 140 : 100)
                            .clipShape(RoundedRectangle(cornerRadius: sizeClass == .regular ? 32 : 24))
                            .shadow(color: AppColors.primary.opacity(0.3), radius: 20, y: 10)

                        Text("Smartiecoin")
                            .font(sizeClass == .regular ? .largeTitle.bold() : .title.bold())
                            .foregroundColor(AppColors.text)

                        Text("Wallet")
                            .font(sizeClass == .regular ? .title2 : .title3)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.bottom, sizeClass == .regular ? 60 : 48)

                    // Info card
                    VStack {
                        Text("Non-custodial wallet. Your keys never leave this device.")
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(16)
                    }
                    .frame(maxWidth: sizeClass == .regular ? 500 : .infinity)
                    .cardStyle()
                    .padding(.bottom, sizeClass == .regular ? 60 : 48)

                    // Buttons
                    VStack(spacing: 12) {
                        Button(action: onCreateWallet) {
                            Text("Create New Wallet")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button(action: onImportWallet) {
                            Text("Import Existing Wallet")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .frame(maxWidth: sizeClass == .regular ? 400 : .infinity)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, sizeClass == .regular ? 40 : 24)
                .frame(minHeight: geo.size.height)
            }
        }
        .background(AppColors.bg)
    }
}
