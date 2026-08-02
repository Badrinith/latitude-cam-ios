import SwiftUI

// MARK: - Design Tokens

struct LatitudePalette {
    // Backgrounds
    static let backgroundDark = Color(red: 0.06, green: 0.06, blue: 0.06) // #0d0d0d
    static let backgroundCard = Color(red: 0.11, green: 0.11, blue: 0.11) // #1c1c1e
    static let backgroundSheet = Color(red: 0.09, green: 0.09, blue: 0.09) // #161616

    // Text
    static let textPrimary = Color(red: 0.949, green: 0.937, blue: 0.91) // #f2efe8
    static let textSecondary = Color(white: 1.0, opacity: 0.5)
    static let textTertiary = Color(white: 1.0, opacity: 0.35)

    // Accent
    static let accentAmber = Color(red: 0.851, green: 0.541, blue: 0.322) // #d98a52
    static let accentAmberDark = Color(red: 0.541, green: 0.353, blue: 0.204) // #8a5a34

    // Film Swatches
    static let filmAmber = Color(red: 0.541, green: 0.478, blue: 0.388) // #8a7a63
    static let filmSlate = Color(red: 0.42, green: 0.416, blue: 0.388) // #6b6a63
    static let filmRust = Color(red: 0.612, green: 0.247, blue: 0.18) // #9c3f2e
    static let filmMono = Color(red: 0.169, green: 0.169, blue: 0.169) // #2b2b2b

    // Glass effect
    static let glassBackground = Color(white: 0, opacity: 0.45)
}

struct LatitudeTypography {
    // Font names
    static let systemFont = "system"
    static let monoFont = "SF Mono"

    // Sizes & weights
    struct Headline {
        static let size: CGFloat = 30
        static let weight: Font.Weight = .bold // 700
        static let lineHeight: CGFloat = 34.5 // 1.15
    }

    struct Title {
        static let size: CGFloat = 22
        static let weight: Font.Weight = .bold // 700
    }

    struct Button {
        static let size: CGFloat = 15
        static let weight: Font.Weight = .semibold // 600
    }

    struct Label {
        static let size: CGFloat = 13
        static let weight: Font.Weight = .semibold // 600
    }

    struct Description {
        static let size: CGFloat = 12
        static let weight: Font.Weight = .regular // 400
    }

    struct Caption {
        static let size: CGFloat = 11
        static let weight: Font.Weight = .regular // 400
    }

    struct Mono {
        static let size: CGFloat = 12
        static let weight: Font.Weight = .semibold // 600
    }
}

struct LatitudeSpacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 100
}

struct LatitudeRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 14
    static let large: CGFloat = 16
    static let sheet: CGFloat = 28
    static let card: CGFloat = 16
    static let pill: CGFloat = 9999
}

// MARK: - App State

enum AppScreen {
    case launch
    case onboarding
    case login
    case viewfinder
    case filmSim
    case library
    case edit
    case review
    case settings
}

class AppState: ObservableObject {
    @Published var currentScreen: AppScreen = .launch
    @Published var proControlsOpen = false
    @Published var exportSheetOpen = false
    @Published var currentFilmProfile = "Amber"
    @Published var selectedLibraryIndex: Int?
}

// MARK: - View Modifiers

struct GlassPillStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(LatitudePalette.glassBackground)
            .cornerRadius(16)
            .backdropBlur(radius: 10)
    }
}

extension View {
    func glassPill() -> some View {
        modifier(GlassPillStyle())
    }
}

struct BackdropBlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func backdropBlur(radius: CGFloat) -> some View {
        modifier(BackdropBlurModifier(radius: radius))
    }
}
