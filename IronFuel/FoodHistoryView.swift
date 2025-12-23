import SwiftUI
import SwiftData

struct FoodHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var allLogs: [FoodLog]
    
    @State private var searchText = ""
    
    var filteredLogs: [FoodLog] {
        if searchText.isEmpty {
            return allLogs
        } else {
            return allLogs.filter { $0.foodName.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredLogs) { log in
                HStack {
                    VStack(alignment: .leading) {
                        Text(log.foodName)
                            .font(.headline)
                        Text("\(log.timestamp.formatted(date: .abbreviated, time: .shortened)) • \(log.category.rawValue.capitalized)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(log.calories) kcal")
                            .font(.subheadline.bold())
                        Text("\(Int(log.protein))p \(Int(log.carbs))c \(Int(log.fats))f")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        modelContext.delete(log)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Food History")
        .searchable(text: $searchText, prompt: "Search foods")
        .overlay {
            if filteredLogs.isEmpty {
                ContentUnavailableView("No History", systemImage: "fork.knife", description: Text("You haven't logged any food yet."))
            }
        }
    }
}
