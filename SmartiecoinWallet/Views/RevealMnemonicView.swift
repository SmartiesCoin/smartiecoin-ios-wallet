import SwiftUI

struct RevealMnemonicView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let mnemonic: String?
    let loading: Bool
    let error: String?
    let onSubmit: (String) -> Void
    let onBack: () -> Void

    @State private var password = ""
    @State private var copied = false

    var body: some View {
        Group {
            if let mnemonic, !mnemonic.isEmpty {
                revealedView(mnemonic: mnemonic)
            } else {
                passwordPrompt
            }
        }
        .background(AppColors.bg)
    }

    // MARK: - Password Prompt

    private var passwordPrompt: some View {
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

                    Spacer(minLength: sizeClass == .regular ? 80 : 40)

                    VStack(spacing: 16) {
                        Image(systemName: "key.fill")
                            .font(.system(size: sizeClass == .regular ? 60 : 48))
                            .foregroundColor(AppColors.primary)
                            .padding(.bottom, 8)

                        Text("Reveal Recovery Phrase")
                            .font(sizeClass == .regular ? .title.bold() : .title2.bold())
                            .foregroundColor(AppColors.text)

                        Text("Enter your password to view your 12-word recovery phrase.")
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 32)

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
                                Text("Reveal")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(disabled: password.isEmpty || loading))
                        .disabled(password.isEmpty || loading)
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
    }

    // MARK: - Revealed View

    private var columns: [GridItem] {
        if sizeClass == .regular {
            [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        } else {
            [GridItem(.flexible()), GridItem(.flexible())]
        }
    }

    private func revealedView(mnemonic: String) -> some View {
        let words = mnemonic.split(separator: " ").map(String.init)

        return AdaptiveContainer {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Done")
                        }
                        .foregroundColor(AppColors.primary)
                    }
                    Spacer()
                }
                .padding(.bottom, 16)

                Text("Recovery Phrase")
                    .font(sizeClass == .regular ? .largeTitle.bold() : .title.bold())
                    .foregroundColor(AppColors.text)
                    .padding(.bottom, 8)

                Text("These 12 words can restore your wallet on any device.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 16)

                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(hex: 0xFCA5A5))
                    Text("NEVER share this phrase. Anyone with it can steal your funds.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(hex: 0xFCA5A5))
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0x7F1D1D))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 24)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.textMuted)
                                .frame(width: 20, alignment: .leading)

                            Text(word)
                                .font(.body.weight(.medium))
                                .foregroundColor(AppColors.text)

                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(AppColors.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                    }
                }
                .padding(.bottom, 24)

                Button(action: { copyMnemonic(mnemonic) }) {
                    HStack(spacing: 8) {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy Recovery Phrase")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.bottom, 12)

                Button(action: onBack) {
                    Text("Done")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func copyMnemonic(_ mnemonic: String) {
        UIPasteboard.general.string = mnemonic
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }
}
