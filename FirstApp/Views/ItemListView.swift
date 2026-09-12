import SwiftUI

struct DemoItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let symbol: String
    let detail: String
}

/// The second tab: a searchable list that pushes a detail screen by value.
struct ItemListView: View {
    @State private var query = ""

    private let items: [DemoItem] = [
        DemoItem(
            name: "State",
            symbol: "circle.hexagongrid.fill",
            detail: "A property marked @State is owned by the view and stored by SwiftUI, not by the struct itself. When you change it, SwiftUI throws away the old body and calls it again with the new value. That is the whole update model: you never tell a label to change its text, you change the state and let the view be rebuilt."
        ),
        DemoItem(
            name: "Bindings",
            symbol: "arrow.left.arrow.right",
            detail: "A Binding is a read-write reference to someone else's state. Writing $name instead of name hands a control the ability to write back, which is how TextField and Toggle can change a value they do not own. Without the dollar sign you are passing a snapshot of the value and edits have nowhere to go."
        ),
        DemoItem(
            name: "NavigationStack",
            symbol: "rectangle.stack.fill",
            detail: "Introduced in iOS 16 to replace NavigationView, which was deprecated. It manages a stack of pushed screens and can expose that stack as an array you control in code. Pair it with navigationDestination(for:) to push by value: the list sends a piece of data, and the stack decides which view represents it."
        ),
        DemoItem(
            name: "SF Symbols",
            symbol: "star.circle.fill",
            detail: "Apple ships several thousand vector icons that are built into the system, so using one costs nothing in app size. They align to text and inherit font size, weight, and colour automatically. Download the free SF Symbols app from Apple to browse names and check which iOS version first shipped each symbol."
        ),
        DemoItem(
            name: "Dark Mode",
            symbol: "moon.stars.fill",
            detail: "Dark mode is free if you never hardcode a colour. Semantic colours such as Color(.systemGroupedBackground) and styles such as .primary and .secondary resolve differently depending on the active appearance. Use the Xcode preview's appearance switch, or Settings in the Simulator, to check both looks before shipping."
        ),
        DemoItem(
            name: "Haptics",
            symbol: "waveform",
            detail: "Haptic feedback is the small tap you feel when a control responds. UIImpactFeedbackGenerator gives you light, medium, and heavy taps, while UINotificationFeedbackGenerator signals success, warning, or error. The Taptic Engine only exists in hardware, so none of it can be felt in the Simulator."
        ),
        DemoItem(
            name: "UserDefaults",
            symbol: "externaldrive.fill",
            detail: "UserDefaults is a small key-value store written to disk in your app's container, meant for settings and preferences rather than real data. @AppStorage wraps a single key so reading it redraws the view and writing it saves immediately. Never put passwords or tokens here — that is what the Keychain is for."
        ),
        DemoItem(
            name: "Simulator vs Device",
            symbol: "iphone.gen3",
            detail: "The Simulator runs your app on the Mac's own CPU, so it is fast but not honest. Haptics, the camera, real GPS, push notifications, and true performance all need a physical iPhone. Test on a device before you trust anything about speed, battery, or how the app feels in the hand."
        )
    ]

    private var filteredItems: [DemoItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filteredItems) { item in
                NavigationLink(value: item) {
                    Label(item.name, systemImage: item.symbol)
                }
            }
            .navigationDestination(for: DemoItem.self) { item in
                ItemDetailView(item: item)
            }
            .navigationTitle("List")
            .searchable(text: $query, prompt: "Filter")
        }
    }
}

#Preview {
    ItemListView()
}
