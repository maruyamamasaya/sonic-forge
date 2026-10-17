import SwiftUI
import AppKit

enum WorkspaceWood: String, CaseIterable, Identifiable {
    case walnut, oak, cherry
    var id: String { rawValue }
    var title: String { switch self { case .walnut: return "Walnut"; case .oak: return "White oak"; case .cherry: return "Cherry" } }
    var ink: Color { self == .walnut ? Color(red: 0.96, green: 0.90, blue: 0.78) : Color(red: 0.18, green: 0.13, blue: 0.08) }
    var scheme: ColorScheme { self == .walnut ? .dark : .light }
    var image: NSImage? { Self.images[rawValue] }
    private static let images: [String: NSImage] = Dictionary(uniqueKeysWithValues: allCases.compactMap { wood in
        guard let url = Bundle.main.url(forResource: wood.rawValue, withExtension: "png", subdirectory: "Textures"), let image = NSImage(contentsOf: url) else { return nil }
        return (wood.rawValue, image)
    })
}

struct WoodSurface: View {
    let wood: WorkspaceWood
    var horizontalGrain = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.33, green: 0.23, blue: 0.16)
                if let image = wood.image {
                    if horizontalGrain {
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.height, height: geometry.size.width).clipped()
                            .rotationEffect(.degrees(90))
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    } else {
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                }
                Color.black.opacity(wood == .walnut ? 0.20 : 0)
                LinearGradient(colors: [.white.opacity(0.045), .clear, .black.opacity(wood == .walnut ? 0.22 : 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.clipped().allowsHitTesting(false)
    }
}

struct CabinetButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(primary ? Color(red: 0.14, green: 0.12, blue: 0.08) : Color(red: 0.91, green: 0.90, blue: 0.83))
            .background {
                RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: primary ? [Color(red: 0.88, green: 0.77, blue: 0.55), Color(red: 0.67, green: 0.52, blue: 0.30)] : [Color(red: 0.21, green: 0.23, blue: 0.19), Color(red: 0.13, green: 0.15, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)) }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.1 : 0.45), radius: configuration.isPressed ? 0 : 2, y: configuration.isPressed ? 0 : 2)
            .offset(y: configuration.isPressed ? 1 : 0).opacity(enabled ? 1 : 0.38)
    }
}
