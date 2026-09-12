import SwiftUI

/// The first tab. Everything here is a self-contained demo of one SwiftUI idea:
/// state, animation, two-way bindings, and navigation.
struct HomeView: View {
    @State private var greeting: String?
    @State private var tapCount = 0
    @State private var name = ""
    @State private var isExcited = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    helloCard
                    counterCard
                    bindingCard
                    navigationCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("First iOS App")
        }
    }

    private var helloCard: some View {
        Card("The classic", systemImage: "hand.wave.fill") {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    greeting = greeting == nil ? "Hello, World!" : nil
                }
                Haptics.impact(.medium)
            } label: {
                Label(greeting == nil ? "Say Hello World" : "Clear",
                      systemImage: greeting == nil ? "sparkles" : "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let greeting {
                Text(greeting)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.tint)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var counterCard: some View {
        Card("Tap counter", systemImage: "number") {
            HStack(spacing: 20) {
                Button {
                    withAnimation { tapCount = max(0, tapCount - 1) }
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .disabled(tapCount == 0)

                Text("\(tapCount)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    // Animates digit-by-digit instead of cross-fading the whole label.
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)

                Button {
                    withAnimation { tapCount += 1 }
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .font(.system(size: 34))
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            Text("State drives the view: change the number and SwiftUI redraws this card for you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var bindingCard: some View {
        Card("Two-way binding", systemImage: "arrow.left.arrow.right") {
            TextField("Type your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .submitLabel(.done)

            Toggle("Excited", isOn: $isExcited.animation())

            Text(liveGreeting)
                .font(.title3.weight(.medium))
        }
    }

    private var liveGreeting: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = trimmed.isEmpty ? "stranger" : trimmed
        return "Hello, \(who)\(isExcited ? "!!!" : ".")"
    }

    private var navigationCard: some View {
        Card("Navigation", systemImage: "arrow.forward") {
            NavigationLink {
                SecondPageView()
            } label: {
                Label("Go to the second page", systemImage: "chevron.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

#Preview {
    HomeView()
}
