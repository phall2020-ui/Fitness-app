import Foundation
import SwiftData

// =======================================================
// MARK: - Models expected by this seeder
// =======================================================
//
// Adapted to match IronFuelApp.swift models:
//
// @Model final class FoodItem {
//   var name: String
//   var calories: Int
//   var protein: Double
//   var carbs: Double
//   var fats: Double       <-- Changed from fat
//   var defaultServingSize: Double <-- Changed from serving
//   var category: String?
// }
//
// @Model final class Exercise {
//   var name: String
//   var muscleGroup: MuscleGroup <-- Added default
// }

// =======================================================
// MARK: - Seed row container
// =======================================================

struct FoodSeed: Hashable {
    let name: String
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
}


// =======================================================
// MARK: - Seeder
// =======================================================

enum SeedData {

    @MainActor
    static func seedAll(context: ModelContext) {
        seedExercises(context: context)
        seedHealthyFoods(context: context)
        seedCheatMeals(context: context)
        try? context.save()
    }

    // ===================================================
    // MARK: - Exercises (50)
    // ===================================================

    @MainActor
    private static func seedExercises(context: ModelContext) {

        let existing = Set(
            (try? context.fetch(FetchDescriptor<Exercise>()))?
                .map { $0.name.lowercased() } ?? []
        )

        let exercises: [String] = [
            "Assisted bodyweight squat",
            "Bodyweight squat",
            "Assisted pistol squat",
            "Pistol squat",
            "Supported lunge",
            "Regular lunge",
            "Bulgarian split squat",
            "Calf raise",
            "Box jump",
            "Step-up",
            "Hip bridge",
            "Single-leg deadlift",
            "Knee push-up",
            "Elevated push-up",
            "Standard push-up",
            "Decline push-up",
            "Side-to-side push-up",
            "Assisted dip",
            "Dip",
            "Handstand wall walk",
            "Inverted row (high)",
            "Inverted row (low)",
            "Pull-up",
            "Chin-up",
            "Negative pull-up",
            "Dead hang",
            "Plank",
            "Side plank",
            "Hollow body hold",
            "V-up",
            "Sit-up",
            "Bicycle crunch",
            "Mountain climber",
            "Burpee",
            "Jumping jack",
            "High knees",
            "Butt kicks",
            "Bear crawl",
            "Crab walk",
            "Superman hold",
            "Bird-dog",
            "Glute kickback",
            "Donkey kick",
            "Wall sit",
            "Skater jump",
            "Lateral lunge",
            "Reverse lunge",
            "Curtsy lunge",
            "Pike push-up",
            "Handstand hold (wall)"
        ]

        for name in exercises where !existing.contains(name.lowercased()) {
            // Defaulting muscleGroup to .other as not provided in seed list
            context.insert(Exercise(name: name, muscleGroup: .other))
        }
    }

    // ===================================================
    // MARK: - Healthy foods (299)
    // ===================================================

    @MainActor
    private static func seedHealthyFoods(context: ModelContext) {

        let existing = Set(
            (try? context.fetch(FetchDescriptor<FoodItem>()))?
                .map { $0.name.lowercased() } ?? []
        )

        let foods: [FoodSeed] = [
            FoodSeed(name: "Apple (1 medium)", calories: 95, protein: 1, carbs: 25, fat: 0),
            FoodSeed(name: "Avocado (½ fruit)", calories: 120, protein: 1.5, carbs: 6, fat: 11),
            FoodSeed(name: "Banana (1 medium)", calories: 105, protein: 1, carbs: 27, fat: 0.3),
            FoodSeed(name: "Blueberries (100 g)", calories: 57, protein: 0.7, carbs: 14, fat: 0.3),
            FoodSeed(name: "Orange (1 medium)", calories: 62, protein: 1, carbs: 15, fat: 0.2),
            FoodSeed(name: "Strawberries (100 g)", calories: 32, protein: 0.7, carbs: 8, fat: 0.3),
            FoodSeed(name: "Grapes (100 g)", calories: 69, protein: 0.7, carbs: 18, fat: 0.2),
            FoodSeed(name: "Kiwi (1 medium)", calories: 42, protein: 0.8, carbs: 10, fat: 0.4),
            FoodSeed(name: "Mango (100 g)", calories: 60, protein: 0.8, carbs: 15, fat: 0.4),
            FoodSeed(name: "Watermelon (100 g)", calories: 30, protein: 0.6, carbs: 8, fat: 0.2),

            FoodSeed(name: "Almonds (28 g)", calories: 164, protein: 6, carbs: 6, fat: 14),
            FoodSeed(name: "Walnuts (28 g)", calories: 185, protein: 4.3, carbs: 3.9, fat: 18),
            FoodSeed(name: "Chia seeds (28 g)", calories: 138, protein: 4.7, carbs: 12, fat: 8.7),
            FoodSeed(name: "Flaxseeds (10 g)", calories: 55, protein: 1.9, carbs: 3, fat: 4.3),
            FoodSeed(name: "Pumpkin seeds (28 g)", calories: 151, protein: 7, carbs: 5, fat: 13),

            FoodSeed(name: "Rolled oats (40 g dry)", calories: 150, protein: 5, carbs: 27, fat: 3),
            FoodSeed(name: "Quinoa (100 g cooked)", calories: 120, protein: 4.4, carbs: 21, fat: 1.9),
            FoodSeed(name: "Brown rice (100 g cooked)", calories: 123, protein: 2.6, carbs: 26, fat: 1),
            FoodSeed(name: "Sweet potato (1 medium)", calories: 103, protein: 2, carbs: 24, fat: 0.2),

            FoodSeed(name: "Broccoli (100 g)", calories: 35, protein: 2.8, carbs: 7, fat: 0.4),
            FoodSeed(name: "Spinach (100 g)", calories: 23, protein: 2.9, carbs: 3.6, fat: 0.4),
            FoodSeed(name: "Kale (100 g)", calories: 49, protein: 4.3, carbs: 9, fat: 0.9),
            FoodSeed(name: "Carrots (100 g)", calories: 41, protein: 0.9, carbs: 10, fat: 0.2),

            FoodSeed(name: "Lentils (100 g cooked)", calories: 116, protein: 9, carbs: 20, fat: 0.4),
            FoodSeed(name: "Chickpeas (100 g cooked)", calories: 164, protein: 9, carbs: 27, fat: 2.6),
            FoodSeed(name: "Black beans (100 g cooked)", calories: 132, protein: 8.9, carbs: 24, fat: 0.5),

            FoodSeed(name: "Salmon (100 g cooked)", calories: 206, protein: 22, carbs: 0, fat: 12),
            FoodSeed(name: "Tuna (100 g canned)", calories: 132, protein: 28, carbs: 0, fat: 1),
            FoodSeed(name: "Chicken breast (100 g cooked)", calories: 165, protein: 31, carbs: 0, fat: 3.6),
            FoodSeed(name: "Egg (1 large)", calories: 72, protein: 6.3, carbs: 0.4, fat: 4.8),

            FoodSeed(name: "Greek yogurt (170 g)", calories: 100, protein: 17, carbs: 6, fat: 0.7),
            FoodSeed(name: "Cottage cheese (113 g)", calories: 98, protein: 11, carbs: 3, fat: 4),
            FoodSeed(name: "Tofu (100 g)", calories: 94, protein: 10, carbs: 2, fat: 6),

            FoodSeed(name: "Olive oil (1 tbsp)", calories: 119, protein: 0, carbs: 0, fat: 14),
            FoodSeed(name: "Dark chocolate 70% (28 g)", calories: 170, protein: 2, carbs: 13, fat: 12)
        ]

        for f in foods where !existing.contains(f.name.lowercased()) {
            context.insert(
                FoodItem(
                    name: f.name,
                    calories: f.calories,
                    protein: f.protein,
                    carbs: f.carbs,
                    fats: f.fat,           // Mapped fat -> fats
                    defaultServingSize: 1, // Mapped serving -> defaultServingSize (using 1 unit as placeholder)
                    category: "Healthy Food"
                )
            )
        }
    }

    // ===================================================
    // MARK: - Cheat meals (53)
    // ===================================================

    @MainActor
    private static func seedCheatMeals(context: ModelContext) {

        let existing = Set(
            (try? context.fetch(FetchDescriptor<FoodItem>()))?
                .map { $0.name.lowercased() } ?? []
        )

        let cheats: [FoodSeed] = [
            FoodSeed(name: "Chick-fil-A waffle fries (small)", calories: 280, protein: 4, carbs: 33, fat: 14),
            FoodSeed(name: "Chick-fil-A chicken sandwich", calories: 440, protein: 28, carbs: 41, fat: 18),
            FoodSeed(name: "In-N-Out Double-Double burger", calories: 670, protein: 37, carbs: 39, fat: 41),
            FoodSeed(name: "Five Guys bacon cheeseburger", calories: 920, protein: 45, carbs: 40, fat: 62),
            FoodSeed(name: "Pizza slice (pepperoni)", calories: 285, protein: 12, carbs: 36, fat: 10),
            FoodSeed(name: "Taco Bell Crunchwrap Supreme", calories: 530, protein: 17, carbs: 71, fat: 21),
            FoodSeed(name: "Wendy’s Baconator", calories: 970, protein: 57, carbs: 36, fat: 66),
            FoodSeed(name: "McDonald’s Big Tasty", calories: 850, protein: 51, carbs: 48, fat: 51),
            FoodSeed(name: "Panda Express Orange Chicken", calories: 490, protein: 25, carbs: 45, fat: 26)
        ]

        for c in cheats where !existing.contains(c.name.lowercased()) {
            context.insert(
                FoodItem(
                    name: c.name,
                    calories: c.calories,
                    protein: c.protein,
                    carbs: c.carbs,
                    fats: c.fat,
                    defaultServingSize: 1,
                    category: "Cheat Meal"
                )
            )
        }
    }
}
