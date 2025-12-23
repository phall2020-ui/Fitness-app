import SwiftUI
import SwiftData

struct EditFoodLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var foodLog: FoodLog
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Food Details") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Food name", text: $foodLog.foodName)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Serving Size")
                        Spacer()
                        TextField("g", value: $foodLog.servingSize, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    Picker("Meal", selection: $foodLog.category) {
                        ForEach(MealCategory.allCases, id: \.self) { category in
                            Text(category.rawValue.capitalized).tag(category)
                        }
                    }
                }
                
                Section("Nutrition") {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("kcal", value: $foodLog.calories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("g", value: $foodLog.protein, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Carbs")
                        Spacer()
                        TextField("g", value: $foodLog.carbs, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Fats")
                        Spacer()
                        TextField("g", value: $foodLog.fats, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Delete Entry", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Edit Food")
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
            .alert("Delete Food Entry", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    modelContext.delete(foodLog)
                    try? modelContext.save()
                    dismiss()
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
}