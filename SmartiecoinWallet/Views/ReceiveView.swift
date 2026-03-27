import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiveView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let address: String
    let onBack: () -> Void

    @State private var copied = false

    private var qrSize: CGFloat {
        sizeClass == .regular ? 280 : 200
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

                Text("Receive SMT")
                    .font(sizeClass == .regular ? .largeTitle.bold() : .title.bold())
                    .foregroundColor(AppColors.text)
                    .padding(.bottom, 8)

                Text("Share your address or QR code to receive Smartiecoin")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 32)

                // QR Card
                VStack(spacing: 20) {
                    // QR Code
                    if let qrImage = generateQRCode(from: address) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: qrSize, height: qrSize)
                            .padding(16)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Address
                    Text(address)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColors.text)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)

                    // Copy button
                    Button(action: copyAddress) {
                        HStack(spacing: 8) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied!" : "Copy Address")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundColor(AppColors.text)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(copied ? AppColors.success : AppColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .cardStyle()
            }
        }
    }

    private func copyAddress() {
        UIPasteboard.general.string = address
        withAnimation {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = (qrSize * UIScreen.main.scale) / outputImage.extent.size.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
