import SwiftUI

struct ChangePasswordView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let loading: Bool
    let error: String?
    let success: Bool
    let onSubmit: (String, String) -> Void
    let onBack: () -> Void

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""

    private var localError: String? {
        if !confirmPassword.isEmpty && newPassword != confirmPassword {
            return "New passwords do not match"
        }
        if !newPassword.isEmpty && newPassword.count < 8 {
            return "New password must be at least 8 characters"
        }
        return nil
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty
            && !newPassword.isEmpty
            && newPassword == confirmPassword
            && newPassword.count >= 8
            && !loading
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundColor(AppColors.primary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 24)

                    Spacer(minLength: sizeClass == .regular ? 60 : 20)

                    VStack(spacing: 16) {
                        Image(systemName: "lock.rotation")
                            .font(.system(size: sizeClass == .regular ? 60 : 48))
                            .foregroundColor(AppColors.primary)
                            .padding(.bottom, 8)

                        Text("Change Password")
                            .font(sizeClass == .regular ? .title.bold() : .title2.bold())
                            .foregroundColor(AppColors.text)

                        Text("Your recovery phrase will not change. Only the password used to unlock this device.")
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 32)

                    VStack(spacing: 12) {
                        SecureField("Current password", text: $currentPassword)
                            .inputFieldStyle()

                        SecureField("New password (min. 8 chars)", text: $newPassword)
                            .inputFieldStyle()

                        SecureField("Confirm new password", text: $confirmPassword)
                            .inputFieldStyle()
                            .onSubmit {
                                if canSubmit { onSubmit(currentPassword, newPassword) }
                            }

                        if success {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Password changed successfully")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(AppColors.success)
                        } else if let displayError = localError ?? error {
                            Text(displayError)
                                .font(.caption)
                                .foregroundColor(AppColors.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: {
                            if success {
                                onBack()
                            } else if canSubmit {
                                onSubmit(currentPassword, newPassword)
                            }
                        }) {
                            if loading {
                                ProgressView()
                                    .tint(AppColors.text)
                            } else {
                                Text(success ? "Done" : "Change Password")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(disabled: !success && !canSubmit))
                        .disabled(!success && !canSubmit)
                        .onChange(of: success) { _, newValue in
                            if newValue {
                                currentPassword = ""
                                newPassword = ""
                                confirmPassword = ""
                            }
                        }
                    }
                    .frame(maxWidth: sizeClass == .regular ? 400 : .infinity)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, sizeClass == .regular ? 40 : 24)
                .padding(.top, 20)
                .frame(minHeight: geo.size.height)
            }
        }
        .background(AppColors.bg)
    }
}
