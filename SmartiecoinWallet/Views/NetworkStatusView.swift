import SwiftUI

struct NetworkStatusView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let spvClient: SPVClient
    let onBack: () -> Void
    let onAddPeer: (String) -> Void

    @State private var manualPeerInput = ""
    @State private var showAddPeer = false
    @State private var showBulkAdd = false
    @State private var bulkPeerInput = ""

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
                Button(action: { showBulkAdd = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste Nodes")
                    }
                    .font(.caption)
                    .foregroundColor(AppColors.primary)
                }
                Button(action: { showAddPeer = true }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(AppColors.primary)
                }
            }
            .padding(.horizontal, sizeClass == .regular ? 40 : 24)
            .padding(.top, sizeClass == .regular ? 40 : 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 20) {
                    // Sync Status Card
                    syncStatusCard

                    // Network Stats
                    networkStatsCard

                    // Connected Peers
                    peersCard
                }
                .frame(maxWidth: sizeClass == .regular ? 700 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, sizeClass == .regular ? 40 : 24)
                .padding(.bottom, 40)
            }
        }
        .background(AppColors.bg)
        .alert("Add Peer", isPresented: $showAddPeer) {
            TextField("IP:Port (e.g. 192.168.1.100:9999)", text: $manualPeerInput)
            Button("Cancel", role: .cancel) { manualPeerInput = "" }
            Button("Add") {
                if !manualPeerInput.isEmpty {
                    onAddPeer(manualPeerInput)
                    manualPeerInput = ""
                }
            }
        } message: {
            Text("Enter the IP address and port of a Smartiecoin node")
        }
        .sheet(isPresented: $showBulkAdd) {
            BulkAddPeersSheet(
                input: $bulkPeerInput,
                onAdd: { text in
                    onAddPeer(text)
                    showBulkAdd = false
                    bulkPeerInput = ""
                },
                onCancel: {
                    showBulkAdd = false
                    bulkPeerInput = ""
                }
            )
        }
    }

    // MARK: - Sync Status

    private var syncStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Sync Status")
                    .font(.headline)
                    .foregroundColor(AppColors.text)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(syncDotColor)
                        .frame(width: 10, height: 10)
                    Text(spvClient.syncState.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(syncTextColor)
                }
            }

            // Progress bar
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.bgInput)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.primary)
                            .frame(width: geo.size.width * spvClient.syncProgress, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: spvClient.syncProgress)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("Block \(spvClient.blockHeight)")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted)
                    Spacer()
                    Text("\(Int(spvClient.syncProgress * 100))%")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("Network: \(spvClient.networkHeight)")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted)
                }
            }

            if let error = spvClient.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.danger)
            }
        }
        .padding(20)
        .cardStyle()
    }

    // MARK: - Network Stats

    private var networkStatsCard: some View {
        VStack(spacing: 12) {
            Text("Network")
                .font(.headline)
                .foregroundColor(AppColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            StatRow(label: "Connected Peers", value: "\(spvClient.peerCount)")
            StatRow(label: "Block Height", value: "\(spvClient.blockHeight)")
            StatRow(label: "Network Height", value: "\(spvClient.networkHeight)")
            StatRow(label: "Protocol", value: "P2P (port \(P2PConfig.port))")
            StatRow(label: "Mode", value: "SPV (Bloom Filter)")
        }
        .padding(20)
        .cardStyle()
    }

    // MARK: - Peers List

    private var peersCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Peers (\(spvClient.connectedPeers.count))")
                    .font(.headline)
                    .foregroundColor(AppColors.text)
                Spacer()
            }

            if spvClient.connectedPeers.isEmpty {
                Text("No peers connected")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textMuted)
                    .padding(.vertical, 20)
            } else {
                ForEach(spvClient.connectedPeers) { peer in
                    PeerRow(peer: peer)
                }
            }
        }
        .padding(20)
        .cardStyle()
    }

    // MARK: - Helpers

    private var syncDotColor: Color {
        switch spvClient.syncState {
        case .synchronized: return AppColors.success
        case .syncing, .connecting: return AppColors.warning
        case .disconnected, .error: return AppColors.danger
        }
    }

    private var syncTextColor: Color {
        switch spvClient.syncState {
        case .synchronized: return AppColors.success
        case .syncing, .connecting: return AppColors.warning
        case .disconnected, .error: return AppColors.danger
        }
    }
}

// MARK: - Sub-components

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppColors.text)
        }
    }
}

struct BulkAddPeersSheet: View {
    @Binding var input: String
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste your node list in any of these formats:")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("addnode=103.13.114.93")
                    Text("addnode=109.173.162.234:9999")
                    Text("136.144.42.239")
                }
                .font(.caption.monospaced())
                .foregroundColor(AppColors.textMuted)
                .padding(12)
                .background(AppColors.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                TextEditor(text: $input)
                    .font(.body.monospaced())
                    .foregroundColor(AppColors.text)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(AppColors.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                    .frame(minHeight: 150)

                Button(action: {
                    if !input.isEmpty { onAdd(input) }
                }) {
                    Text("Add Peers")
                }
                .buttonStyle(PrimaryButtonStyle(disabled: input.isEmpty))
                .disabled(input.isEmpty)
            }
            .padding(24)
            .background(AppColors.bg)
            .navigationTitle("Add Nodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

struct PeerRow: View {
    let peer: SPVClient.PeerInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(peer.isConnected ? AppColors.success : AppColors.danger)
                    .frame(width: 8, height: 8)

                Text("\(peer.host):\(peer.port)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.text)

                Spacer()

                Text("H: \(peer.height)")
                    .font(.caption)
                    .foregroundColor(AppColors.textMuted)
            }

            HStack(spacing: 12) {
                Text(peer.userAgent)
                    .font(.caption)
                    .foregroundColor(AppColors.textMuted)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 8) {
                    Label(formatBytes(peer.bytesSent), systemImage: "arrow.up")
                    Label(formatBytes(peer.bytesReceived), systemImage: "arrow.down")
                }
                .font(.caption)
                .foregroundColor(AppColors.textMuted)
            }
        }
        .padding(12)
        .background(AppColors.bgInput.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}
