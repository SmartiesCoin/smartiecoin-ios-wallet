import SwiftUI

enum AppColors {
    static let bg = Color(hex: 0x0F172A)
    static let bgCard = Color(hex: 0x1E293B)
    static let bgInput = Color(hex: 0x334155)
    static let primary = Color(hex: 0x6366F1)
    static let primaryDark = Color(hex: 0x4F46E5)
    static let primaryLight = Color(hex: 0x818CF8)
    static let text = Color(hex: 0xF8FAFC)
    static let textSecondary = Color(hex: 0x94A3B8)
    static let textMuted = Color(hex: 0x64748B)
    static let border = Color(hex: 0x475569)
    static let success = Color(hex: 0x22C55E)
    static let danger = Color(hex: 0xEF4444)
    static let warning = Color(hex: 0xF59E0B)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.border, lineWidth: 1)
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var disabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(AppColors.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(disabled ? AppColors.primary.opacity(0.5) : AppColors.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(AppColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct InputFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(AppColors.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .foregroundColor(AppColors.text)
            .font(.body)
            .tint(AppColors.primary)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    func inputFieldStyle() -> some View {
        modifier(InputFieldStyle())
    }
}

struct AdaptiveContainer<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: sizeClass == .regular ? 600 : .infinity)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, sizeClass == .regular ? 40 : 24)
                    .padding(.top, sizeClass == .regular ? 60 : 20)
                    .padding(.bottom, 40)
            }
        }
        .background(AppColors.bg)
    }
}
