import SwiftUI

struct UnlockWalletView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let address: String
    let onSubmit: (String) -> Void
    let onDelete: () -> Void
    let loading: Bool
    let error: String?

    @State private var password = ""
    @State private var showDeleteAlert = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: sizeClass == .regular ? 140 : 80)

                    // Logo & Header
                    VStack(spacing: 16) {
                        Image("AppIconDisplay")
                            .resizable()
                            .scaledToFit()
                            .frame(width: sizeClass == .regular ? 100 : 80,
                                   height: sizeClass == .regular ? 100 : 80)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: AppColors.primary.opacity(0.3), radius: 16, y: 8)

                        Text("Unlock Wallet")
                            .font(sizeClass == .regular ? .title.bold() : .title2.bold())
                            .foregroundColor(AppColors.text)

                        Text(address)
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted)
                            .lineLimit(1)
                            .frame(maxWidth: 250)
                    }
                    .padding(.bottom, 40)

                    // Form
                    VStack(spacing: 12) {
                        SecureField("Enter your password", text: $password)
                            .inputFieldStyle()
                            .onSubmit {
                                if !password.isEmpty { onSubmit(password) }
                            }

                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(AppColors.danger)
                        }

                        Button(action: { if !password.isEmpty { onSubmit(password) } }) {
                            if loading {
                                ProgressView()
                                    .tint(AppColors.text)
                            } else {
                                Text("Unlock")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(disabled: password.isEmpty || loading))
                        .disabled(password.isEmpty || loading)

                        Button(action: { showDeleteAlert = true }) {
                            Text("Delete Wallet")
                                .font(.subheadline)
                                .foregroundColor(AppColors.danger)
                        }
                        .padding(.top, 8)
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
        .alert("Delete Wallet", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will remove the wallet from this device. Make sure you have your recovery phrase backed up!")
        }
    }
}
