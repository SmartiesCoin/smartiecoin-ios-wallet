import SwiftUI

struct CreateWalletView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let onSubmit: (String) -> Void
    let onBack: () -> Void
    let loading: Bool
    let error: String?

    @State private var password = ""
    @State private var confirm = ""

    private var canSubmit: Bool {
        password.count >= 8 && password == confirm && !loading
    }

    var body: some View {
        AdaptiveContainer {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(AppColors.primary)
                }
                .padding(.bottom, 24)

                Text("Create Wallet")
                    .font(sizeClass == .regular ? .largeTitle.bold() : .title.bold())
                    .foregroundColor(AppColors.text)
                    .padding(.bottom, 8)

                Text("Set a password to encrypt your wallet")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 32)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Password")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)

                    SecureField("At least 8 characters", text: $password)
                        .inputFieldStyle()

                    Text("Confirm Password")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.top, 4)

                    SecureField("Repeat your password", text: $confirm)
                        .inputFieldStyle()

                    if !password.isEmpty && password.count < 8 {
                        Text("Password must be at least 8 characters")
                            .font(.caption)
                            .foregroundColor(AppColors.warning)
                    }

                    if !confirm.isEmpty && password != confirm {
                        Text("Passwords don't match")
                            .font(.caption)
                            .foregroundColor(AppColors.danger)
                    }

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(AppColors.danger)
                    }

                    Button(action: { if canSubmit { onSubmit(password) } }) {
                        if loading {
                            ProgressView()
                                .tint(AppColors.text)
                        } else {
                            Text("Create Wallet")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(disabled: !canSubmit))
                    .disabled(!canSubmit)
                    .padding(.top, 16)
                }
            }
        }
    }
}
