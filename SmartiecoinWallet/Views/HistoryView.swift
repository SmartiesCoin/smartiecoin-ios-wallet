import SwiftUI

struct HistoryView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let address: String
    let onBack: () -> Void

    @State private var transactions: [HistoryTx] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
            .padding(.horizontal, sizeClass == .regular ? 40 : 24)
            .padding(.top, sizeClass == .regular ? 40 : 20)
            .padding(.bottom, 16)

            Text("Transaction History")
                .font(sizeClass == .regular ? .largeTitle.bold() : .title.bold())
                .foregroundColor(AppColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, sizeClass == .regular ? 40 : 24)
                .padding(.bottom, 16)

            if loading {
                Spacer()
                ProgressView()
                    .tint(AppColors.primary)
                Spacer()
            } else if let error {
                Spacer()
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(AppColors.danger)
                    .padding()
                Spacer()
            } else if transactions.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.textMuted)
                    Text("No transactions yet")
                        .font(.headline)
                        .foregroundColor(AppColors.textMuted)
                }
                Spacer()
            } else {
                transactionList
            }
        }
        .background(AppColors.bg)
        .task {
            await loadHistory()
        }
    }

    private var transactionList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(transactions) { tx in
                    TransactionRow(tx: tx)
                }
            }
            .frame(maxWidth: sizeClass == .regular ? 700 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, sizeClass == .regular ? 40 : 24)
            .padding(.bottom, 40)
        }
    }

    private func loadHistory() async {
        do {
            #if WALLET_MODE_API
            transactions = try await APIService.fetchHistory(address: address)
            #else
            transactions = await SPVWalletService.fetchHistory(address: address)
            #endif
            loading = false
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }
}

struct TransactionRow: View {
    let tx: HistoryTx

    private var netDisplay: String {
        SmartiecoinNetwork.smtToDisplay(tx.netAmount)
    }

    private var dateDisplay: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: tx.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Indicator dot
            Circle()
                .fill(tx.isReceive ? AppColors.success : AppColors.danger)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.isReceive ? "Received" : "Sent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.text)

                Text(dateDisplay)
                    .font(.caption)
                    .foregroundColor(AppColors.textMuted)

                Text(String(tx.txid.prefix(16)) + "...")
                    .font(.caption2)
                    .foregroundColor(AppColors.textMuted)
            }

            Spacer()

            Text("\(tx.isReceive ? "+" : "-")\(netDisplay)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tx.isReceive ? AppColors.success : AppColors.danger)
        }
        .padding(14)
        .background(AppColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}
