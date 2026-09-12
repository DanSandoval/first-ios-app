import SwiftUI

/// Semantic colour roles for the app.
///
/// ## Why there are no hex values in this file
///
/// Every role below resolves from a **system semantic colour** — `Color(.label)`,
/// `Color(.systemGroupedBackground)`, `Color(.systemRed)` and friends — rather
/// than from a literal. That is not stylistic preference; a hand-picked hex is a
/// dark-mode bug that has not surfaced yet:
///
/// - A literal has exactly one value. Dark mode needs a second one, and
///   *Increase Contrast* (Settings → Accessibility → Display & Text Size) needs
///   a third. System colours carry all of them and pick the right one from the
///   trait environment for free. `#1C1C1E` looks correct until someone turns on
///   a setting you never tested.
/// - The system palette is tuned against the real backdrops it will sit on,
///   including behind translucent material, where a flat literal turns muddy.
/// - `.systemRed` is not the same red in light and dark mode — the dark variant
///   is lightened to hold contrast against a black background. Shipping one
///   fixed red means shipping a red that fails contrast in one of the two.
///
/// If a role you need is missing, add it here resolving from a system colour.
/// Do not reach for a literal at the call site.
///
/// ## The two deliberate exceptions
///
/// ``shadowTint`` and ``onAccent`` are fixed values, each for a documented
/// reason where an adaptive colour is actively wrong. Both are explained at
/// their definitions. There should never be a third.
enum Palette {

    // MARK: - Surfaces

    /// The backdrop of a screen.
    ///
    /// Grouped rather than plain `.systemBackground`, because the app's screens
    /// are card lists — and the grouped pair is what makes
    /// ``surfaceElevated`` read as raised in *both* appearances (darker
    /// backdrop in light mode, lighter card in dark mode).
    static let surface = Color(.systemGroupedBackground)

    /// The fill of a card or any surface sitting on ``surface``.
    ///
    /// Matches the existing `Card` container exactly.
    static let surfaceElevated = Color(.secondarySystemGroupedBackground)

    /// A surface for content nested *inside* a card — a code block, an inset
    /// well, a skeleton placeholder's backdrop.
    static let surfaceInset = Color(.tertiarySystemGroupedBackground)

    // MARK: - Lines

    /// A divider between rows of content.
    ///
    /// Semi-transparent by design: it blends with whatever surface it lands on
    /// instead of fighting it. Draw it at true hairline width — see
    /// `HairlineDivider`.
    static let separator = Color(.separator)

    /// A border that must remain visible over any surface, including images.
    ///
    /// Opaque, unlike ``separator``. Reach for it only when a translucent line
    /// would disappear.
    static let border = Color(.opaqueSeparator)

    // MARK: - Text

    /// Primary reading text.
    static let textPrimary = Color(.label)

    /// Supporting text: values, captions, subtitles.
    static let textSecondary = Color(.secondaryLabel)

    /// De-emphasised text: placeholders, disabled labels, trailing metadata.
    static let textTertiary = Color(.tertiaryLabel)

    // MARK: - Accent

    /// The app's tint.
    ///
    /// Resolves from the `AccentColor` asset, which is where the app-wide tint
    /// is already defined (`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`), so
    /// this stays in step with system controls automatically.
    static let accent = Color.accentColor

    /// Content colour for anything drawn *on top of* ``accent``.
    ///
    /// **Deliberate exception #1 of 2.** UIKit has no inverse-of-`label` role,
    /// and the near-substitutes are wrong here: `Color(.systemBackground)` would
    /// paint black text on a bright blue fill in dark mode, which no system
    /// control does. A saturated accent is dark enough to carry white in both
    /// appearances, so white is the correct fixed answer — stated once, here,
    /// rather than sprinkled as `.white` through the component files.
    static let onAccent = Color(uiColor: .white)

    // MARK: - Status

    /// A completed, healthy or passing state.
    ///
    /// The system greens/oranges/reds below are appearance-adaptive and are the
    /// same hues the reader already learned from Mail, Settings and Health.
    /// Inventing a brand green buys nothing and costs the dark-mode variant.
    static let success = Color(.systemGreen)

    /// A degraded state, or an action that deserves a second look.
    static let warning = Color(.systemOrange)

    /// A failure, or a destructive action.
    static let danger = Color(.systemRed)

    /// An informational or in-progress state with no valence.
    ///
    /// Grey rather than blue on purpose: blue reads as interactive.
    static let neutral = Color(.secondaryLabel)

    // MARK: - Fills

    /// The resting fill of a non-tinted control — a secondary button, a chip.
    static let controlFill = Color(.tertiarySystemFill)

    /// A quieter fill, for badges and other passive tinted shapes.
    static let controlFillSubtle = Color(.secondarySystemFill)

    // MARK: - Skeletons

    /// The body of a loading placeholder block.
    ///
    /// Fills adapt with the appearance *and* are translucent, so a placeholder
    /// built from this sits correctly on any surface without knowing which one
    /// it landed on.
    static let skeleton = Color(.secondarySystemFill)

    /// The travelling highlight in `.shimmer(isActive:)`.
    ///
    /// Translucent, so the sweep lightens dark UI and darkens light UI from the
    /// same single definition.
    static let shimmerHighlight = Color(.tertiarySystemFill)

    // MARK: - Shadow

    /// The colour a shadow is tinted with.
    ///
    /// **Deliberate exception #2 of 2.** A shadow models light that did not
    /// reach the surface behind it, so it is an absence — it must darken in
    /// every appearance. An adaptive colour inverts: `Color(.label)` would turn
    /// a dark-mode shadow into a white *glow* around the card.
    ///
    /// The dark-mode adjustment therefore belongs in the alpha and blur radius,
    /// not the hue — which is exactly what ``Elevation`` does with it.
    static let shadowTint = Color(.sRGBLinear, white: 0, opacity: 1)
}

// MARK: - Previews

#Preview("Palette · Light") {
    PalettePreview()
}

#Preview("Palette · Dark") {
    PalettePreview()
        .preferredColorScheme(.dark)
}

/// Swatch sheet used by the previews above. Keeping it in one place means the
/// light and dark previews cannot drift apart.
private struct PalettePreview: View {
    private let roles: [(String, Color)] = [
        ("surface", Palette.surface),
        ("surfaceElevated", Palette.surfaceElevated),
        ("surfaceInset", Palette.surfaceInset),
        ("separator", Palette.separator),
        ("textPrimary", Palette.textPrimary),
        ("textSecondary", Palette.textSecondary),
        ("accent", Palette.accent),
        ("success", Palette.success),
        ("warning", Palette.warning),
        ("danger", Palette.danger),
        ("neutral", Palette.neutral)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.sm) {
                ForEach(roles, id: \.0) { name, color in
                    HStack(spacing: Spacing.md) {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(color)
                            .frame(width: 44, height: 44)
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(Palette.separator, lineWidth: 1)
                            }

                        Text(name)
                            .font(Typography.mono)
                            .foregroundStyle(Palette.textPrimary)

                        Spacer(minLength: Spacing.sm)
                    }
                }
            }
            .padding(Spacing.md)
        }
        .background(Palette.surface)
    }
}
