import SwiftUI

// MARK: - Buttons

/// The button style for the single most important action on a screen.
///
/// Filled with ``Palette/accent``. There should be at most one of these visible
/// at a time — two "primary" buttons side by side means neither is primary.
///
/// ```swift
/// Button("Save") { save() }
///     .buttonStyle(PrimaryButtonStyle())
/// ```
///
/// - Note: The minimum height is 44pt, Apple's documented minimum tap target.
///   A control that merely *looks* big enough because of its label is not the
///   same thing: the frame is what gets hit-tested.
struct PrimaryButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        // Nested so it can read `isEnabled`. `makeBody` is not a View body, so
        // it has no environment of its own to read from.
        Surface(configuration: configuration)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(isEnabled ? Palette.onAccent : Palette.textTertiary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    isEnabled ? Palette.accent : Palette.controlFill,
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                )
                // The whole frame is tappable, including the padding — not just
                // the glyphs of the label.
                .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .opacity(configuration.isPressed ? 0.85 : 1)
                .scaleEffect(pressedScale)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        /// Reduce Motion keeps the opacity dip but drops the scale: the press
        /// still reads, without a control that visibly moves under the finger.
        private var pressedScale: CGFloat {
            guard configuration.isPressed, !reduceMotion else { return 1 }
            return 0.97
        }
    }
}

/// The button style for supporting actions.
///
/// A tinted label on a neutral system fill — present, but clearly subordinate to
/// ``PrimaryButtonStyle``. Several of these on one screen is fine.
struct SecondaryButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(Typography.body.weight(.medium))
                .foregroundStyle(isEnabled ? Palette.accent : Palette.textTertiary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    Palette.controlFill,
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .scaleEffect(pressedScale)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var pressedScale: CGFloat {
            guard configuration.isPressed, !reduceMotion else { return 1 }
            return 0.97
        }
    }
}

// MARK: - Section header

/// A header introducing a group of content.
///
/// Carries the `.isHeader` accessibility trait, which is what lets VoiceOver
/// users jump between sections with the rotor instead of swiping through every
/// row. A `Text` styled to look like a header does not do that.
///
/// ```swift
/// SectionHeader(title: "Network", subtitle: "Last checked 2 minutes ago", systemImage: "wifi")
/// ```
struct SectionHeader: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String?

    /// - Parameters:
    ///   - title: The section name.
    ///   - subtitle: Optional supporting line beneath the title.
    ///   - systemImage: Optional SF Symbol. Purely decorative — it is hidden
    ///     from VoiceOver, because it repeats what the title already says.
    init(title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Palette.textSecondary)

                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Labeled row

/// A label-and-value row: label leading, value trailing in a secondary colour.
///
/// The layout is not a fixed `HStack`. At large Dynamic Type sizes a fixed row
/// has to resolve the overflow somehow, and every option is bad — truncating the
/// label ("Bundle identi…" tells the reader nothing), truncating the value, or
/// squeezing both into unreadable columns. `ViewThatFits` sidesteps the choice:
/// the side-by-side layout is used when both halves genuinely fit on one line,
/// and the row stacks vertically when they do not.
///
/// ```swift
/// LabeledRow(label: "Build", value: "1.0 (42)", isMonospaced: true)
/// ```
struct LabeledRow: View {
    private let label: String
    private let value: String
    private let isMonospaced: Bool

    /// - Parameters:
    ///   - label: What the value is.
    ///   - value: The value itself.
    ///   - isMonospaced: Pass `true` for identifiers, hashes, versions and
    ///     anything else the reader may need to compare character by character.
    init(label: String, value: String, isMonospaced: Bool = false) {
        self.label = label
        self.value = value
        self.isMonospaced = isMonospaced
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Preferred: one line. `lineLimit(1)` is what makes the fit test
            // meaningful — wrapping text would always "fit" by shrinking itself
            // into a tall column, and this branch would never be rejected.
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                labelText.lineLimit(1)
                Spacer(minLength: Spacing.sm)
                valueText.lineLimit(1)
            }

            // Fallback: stacked, both halves free to wrap.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                labelText
                valueText.fillWidth(alignment: .leading)
            }
        }
        .frame(minHeight: 44)
        // One swipe stop reading "Build, 1.0 (42)" rather than two disconnected
        // fragments the reader has to re-associate.
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .font(Typography.body)
            .foregroundStyle(Palette.textPrimary)
    }

    private var valueText: some View {
        Text(value)
            .font(isMonospaced ? Typography.mono : Typography.body)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.trailing)
            // Identifiers exist to be copied.
            .textSelection(.enabled)
    }
}

// MARK: - Badge

/// The meaning a ``Badge`` conveys, which determines its colour.
///
/// Tone is chosen by *meaning*, never by the colour wanted — that is what keeps
/// green meaning "good" everywhere in the app instead of "green looked nice on
/// this screen".
enum BadgeTone: CaseIterable {

    /// No valence: a count, a category, a plain fact.
    case neutral

    /// Healthy, complete, passing.
    case success

    /// Degraded, deprecated, needs attention but is not broken.
    case warning

    /// Failed, expired, destructive.
    case danger

    /// The text and border colour.
    fileprivate var foreground: Color {
        switch self {
        case .neutral: return Palette.textSecondary
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .danger: return Palette.danger
        }
    }

    /// The pill fill.
    ///
    /// Derived from ``foreground`` at low opacity rather than defined
    /// separately, so it adapts wherever the system colour adapts — including
    /// dark mode, where `.systemGreen` is a different green.
    fileprivate var background: Color {
        switch self {
        case .neutral: return Palette.controlFillSubtle
        default: return foreground.opacity(0.15)
        }
    }

    /// Spoken prefix, so the badge's meaning survives the loss of colour.
    ///
    /// Colour alone is never an acceptable carrier of meaning: it is invisible
    /// to VoiceOver and ambiguous for the ~8% of men with a colour vision
    /// deficiency.
    fileprivate var accessibilityPrefix: String? {
        switch self {
        case .neutral: return nil
        case .success: return "Success"
        case .warning: return "Warning"
        case .danger: return "Error"
        }
    }
}

/// A small pill conveying status.
///
/// ```swift
/// Badge(text: "Online", tone: .success)
/// ```
struct Badge: View {
    private let text: String
    private let tone: BadgeTone

    /// - Parameters:
    ///   - text: The label. Keep it to one or two words; a badge that wraps is
    ///     a sentence wearing a costume.
    ///   - tone: What the badge means. See ``BadgeTone``.
    init(text: String, tone: BadgeTone) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(Typography.caption.weight(.semibold))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(tone.background, in: Capsule(style: .continuous))
            .accessibilityLabel(spokenLabel)
    }

    /// The badge's colour is meaningless to VoiceOver, so the tone is spoken.
    private var spokenLabel: Text {
        guard let prefix = tone.accessibilityPrefix else { return Text(text) }
        return Text("\(prefix), \(text)")
    }
}

// MARK: - Hairline divider

/// A separator drawn at true one-pixel width.
///
/// `Divider()` and a `1` in a frame both give one *point*, which is two or three
/// physical pixels on every shipping iPhone — noticeably heavier than the lines
/// in a system `List`. Dividing by the display scale gives the same hairline the
/// system draws.
///
/// The scale comes from `@Environment(\.displayScale)` rather than
/// `UIScreen.main.scale`: `UIScreen.main` is deprecated, is wrong on an external
/// display or in a Mac Catalyst window, and — unlike the environment value —
/// does not invalidate the view when the view moves to a different screen.
struct HairlineDivider: View {

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            // `max(_:1)` guards the degenerate scale some preview and test
            // environments report, which would otherwise divide into a bar.
            .frame(height: 1 / max(displayScale, 1))
            .fillWidth()
            // Purely visual: it separates content that VoiceOver already reads
            // as separate elements.
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Components · Light") {
    ComponentGallery()
}

#Preview("Components · Dark") {
    ComponentGallery()
        .preferredColorScheme(.dark)
}

#Preview("Components · Accessibility XL") {
    ComponentGallery()
        .dynamicTypeSize(.accessibility2)
}

/// One gallery shared by every preview above, so the light, dark and large-type
/// variants cannot drift out of sync.
private struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                buttons
                rows
                badges
            }
            .padding(Spacing.md)
        }
        .background(Palette.surface)
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: "Buttons",
                subtitle: "Pressed and disabled states",
                systemImage: "hand.tap.fill"
            )

            Button("Save changes") {}
                .buttonStyle(PrimaryButtonStyle())
                .fillWidth(alignment: .center)

            Button("Save changes") {}
                .buttonStyle(PrimaryButtonStyle())
                .fillWidth(alignment: .center)
                .disabled(true)

            Button("Learn more") {}
                .buttonStyle(SecondaryButtonStyle())
                .fillWidth(alignment: .center)

            Button("Learn more") {}
                .buttonStyle(SecondaryButtonStyle())
                .fillWidth(alignment: .center)
                .disabled(true)
        }
        .cardSurface()
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Build", systemImage: "hammer.fill")

            LabeledRow(label: "Version", value: "1.0")
            HairlineDivider()
            LabeledRow(label: "Build number", value: "42", isMonospaced: true)
            HairlineDivider()
            LabeledRow(
                label: "Bundle identifier",
                value: "com.dansandoval.firstiosapp",
                isMonospaced: true
            )
        }
        .cardSurface()
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Status", systemImage: "circle.hexagongrid.fill")

            HStack(spacing: Spacing.sm) {
                Badge(text: "Draft", tone: .neutral)
                Badge(text: "Online", tone: .success)
                Badge(text: "Degraded", tone: .warning)
                Badge(text: "Failed", tone: .danger)
            }
            .fillWidth()
        }
        .cardSurface()
    }
}
