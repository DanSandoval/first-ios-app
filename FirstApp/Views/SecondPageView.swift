import SwiftUI

/// Pushed onto Home's `NavigationStack`. It deliberately has no stack of its
/// own — the pushing view owns the stack.
struct SecondPageView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            Text("Second Page")
                .font(.largeTitle.bold())

            Text("You pushed a new screen onto the navigation stack. The back button and the edge swipe are free — SwiftUI adds both.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                dismiss()
            } label: {
                Label("Back to Home", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Second Page")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SecondPageView()
    }
}
