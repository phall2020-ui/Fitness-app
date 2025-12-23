import SwiftUI
import SwiftData

struct WorkoutHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var allWorkouts: [WorkoutSession]
    
    @State private var searchText = ""
    
    var filteredWorkouts: [WorkoutSession] {
        if searchText.isEmpty {
            return allWorkouts
        } else {
            return allWorkouts.filter { $0.title.localizedCaseInsensitiveContains(searchText) || ($0.gym?.name.localizedCaseInsensitiveContains(searchText) ?? false) }
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredWorkouts) { workout in
                NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                    WorkoutHistoryRow(workout: workout)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteWorkout(workout)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Workout History")
        .searchable(text: $searchText, prompt: "Search workouts or gyms")
        .overlay {
            if filteredWorkouts.isEmpty {
                ContentUnavailableView("No Workouts", systemImage: "dumbbell", description: Text("You haven't logged any workouts yet."))
            }
        }
    }
    
    private func deleteWorkout(_ workout: WorkoutSession) {
        modelContext.delete(workout)
        try? modelContext.save()
    }
}
