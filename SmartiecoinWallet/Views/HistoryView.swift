import SwiftUI

struct HistoryView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let address: String
    let onBack: () -> Void

    @State private var transactions: [HistoryTx] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selectedTx: HistoryTx?

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
        .sheet(item: $selectedTx) { tx in
            TxDetailView(tx: tx)
        }
    }

    private var transactionList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(transactions) { tx in
                    Button { selectedTx = tx } label: {
                        TransactionRow(tx: tx)
                    }
                    .buttonStyle(.plain)
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
            transactions = try await APIService.fetchHistory(address: address)
            loading = false
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }
}

struct TxDetailView: View {
    let tx: HistoryTx
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var explorerURL: URL? {
        URL(string: "https://explorer.smartiecoin.com/tx/\(tx.txid)")
    }

    private var dateDisplay: String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .medium
        return f.string(from: tx.date)
    }

    private var netDisplay: String {
        SmartiecoinNetwork.smtToDisplay(tx.netAmount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: tx.isReceive ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(tx.isReceive ? AppColors.success : AppColors.danger)

                        Text(tx.isReceive ? "Received" : "Sent")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(AppColors.text)

                        Text("\(tx.isReceive ? "+" : "-")\(netDisplay) SMT")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(tx.isReceive ? AppColors.success : AppColors.danger)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 0) {
                        detailRow(label: "Date", value: dateDisplay)
                        Divider().background(AppColors.border)
                        detailRow(label: "Amount", value: "\(netDisplay) SMT")
                        if tx.isReceive {
                            Divider().background(AppColors.border)
                            detailRow(label: "Received", value: "\(SmartiecoinNetwork.smtToDisplay(tx.received)) SMT")
                        } else {
                            Divider().background(AppColors.border)
                            detailRow(label: "Sent", value: "\(SmartiecoinNetwork.smtToDisplay(tx.sent)) SMT")
                        }
                    }
                    .padding(16)
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transaction ID")
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppColors.textSecondary)

                        Text(tx.txid)
                            .font(.caption.monospaced())
                            .foregroundColor(AppColors.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            UIPasteboard.general.string = tx.txid
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copied = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied!" : "Copy TXID")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppColors.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .cardStyle()

                    if let url = explorerURL {
                        Link(destination: url) {
                            HStack(spacing: 8) {
                                Image(systemName: "safari")
                                Text("View on Explorer")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(disabled: false))
                    }
                }
                .padding(24)
            }
            .background(AppColors.bg)
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppColors.primary)
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppColors.text)
        }
        .padding(.vertical, 10)
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
