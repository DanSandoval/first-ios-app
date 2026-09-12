import SwiftUI

// MARK: - Spacing

/// The app's spacing scale.
///
/// Every gap, inset and padding in the UI should come from here rather than
/// from a number typed at the call site. Two reasons, in order of importance:
///
/// 1. **iOS layout rests on a 4-point grid.** System margins, control heights,
///    `Label` icon gutters and the standard `List` insets are all multiples of
///    4. Hand-picked values like `13` or `18` land between the system's own
///    rhythm, and the mismatch is visible the moment a design-system view sits
///    next to a stock `Form` or `List`.
/// 2. A named scale is greppable. Changing every "section gap" in the app means
///    editing ``lg`` once, not auditing several dozen `.padding(24)` calls that
///    may or may not have meant the same thing.
///
/// The scale doubles roughly every step, which keeps adjacent values visually
/// distinct — two steps that differ by 2pt read as a mistake, not a decision.
///
/// ```swift
/// VStack(spacing: Spacing.md) { … }
///     .padding(.horizontal, Spacing.md)
/// ```
enum Spacing {

    /// 4pt — hairline separation inside a single control (icon to its label).
    static let xs: CGFloat = 4

    /// 8pt — related elements in the same visual group.
    static let sm: CGFloat = 8

    /// 16pt — the default. Card padding and the standard screen side margin.
    static let md: CGFloat = 16

    /// 24pt — between distinct groups inside one screen.
    static let lg: CGFloat = 24

    /// 32pt — between major sections.
    static let xl: CGFloat = 32

    /// 48pt — around isolated content: empty states, single call-to-action screens.
    static let xxl: CGFloat = 48
}

// MARK: - Radius

/// Corner radii for rounded containers.
///
/// Always pair these with `RoundedRectangle(cornerRadius:style: .continuous)`.
/// The continuous curve is the one iOS itself uses for app icons, sheets and
/// alerts; the default `.circular` corner is visibly tighter at the same
/// nominal radius and makes a custom container look subtly foreign next to
/// system chrome.
enum Radius {

    /// 8pt — small inline elements: chips, thumbnails, inline code blocks.
    static let sm: CGFloat = 8

    /// 12pt — buttons and controls.
    static let md: CGFloat = 12

    /// 16pt — cards and sheets. Matches the existing `Card` container.
    static let lg: CGFloat = 16

    /// A radius larger than any container half-height, producing a capsule.
    ///
    /// Prefer `Capsule()` where a shape is what's wanted; this exists for the
    /// APIs that take a `CGFloat` and give you no shape to substitute.
    static let pill: CGFloat = 999
}

// MARK: - Elevation

/// Shadow presets for lifting a surface off its background.
///
/// Elevation is appearance-dependent, which is the entire reason this is an
/// enum rather than three loose `.shadow(...)` calls:
///
/// - **In light mode** a shadow is the primary depth cue. The background is
///   near-white, so even a low-opacity black blur reads clearly.
/// - **In dark mode it mostly is not.** The background is already near-black,
///   so a black blur has almost nothing to darken — and a *wide* one just
///   smears the little contrast that exists into mud around the card. Depth in
///   dark mode comes from ``Palette/surfaceElevated`` being a lighter grey than
///   ``Palette/surface``, exactly as the system's own grouped backgrounds do it.
///
/// So the dark-mode presets are **tighter and only slightly more opaque**: just
/// enough edge definition to separate a floating surface from what is behind
/// it, never a soft cloud.
///
/// ```swift
/// content.elevation(.medium)   // sheets, popovers, anything that floats
/// ```
enum Elevation {

    /// No shadow. The correct default for cards sitting in a grouped list,
    /// where the background colour already carries the depth.
    case none

    /// A barely-there lift. Use for a card that should feel detached from a
    /// plain background without announcing it.
    case low

    /// A clear lift, for content that genuinely floats above the rest of the
    /// screen: sheets, popovers, drag previews.
    case medium

    /// Blur radius, vertical offset and opacity, resolved for one appearance.
    fileprivate struct Parameters {
        let radius: CGFloat
        let y: CGFloat
        let opacity: Double

        /// Nothing to draw — lets the modifier skip the shadow entirely rather
        /// than render a zero-opacity one and pay for the offscreen pass.
        static let hidden = Parameters(radius: 0, y: 0, opacity: 0)
    }

    /// The shadow values for this preset in the given appearance.
    ///
    /// - Note: Dark-mode radii are deliberately *smaller* than their light-mode
    ///   counterparts, not larger. See the type-level discussion.
    fileprivate func parameters(for colorScheme: ColorScheme) -> Parameters {
        switch (self, colorScheme) {
        case (.none, _):
            return .hidden
        case (.low, .dark):
            return Parameters(radius: 3, y: 1, opacity: 0.30)
        case (.low, _):
            return Parameters(radius: 4, y: 1, opacity: 0.10)
        case (.medium, .dark):
            return Parameters(radius: 8, y: 3, opacity: 0.38)
        case (.medium, _):
            return Parameters(radius: 12, y: 4, opacity: 0.14)
        }
    }
}

/// Applies an ``Elevation`` preset, re-resolving it when the appearance changes.
///
/// Reading `colorScheme` here rather than at the call site is what keeps every
/// caller honest: there is no way to apply a shadow that was tuned for light
/// mode and forget the dark-mode case.
private struct ElevationModifier: ViewModifier {
    let elevation: Elevation

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let parameters = elevation.parameters(for: colorScheme)

        if parameters.opacity == 0 {
            content
        } else {
            content.shadow(
                color: Palette.shadowTint.opacity(parameters.opacity),
                radius: parameters.radius,
                x: 0,
                y: parameters.y
            )
        }
    }
}

extension View {

    /// Lifts this view off its background with an appearance-aware shadow.
    ///
    /// - Parameter elevation: How far off the background the surface should sit.
    func elevation(_ elevation: Elevation) -> some View {
        modifier(ElevationModifier(elevation: elevation))
    }
}

// MARK: - Typography

/// Semantic text roles.
///
/// **The rule: every font here is built from a `Font.TextStyle`, never from a
/// fixed point size.** `Font.system(.body, …)` scales with the reader's Dynamic
/// Type setting; `Font.system(size: 17)` does not, and an app full of the
/// latter is simply unreadable for anyone who has turned text size up — which
/// is a large fraction of users, not an edge case.
///
/// Weight and design (rounded, monospaced) *may* be customised, because neither
/// affects scaling. Size may not.
///
/// Roles are named for their job rather than their appearance, so a later
/// decision to make section headers smaller is one edit here instead of a
/// search for `.subheadline` across the app.
///
/// ```swift
/// Text("Settings").font(Typography.screenTitle)
/// ```
enum Typography {

    /// The title of a screen, when it is drawn in the content rather than in a
    /// navigation bar.
    ///
    /// Rounded, because it matches the numeric display face already used for
    /// prominent values elsewhere in the app.
    static let screenTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)

    /// The header above a group of related content.
    ///
    /// Matches the existing `Card` title (`.subheadline.weight(.semibold)`) so
    /// design-system sections and cards sit at the same level in the hierarchy.
    static let sectionHeader = Font.system(.subheadline, weight: .semibold)

    /// Default running text.
    static let body = Font.system(.body)

    /// Supporting text: hints, timestamps, secondary detail.
    ///
    /// Mapped to `.footnote` rather than `.caption`. At the default Dynamic Type
    /// size `.caption` is 12pt and `.caption2` 11pt — below Apple's own 13pt
    /// floor for sustained reading. `.footnote` is the smallest style that stays
    /// comfortable, and it matches the secondary text already used in `Card`.
    static let caption = Font.system(.footnote)

    /// Monospaced text: identifiers, hashes, versions, raw values.
    ///
    /// Still `.body`-relative, so it scales like everything else. Reach for this
    /// when column alignment or character-by-character comparison matters — not
    /// for decoration.
    static let mono = Font.system(.body, design: .monospaced)
}

// MARK: - Previews

#Preview("Typography") {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Screen title").font(Typography.screenTitle)
            Text("Section header").font(Typography.sectionHeader)
            Text("Body text carries the bulk of the reading, and wraps across as many lines as it needs.")
                .font(Typography.body)
            Text("Caption — supporting detail.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
            Text("mono-1A2B3C4D")
                .font(Typography.mono)
        }
        .fillWidth(alignment: .leading)
        .padding(Spacing.md)
    }
    .background(Palette.surface)
}

#Preview("Typography · Accessibility XL") {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Screen title").font(Typography.screenTitle)
            Text("Section header").font(Typography.sectionHeader)
            Text("Body text scales with the reader's setting because every role is built from a TextStyle.")
                .font(Typography.body)
            Text("Caption — supporting detail.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .fillWidth(alignment: .leading)
        .padding(Spacing.md)
    }
    .background(Palette.surface)
    .dynamicTypeSize(.accessibility3)
}

#Preview("Elevation · Light") {
    ElevationPreview()
}

#Preview("Elevation · Dark") {
    ElevationPreview()
        .preferredColorScheme(.dark)
}

/// Side-by-side elevation samples. Shared by both previews so the light and
/// dark variants are provably showing the same thing — which is the only way to
/// judge whether the dark-mode shadow tuning above actually works.
private struct ElevationPreview: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            sample("none", elevation: .none)
            sample("low", elevation: .low)
            sample("medium", elevation: .medium)
        }
        .padding(Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.surface)
    }

    private func sample(_ name: String, elevation: Elevation) -> some View {
        Text(name)
            .font(Typography.mono)
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                Palette.surfaceElevated,
                in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            )
            .elevation(elevation)
    }
}
