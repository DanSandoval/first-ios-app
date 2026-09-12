import SwiftUI

struct ItemDetailView: View {
    let item: DemoItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: item.symbol)
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)

                Text(item.name)
                    .font(.largeTitle.bold())

                Text(item.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ItemDetailView(
            item: DemoItem(
                name: "State",
                symbol: "circle.hexagongrid.fill",
                detail: "A property marked @State is owned by the view and stored by SwiftUI. Change it and SwiftUI rebuilds the body for you."
            )
        )
    }
}
