import SwiftUI

struct BackupMnemonicView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let mnemonic: String
    let onContinue: () -> Void

    @State private var showConfirmation = false

    private var words: [String] {
        mnemonic.split(separator: " ").map(String.init)
    }

    private var columns: [GridItem] {
        if sizeClass == .regular {
            [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        } else {
            [GridItem(.flexible()), GridItem(.flexible())]
        }
    }

    var body: some View {
        AdaptiveContainer {
            VStack(alignment: .leading, spacing: 0) {
                Text("Backup Recovery Phrase")
                    .font(sizeClass == .regular ? .largeTitle.bold() : .title.bold())
                    .foregroundColor(AppColors.text)
                    .padding(.bottom, 8)

                Text("Write down these 12 words in order. This is the ONLY way to recover your wallet.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 16)

                // Warning
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

                // Word grid
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
                .padding(.bottom, 32)

                Button(action: { showConfirmation = true }) {
                    Text("I've Saved My Phrase")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .alert("Have you saved your phrase?", isPresented: $showConfirmation) {
            Button("Go Back", role: .cancel) {}
            Button("Yes, I saved it") { onContinue() }
        } message: {
            Text("If you lose this phrase, you will lose access to your wallet forever.")
        }
    }
}
