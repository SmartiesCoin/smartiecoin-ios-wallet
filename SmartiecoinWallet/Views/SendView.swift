import SwiftUI

struct SendView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let address: String
    let balance: BalanceResponse?
    let onBack: () -> Void
    let onSendTransaction: (String, String) async throws -> (txid: String, fee: Int)
    let onSuccess: () -> Void

    @State private var step: SendStep = .form
    @State private var toAddress = ""
    @State private var amount = ""
    @State private var error: String?
    @State private var txResult: TxResult?

    private var availableSmt: Double {
        guard let balance else { return 0 }
        return Double(balance.balance) / Double(SmartiecoinNetwork.coin)
    }

    enum SendStep {
        case form, confirm, sending, success
    }

    struct TxResult {
        let txid: String
        let fee: Int
    }

    var body: some View {
        AdaptiveContainer {
            switch step {
            case .form:
                formView
            case .confirm, .sending:
                confirmView
            case .success:
                successView
            }
        }
    }

    // MARK: - Form

    private var formView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .foregroundColor(AppColors.primary)
            }
            .padding(.bottom, 24)

            Text("Send SMT")
                .font(sizeClass == .regular ? .largeTitle.bold() : .title.bold())
                .foregroundColor(AppColors.text)
                .padding(.bottom, 8)

            Text("Available: \(String(format: "%.8f", availableSmt)) SMT")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .padding(.bottom, 24)

            Text("Recipient Address")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .padding(.bottom, 6)

            TextField("S... or R...", text: $toAddress)
                .inputFieldStyle()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.bottom, 12)

            Text("Amount (SMT)")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .padding(.bottom, 6)

            TextField("0.00000000", text: $amount)
                .inputFieldStyle()
                .keyboardType(.decimalPad)

            HStack {
                Spacer()
                Button("MAX") {
                    amount = String(format: "%.8f", availableSmt)
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.primary)
            }
            .padding(.top, 8)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.danger)
                    .padding(.top, 8)
            }

            Button(action: handleReview) {
                Text("Review")
            }
            .buttonStyle(PrimaryButtonStyle(disabled: toAddress.isEmpty || amount.isEmpty))
            .disabled(toAddress.isEmpty || amount.isEmpty)
            .padding(.top, 24)
        }
    }

    // MARK: - Confirm

    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Confirm Transaction")
                .font(sizeClass == .regular ? .largeTitle.bold() : .title.bold())
                .foregroundColor(AppColors.text)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("To")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted)
                    Text(toAddress)
                        .font(.body.weight(.medium))
                        .foregroundColor(AppColors.text)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Amount")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted)
                    Text("\(amount) SMT")
                        .font(.body.weight(.medium))
                        .foregroundColor(AppColors.text)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .padding(.bottom, 16)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.danger)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 12) {
                Button(action: { step = .form }) {
                    Text("Back")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(step == .sending)

                Button(action: handleSend) {
                    if step == .sending {
                        ProgressView()
                            .tint(AppColors.text)
                    } else {
                        Text("Send")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(disabled: step == .sending))
                .disabled(step == .sending)
            }
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 0) {
            if let result = txResult {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(AppColors.success)
                        .padding(.bottom, 8)

                    Text("Transaction Sent!")
                        .font(.title2.bold())
                        .foregroundColor(AppColors.text)

                    Text("\(amount) SMT")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.success)
                        .padding(.vertical, 8)

                    Group {
                        Text("To")
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted)
                        Text(toAddress)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        Text("Fee")
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted)
                            .padding(.top, 4)
                        Text("\(SmartiecoinNetwork.smtToDisplay(result.fee)) SMT")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)

                        Text("TXID")
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted)
                            .padding(.top, 4)
                        Text(result.txid)
                            .font(.caption2)
                            .foregroundColor(AppColors.textMuted)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(AppColors.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.success, lineWidth: 1)
                )
                .padding(.bottom, 24)
            }

            Button(action: onSuccess) {
                Text("Back to Wallet")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: - Actions

    private func handleReview() {
        error = nil

        guard AddressGenerator.isValidAddress(toAddress) else {
            error = "Invalid Smartiecoin address"
            return
        }

        guard let val = Double(amount), val > 0 else {
            error = "Invalid amount"
            return
        }

        guard val <= availableSmt else {
            error = "Insufficient funds"
            return
        }

        step = .confirm
    }

    private func handleSend() {
        step = .sending
        error = nil

        Task {
            do {
                let result = try await onSendTransaction(toAddress, amount)
                await MainActor.run {
                    txResult = TxResult(txid: result.txid, fee: result.fee)
                    step = .success
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    step = .confirm
                }
            }
        }
    }
}
