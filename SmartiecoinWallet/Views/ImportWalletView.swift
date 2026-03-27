import SwiftUI

struct ImportWalletView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let onSubmit: (String, String) -> Void
    let onBack: () -> Void
    let loading: Bool
    let error: String?

    @State private var mnemonic = ""
    @State private var password = ""
    @State private var confirm = ""

    private var wordCount: Int {
        mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .filter { !$0.isEmpty }
            .count
    }

    private var canSubmit: Bool {
        wordCount == 12 && password.count >= 8 && password == confirm && !loading
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

                Text("Import Wallet")
                    .font(sizeClass == .regular ? .largeTitle.bold() : .title.bold())
                    .foregroundColor(AppColors.text)
                    .padding(.bottom, 8)

                Text("Enter your 12-word recovery phrase")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 24)

                // Mnemonic input
                Text("Recovery Phrase")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 6)

                TextEditor(text: $mnemonic)
                    .frame(minHeight: 80)
                    .padding(10)
                    .background(AppColors.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                    .foregroundColor(AppColors.text)
                    .font(.body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scrollContentBackground(.hidden)

                Text("\(wordCount)/12 words")
                    .font(.caption)
                    .foregroundColor(AppColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, 12)

                // Password fields
                Text("New Password")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 6)

                SecureField("At least 8 characters", text: $password)
                    .inputFieldStyle()
                    .padding(.bottom, 12)

                Text("Confirm Password")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 6)

                SecureField("Repeat your password", text: $confirm)
                    .inputFieldStyle()

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppColors.danger)
                        .padding(.top, 8)
                }

                Button(action: { if canSubmit { onSubmit(mnemonic.trimmingCharacters(in: .whitespacesAndNewlines), password) } }) {
                    if loading {
                        ProgressView()
                            .tint(AppColors.text)
                    } else {
                        Text("Import Wallet")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(disabled: !canSubmit))
                .disabled(!canSubmit)
                .padding(.top, 24)
            }
        }
    }
}
