import SwiftUI
import SwiftData

struct EditExerciseSetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var exerciseSet: ExerciseSet
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Set Details") {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("kg", value: $exerciseSet.weight, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kg")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Reps")
                        Spacer()
                        TextField("reps", value: $exerciseSet.reps, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    
                    if exerciseSet.rpe != nil {
                        HStack {
                            Text("RPE")
                            Spacer()
                            TextField("RPE", value: Binding(
                                get: { exerciseSet.rpe ?? 0 },
                                set: { exerciseSet.rpe = $0 == 0 ? nil : $0 }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        }
                    }
                    
                    Toggle("Completed", isOn: $exerciseSet.isCompleted)
                    
                    Picker("Set Type", selection: $exerciseSet.type) {
                        ForEach(SetType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                }
                
                Section {
                    Button("Delete Set", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .alert("Delete Set", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    modelContext.delete(exerciseSet)
                    try? modelContext.save()
                    dismiss()
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
}