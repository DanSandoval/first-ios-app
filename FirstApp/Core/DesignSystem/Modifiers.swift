import SwiftUI

// MARK: - Card surface

/// Wraps content in the app's standard card container.
///
/// Deliberately identical to the existing `Card` view's container: `Spacing.md`
/// padding, `Palette.surfaceElevated` fill, `Radius.lg` continuous corners. The
/// two are visually interchangeable, which is the point — `Card` supplies a
/// title and an icon, this modifier supplies the surface alone for content that
/// does not want a header.
private struct CardSurfaceModifier: ViewModifier {
    let elevation: Elevation

    func body(content: Content) -> some View {
        content
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Palette.surfaceElevated,
                in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            )
            .elevation(elevation)
    }
}

// MARK: - Shimmer

/// A skeleton-loading shimmer.
///
/// Respects `accessibilityReduceMotion`: with the setting on, the travelling
/// highlight is replaced by a static one. This is a real requirement, not a
/// nicety — repeating looped motion is a documented vestibular-disorder trigger,
/// and a shimmer is about as close to the worst case as a loading state gets
/// (indefinite, unprompted, and repeating for as long as the network is slow).
/// The static fallback still reads as "not real content yet", which is the whole
/// job of a skeleton.
private struct ShimmerModifier: ViewModifier {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // `content` deliberately sits outside the conditional. Branching on
        // `isActive` around it would give the loading and loaded states
        // different structural identities, and SwiftUI would tear the subtree
        // down and rebuild it the moment the shimmer stopped — silently
        // resetting any `@State` the caller's content happens to hold. Only the
        // overlay's *contents* are conditional, so `ShimmerSweep` (and its
        // repeating animation) is still torn down when the shimmer ends.
        content
            .overlay {
                if isActive {
                    sweep
                        // Confines the highlight to the content's own alpha, so
                        // it follows rounded corners and non-rectangular shapes
                        // without this modifier needing to know the shape.
                        .blendMode(.sourceAtop)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // Isolates the blend above to content + overlay. Without it the
            // `.sourceAtop` composite would reach whatever is behind the view
            // as well.
            .compositingGroup()
    }

    @ViewBuilder
    private var sweep: some View {
        if reduceMotion {
            Palette.shimmerHighlight
        } else {
            ShimmerSweep()
        }
    }
}

/// The travelling highlight band. Split out so that its `@State` is created
/// fresh when the shimmer turns on and torn down when it turns off, rather than
/// leaving a `repeatForever` animation running behind an inactive modifier.
private struct ShimmerSweep: View {
    @State private var phase: CGFloat = 0

    private static let duration: TimeInterval = 1.2

    /// Band width as a fraction of the content width. Narrow enough to read as
    /// a highlight sweeping past rather than the whole view pulsing.
    private static let bandFraction: CGFloat = 0.45

    var body: some View {
        GeometryReader { proxy in
            let band = max(proxy.size.width * Self.bandFraction, 1)

            LinearGradient(
                colors: [
                    Palette.shimmerHighlight.opacity(0),
                    Palette.shimmerHighlight,
                    Palette.shimmerHighlight.opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band)
            // phase 0 parks the band just off the leading edge, phase 1 just
            // off the trailing edge, so the highlight never pops in or out.
            .offset(x: phase * (proxy.size.width + band) - band)
            .onAppear {
                withAnimation(.linear(duration: Self.duration).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
    }
}

// MARK: - View API

extension View {

    /// Wraps this view in the app's standard card surface.
    ///
    /// - Parameter elevation: Shadow preset. Defaults to ``Elevation/none``,
    ///   which is what matches a card sitting in a grouped list — there the
    ///   depth comes from `Palette.surfaceElevated` against `Palette.surface`,
    ///   and adding a shadow only makes the card look like it is peeling off the
    ///   page. Pass ``Elevation/low`` or ``Elevation/medium`` for a card that
    ///   genuinely floats: a drag preview, a popover, an overlay.
    ///
    /// ```swift
    /// VStack(alignment: .leading, spacing: Spacing.sm) {
    ///     Text("Latency").font(Typography.sectionHeader)
    ///     Text("42 ms").font(Typography.mono)
    /// }
    /// .cardSurface()
    /// ```
    func cardSurface(elevation: Elevation = .none) -> some View {
        modifier(CardSurfaceModifier(elevation: elevation))
    }

    /// Overlays a skeleton-loading shimmer while `isActive` is `true`.
    ///
    /// Apply it to placeholder shapes, not to real content — a shimmer over text
    /// the reader can already read is noise:
    ///
    /// ```swift
    /// RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
    ///     .fill(Palette.skeleton)
    ///     .frame(height: 16)
    ///     .shimmer(isActive: state.isLoading)
    /// ```
    ///
    /// - Parameter isActive: Whether content is still loading. When `false` the
    ///   highlight and its repeating animation are torn down; the content keeps
    ///   its identity across the transition, so any `@State` inside it survives.
    ///
    /// - Important: The shimmer is decorative and is hidden from VoiceOver.
    ///   Give the surrounding placeholder an accessibility label of its own
    ///   (`.accessibilityLabel("Loading")`) so the screen is not silent while a
    ///   request is in flight.
    ///
    /// - Note: Renders static when *Reduce Motion* is on.
    func shimmer(isActive: Bool) -> some View {
        modifier(ShimmerModifier(isActive: isActive))
    }

    /// Stretches this view across the width it is offered.
    ///
    /// Shorthand for the `frame(maxWidth: .infinity, alignment:)` that otherwise
    /// appears on nearly every row and label in a leading-aligned layout.
    ///
    /// - Parameter alignment: Where the content sits inside the stretched frame.
    ///   Defaults to `.leading`, which is right far more often than SwiftUI's own
    ///   `.center` default for text.
    func fillWidth(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
    }
}

// MARK: - Previews

/// One line of a preview skeleton. A named type rather than a bare array of
/// widths so the `ForEach` has a stable identity to key off.
private struct SkeletonLine: Identifiable {
    let id: Int
    let fraction: CGFloat

    static let samples = [
        SkeletonLine(id: 0, fraction: 1.0),
        SkeletonLine(id: 1, fraction: 0.8),
        SkeletonLine(id: 2, fraction: 0.55)
    ]
}

#Preview("Card surface") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Interchangeable with Card")
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Palette.textSecondary)
                Text("Same padding, fill and corner radius — this one just has no title row.")
                    .font(Typography.body)
            }
            .cardSurface()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Floating")
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Palette.textSecondary)
                Text("Elevation .medium, for content that sits above the page.")
                    .font(Typography.body)
            }
            .cardSurface(elevation: .medium)
        }
        .padding(Spacing.md)
    }
    .background(Palette.surface)
}

#Preview("Shimmer") {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Skeleton")
                .font(Typography.sectionHeader)
                .foregroundStyle(Palette.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(SkeletonLine.samples) { line in
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.skeleton)
                        .frame(height: 16)
                        .fillWidth()
                        .scaleEffect(x: line.fraction, anchor: .leading)
                }
            }
            .shimmer(isActive: true)
            .accessibilityElement()
            .accessibilityLabel("Loading")

            Text("With Reduce Motion on, the travelling band is replaced by a static tint. "
                 + "Toggle it in the preview's accessibility inspector, or in Settings › "
                 + "Accessibility › Motion on device.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .cardSurface()
        .padding(Spacing.md)
    }
    .background(Palette.surface)
}

#Preview("Card surface · Dark") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Grouped")
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Palette.textSecondary)
                Text("No shadow — the lighter surface carries the depth.")
                    .font(Typography.body)
            }
            .cardSurface()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Floating")
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Palette.textSecondary)
                Text("A tight, dialed-back shadow rather than a soft cloud.")
                    .font(Typography.body)
            }
            .cardSurface(elevation: .medium)
        }
        .padding(Spacing.md)
    }
    .background(Palette.surface)
    .preferredColorScheme(.dark)
}
