//
//  IronFuel.swift
//  IronFuel – Full current code including FoodLoggingModule integration
//
//  Includes:
//  - Training + Nutrition + Dashboard + Food diary
//  - VisionKit barcode scan
//  - GS1 normalisation (UPC/EAN/GTIN → GTIN-14)
//  - Lookup cascade: SwiftData cache (FoodProduct) → backend (HTTP)
//  - FoodScanViewModel + FoodScanSheet plugged into FoodLogView
//
//  Requirements:
//  - iOS 16+ (VisionKit DataScannerViewController)
//  - Add NSCameraUsageDescription to Info.plist
//

import SwiftUI
import SwiftData
import Foundation
import Charts
import VisionKit
import AVFoundation
import Speech

// MARK: - 1) ENUMS & STRUCTS

enum ExerciseType: String, Codable, CaseIterable { case weightAndReps, bodyweight, duration }
enum SetType: String, Codable, CaseIterable { case warmup, working, failure, drop }
enum Gender: String, Codable { case male, female }

enum ActivityLevel: Double, Codable, CaseIterable {
    case sedentary = 1.2
    case lightlyActive = 1.375
    case moderatelyActive = 1.55
    case veryActive = 1.725
    
    var description: String {
        switch self {
        case .sedentary: return "Sedentary (Little/no exercise)"
        case .lightlyActive: return "Lightly Active (1-3 days/week)"
        case .moderatelyActive: return "Moderately Active (3-5 days/week)"
        case .veryActive: return "Very Active (6-7 days/week)"
        }
    }
}

enum MealCategory: String, Codable, CaseIterable { case breakfast, lunch, dinner, snack }

enum FoodCategory: String, Codable, CaseIterable {
    case protein = "Protein"
    case carbs = "Carbs"
    case fats = "Fats"
    case vegetables = "Vegetables"
    case dairy = "Dairy"
    case fruit = "Fruit"
}

enum BadgeType: String, Codable, CaseIterable {
    case firstLog
    case streak3
    case streak7
    case proteinGoal
    case recipeCreator
}

struct Plate: Identifiable {
    let id = UUID()
    let weight: Double
    let color: Color
}

// MARK: - 2) SWIFTDATA MODELS (APP)

// --- User & Nutrition ---

@Model
final class UserProfile {
    var gender: Gender = .male
    var age: Int = 30
    var heightCm: Double = 175.0
    var activityLevel: ActivityLevel = .moderatelyActive
    var goalRatePerWeekKg: Double = -0.5
    
    var currentWeight: Double
    var caloricGoal: Int
    var proteinGoal: Int
    
    // Per-meal budget percentages (must sum to 1.0)
    var mealBudgetBreakfast: Double = 0.25
    var mealBudgetLunch: Double = 0.35
    var mealBudgetDinner: Double = 0.30
    var mealBudgetSnack: Double = 0.10
    
    init(currentWeight: Double = 70.0, caloricGoal: Int = 2500, proteinGoal: Int = 150) {
        self.currentWeight = currentWeight
        self.caloricGoal = caloricGoal
        self.proteinGoal = proteinGoal
    }
    
    func getBudgetPercentage(for meal: MealCategory) -> Double {
        switch meal {
        case .breakfast: return mealBudgetBreakfast
        case .lunch: return mealBudgetLunch
        case .dinner: return mealBudgetDinner
        case .snack: return mealBudgetSnack
        }
    }
}

@Model
final class WeightLog {
    var date: Date
    var weight: Double
    
    init(date: Date = Date(), weight: Double) {
        self.date = Calendar.current.startOfDay(for: date)
        self.weight = weight
    }
}

// Your “manual foods” database (kept for quick-add, custom foods, etc.)
@Model
final class FoodItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fats: Double
    var defaultServingSize: Double
    var barcode: String?
    
    init(name: String, calories: Int, protein: Double, carbs: Double, fats: Double, defaultServingSize: Double = 100, barcode: String? = nil) {
        self.id = UUID()
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.defaultServingSize = defaultServingSize
        self.barcode = barcode
    }
}

@Model
final class FoodLog {
    var timestamp: Date
    var foodName: String
    var servingSize: Double
    var calories: Int
    var protein: Double
    var carbs: Double
    var fats: Double
    var category: MealCategory
    var isFavorite: Bool = false
    var sourceType: String = "manual"  // "manual", "barcode", "generic"
    var sourceId: String?              // GenericFood.id or gtin14 for lookup
    
    init(timestamp: Date = Date(), foodName: String, servingSize: Double, calories: Int, protein: Double, carbs: Double, fats: Double, category: MealCategory, isFavorite: Bool = false, sourceType: String = "manual", sourceId: String? = nil) {
        self.timestamp = timestamp
        self.foodName = foodName
        self.servingSize = servingSize
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.category = category
        self.isFavorite = isFavorite
        self.sourceType = sourceType
        self.sourceId = sourceId
    }
}

@Model
final class MealTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var meal: MealCategory
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade)
    var items: [MealTemplateItem] = []
    
    init(id: UUID = UUID(), name: String, meal: MealCategory, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.meal = meal
        self.createdAt = createdAt
    }
    
    var totalCalories: Int { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { items.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double { items.reduce(0) { $0 + $1.carbs } }
    var totalFats: Double { items.reduce(0) { $0 + $1.fats } }
}

@Model
final class MealTemplateItem {
    var id: UUID
    var foodName: String
    var servingSize: Double
    var calories: Int
    var protein: Double
    var carbs: Double
    var fats: Double
    
    var template: MealTemplate?
    
    init(id: UUID = UUID(), foodName: String, servingSize: Double, calories: Int, protein: Double, carbs: Double, fats: Double, template: MealTemplate? = nil) {
        self.id = id
        self.foodName = foodName
        self.servingSize = servingSize
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.template = template
    }
}

@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var name: String
    var servings: Int
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade)
    var ingredients: [RecipeIngredient] = []
    
    init(id: UUID = UUID(), name: String, servings: Int = 1, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.servings = max(1, servings)
        self.createdAt = createdAt
    }
    
    private var safeServings: Double { Double(max(1, servings)) }
    
    var totalCalories: Int { ingredients.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { ingredients.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double { ingredients.reduce(0) { $0 + $1.carbs } }
    var totalFats: Double { ingredients.reduce(0) { $0 + $1.fats } }
    
    var caloriesPerServing: Int { Int((Double(totalCalories) / safeServings).rounded()) }
    var proteinPerServing: Double { totalProtein / safeServings }
    var carbsPerServing: Double { totalCarbs / safeServings }
    var fatsPerServing: Double { totalFats / safeServings }
}

@Model
final class RecipeIngredient {
    var id: UUID
    var name: String
    var amount: Double
    var calories: Int
    var protein: Double
    var carbs: Double
    var fats: Double
    
    var recipe: Recipe?
    
    init(id: UUID = UUID(), name: String, amount: Double, calories: Int, protein: Double, carbs: Double, fats: Double, recipe: Recipe? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.recipe = recipe
    }
}

@Model
final class AchievementBadge {
    @Attribute(.unique) var id: UUID
    var type: BadgeType
    var title: String
    var detail: String
    var icon: String
    var unlockedAt: Date
    
    init(id: UUID = UUID(), type: BadgeType, title: String, detail: String, icon: String, unlockedAt: Date = Date()) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.icon = icon
        self.unlockedAt = unlockedAt
    }
}

// --- Generic Ingredients (no brand) ---

@Model
final class GenericFood {
    @Attribute(.unique) var id: String
    var name: String
    var category: FoodCategory
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fibrePer100g: Double
    var typicalServingG: Double
    
    init(id: String, name: String, category: FoodCategory, kcalPer100g: Double, proteinPer100g: Double, carbsPer100g: Double, fatPer100g: Double, fibrePer100g: Double = 0, typicalServingG: Double = 100) {
        self.id = id
        self.name = name
        self.category = category
        self.kcalPer100g = kcalPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fibrePer100g = fibrePer100g
        self.typicalServingG = typicalServingG
    }
    
    /// Pre-populated generic foods with USDA-sourced nutritional data
    static let seedData: [GenericFood] = [
        // Proteins
        GenericFood(id: "chicken_breast_raw", name: "Chicken Breast (Raw)", category: .protein, kcalPer100g: 120, proteinPer100g: 22.5, carbsPer100g: 0, fatPer100g: 2.6, typicalServingG: 150),
        GenericFood(id: "chicken_breast_cooked", name: "Chicken Breast (Cooked)", category: .protein, kcalPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6, typicalServingG: 130),
        GenericFood(id: "chicken_thigh_cooked", name: "Chicken Thigh (Cooked)", category: .protein, kcalPer100g: 209, proteinPer100g: 26, carbsPer100g: 0, fatPer100g: 11, typicalServingG: 100),
        GenericFood(id: "beef_mince_5fat", name: "Beef Mince (5% Fat)", category: .protein, kcalPer100g: 137, proteinPer100g: 21, carbsPer100g: 0, fatPer100g: 5, typicalServingG: 150),
        GenericFood(id: "beef_steak", name: "Beef Sirloin Steak", category: .protein, kcalPer100g: 206, proteinPer100g: 26, carbsPer100g: 0, fatPer100g: 11, typicalServingG: 200),
        GenericFood(id: "salmon_fillet", name: "Salmon Fillet", category: .protein, kcalPer100g: 208, proteinPer100g: 20, carbsPer100g: 0, fatPer100g: 13, fibrePer100g: 0, typicalServingG: 125),
        GenericFood(id: "tuna_canned_water", name: "Tuna (Canned in Water)", category: .protein, kcalPer100g: 116, proteinPer100g: 26, carbsPer100g: 0, fatPer100g: 0.8, typicalServingG: 100),
        GenericFood(id: "whole_egg", name: "Whole Egg", category: .protein, kcalPer100g: 155, proteinPer100g: 13, carbsPer100g: 1.1, fatPer100g: 11, typicalServingG: 50),
        GenericFood(id: "egg_white", name: "Egg White Only", category: .protein, kcalPer100g: 52, proteinPer100g: 11, carbsPer100g: 0.7, fatPer100g: 0.2, typicalServingG: 33),
        
        // Carbs
        GenericFood(id: "white_rice_cooked", name: "White Rice (Cooked)", category: .carbs, kcalPer100g: 130, proteinPer100g: 2.7, carbsPer100g: 28, fatPer100g: 0.3, fibrePer100g: 0.4, typicalServingG: 150),
        GenericFood(id: "brown_rice_cooked", name: "Brown Rice (Cooked)", category: .carbs, kcalPer100g: 112, proteinPer100g: 2.6, carbsPer100g: 24, fatPer100g: 0.9, fibrePer100g: 1.8, typicalServingG: 150),
        GenericFood(id: "oats_dry", name: "Oats (Dry)", category: .carbs, kcalPer100g: 389, proteinPer100g: 17, carbsPer100g: 66, fatPer100g: 7, fibrePer100g: 10, typicalServingG: 40),
        GenericFood(id: "sweet_potato_baked", name: "Sweet Potato (Baked)", category: .carbs, kcalPer100g: 90, proteinPer100g: 2, carbsPer100g: 21, fatPer100g: 0.1, fibrePer100g: 3.3, typicalServingG: 130),
        GenericFood(id: "white_potato_baked", name: "White Potato (Baked)", category: .carbs, kcalPer100g: 93, proteinPer100g: 2.5, carbsPer100g: 21, fatPer100g: 0.1, fibrePer100g: 2.2, typicalServingG: 150),
        GenericFood(id: "pasta_cooked", name: "Pasta (Cooked)", category: .carbs, kcalPer100g: 131, proteinPer100g: 5, carbsPer100g: 25, fatPer100g: 1.1, fibrePer100g: 1.8, typicalServingG: 180),
        GenericFood(id: "bread_white", name: "White Bread", category: .carbs, kcalPer100g: 265, proteinPer100g: 9, carbsPer100g: 49, fatPer100g: 3.2, fibrePer100g: 2.7, typicalServingG: 30),
        GenericFood(id: "bread_wholemeal", name: "Wholemeal Bread", category: .carbs, kcalPer100g: 247, proteinPer100g: 13, carbsPer100g: 41, fatPer100g: 3.4, fibrePer100g: 7, typicalServingG: 30),
        
        // Fats
        GenericFood(id: "olive_oil", name: "Olive Oil", category: .fats, kcalPer100g: 884, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 100, typicalServingG: 15),
        GenericFood(id: "almonds", name: "Almonds", category: .fats, kcalPer100g: 579, proteinPer100g: 21, carbsPer100g: 22, fatPer100g: 50, fibrePer100g: 12, typicalServingG: 30),
        GenericFood(id: "peanut_butter", name: "Peanut Butter", category: .fats, kcalPer100g: 588, proteinPer100g: 25, carbsPer100g: 20, fatPer100g: 50, fibrePer100g: 6, typicalServingG: 32),
        GenericFood(id: "avocado", name: "Avocado", category: .fats, kcalPer100g: 160, proteinPer100g: 2, carbsPer100g: 9, fatPer100g: 15, fibrePer100g: 7, typicalServingG: 100),
        
        // Vegetables
        GenericFood(id: "broccoli_cooked", name: "Broccoli (Cooked)", category: .vegetables, kcalPer100g: 35, proteinPer100g: 2.4, carbsPer100g: 7, fatPer100g: 0.4, fibrePer100g: 3.3, typicalServingG: 80),
        GenericFood(id: "spinach_raw", name: "Spinach (Raw)", category: .vegetables, kcalPer100g: 23, proteinPer100g: 2.9, carbsPer100g: 3.6, fatPer100g: 0.4, fibrePer100g: 2.2, typicalServingG: 30),
        GenericFood(id: "mixed_salad", name: "Mixed Salad Leaves", category: .vegetables, kcalPer100g: 17, proteinPer100g: 1.5, carbsPer100g: 2.5, fatPer100g: 0.2, fibrePer100g: 1.8, typicalServingG: 50),
        
        // Dairy
        GenericFood(id: "greek_yogurt_0fat", name: "Greek Yogurt (0% Fat)", category: .dairy, kcalPer100g: 59, proteinPer100g: 10, carbsPer100g: 3.6, fatPer100g: 0.7, typicalServingG: 170),
        GenericFood(id: "greek_yogurt_full", name: "Greek Yogurt (Full Fat)", category: .dairy, kcalPer100g: 97, proteinPer100g: 9, carbsPer100g: 3.4, fatPer100g: 5, typicalServingG: 170),
        GenericFood(id: "cottage_cheese", name: "Cottage Cheese", category: .dairy, kcalPer100g: 98, proteinPer100g: 11, carbsPer100g: 3.4, fatPer100g: 4.3, typicalServingG: 150),
        GenericFood(id: "milk_semi", name: "Semi-Skimmed Milk", category: .dairy, kcalPer100g: 50, proteinPer100g: 3.4, carbsPer100g: 4.8, fatPer100g: 1.8, typicalServingG: 250),
        
        // Fruit
        GenericFood(id: "banana", name: "Banana", category: .fruit, kcalPer100g: 89, proteinPer100g: 1.1, carbsPer100g: 23, fatPer100g: 0.3, fibrePer100g: 2.6, typicalServingG: 120),
        GenericFood(id: "apple", name: "Apple", category: .fruit, kcalPer100g: 52, proteinPer100g: 0.3, carbsPer100g: 14, fatPer100g: 0.2, fibrePer100g: 2.4, typicalServingG: 180),
        GenericFood(id: "blueberries", name: "Blueberries", category: .fruit, kcalPer100g: 57, proteinPer100g: 0.7, carbsPer100g: 14, fatPer100g: 0.3, fibrePer100g: 2.4, typicalServingG: 80)
    ]
}

// --- Training ---

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var startTime: Date
    var endTime: Date?
    var title: String
    
    @Relationship(deleteRule: .cascade)
    var exercises: [WorkoutExercise] = []
    
    init(startTime: Date = Date(), title: String = "New Workout") {
        self.id = UUID()
        self.startTime = startTime
        self.title = title
    }
    
    var totalVolume: Double {
        exercises.reduce(0) { $0 + $1.volume }
    }
}

@Model
final class WorkoutExercise {
    var id: UUID
    var exerciseName: String
    var orderIndex: Int
    
    @Relationship(deleteRule: .cascade)
    var sets: [ExerciseSet] = []
    
    var workout: WorkoutSession?
    
    init(exerciseName: String, orderIndex: Int) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.orderIndex = orderIndex
    }
    
    var volume: Double {
        sets.filter { $0.isCompleted }.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }
}

@Model
final class ExerciseSet {
    var id: UUID
    var weight: Double
    var reps: Int
    var rpe: Int?
    var isCompleted: Bool
    var type: SetType
    var orderIndex: Int
    
    var exercise: WorkoutExercise?
    
    init(weight: Double, reps: Int, orderIndex: Int, type: SetType = .working) {
        self.id = UUID()
        self.weight = weight
        self.reps = reps
        self.isCompleted = false
        self.type = type
        self.orderIndex = orderIndex
    }
}

// MARK: - 3) FoodLoggingModule (Integrated)

// 3.1 GS1Barcode.swift

public struct NormalizedBarcode: Sendable {
    public let raw: String
    public let digits: String
    public let gtin14: String
    public let alternates: [String]
    public let isValidCheckDigit: Bool
}

public enum BarcodeNormalizationError: Error {
    case noDigits
    case unsupportedLength(Int)
}

public enum GS1Barcode {
    public static func normalize(_ raw: String) throws -> NormalizedBarcode {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { throw BarcodeNormalizationError.noDigits }
        
        let len = digits.count
        guard [8, 12, 13, 14].contains(len) else {
            throw BarcodeNormalizationError.unsupportedLength(len)
        }
        
        let isValid = validateGS1CheckDigit(digits)
        let gtin14 = digits.leftPad(to: 14, with: "0")
        
        var alternates: [String] = [gtin14]
        if len == 12 {
            let ean13As14 = ("0" + digits).leftPad(to: 14, with: "0")
            alternates.append(ean13As14)
        } else if len == 14 {
            alternates.append(digits)
        } else {
            alternates.append(gtin14)
        }
        
        alternates = Array(Set(alternates))
        
        return NormalizedBarcode(
            raw: raw,
            digits: digits,
            gtin14: gtin14,
            alternates: alternates,
            isValidCheckDigit: isValid
        )
    }
    
    public static func validateGS1CheckDigit(_ digits: String) -> Bool {
        guard digits.allSatisfy(\.isNumber), digits.count >= 2 else { return false }
        let body = digits.dropLast()
        let checkChar = digits.last!
        guard let expected = computeGS1CheckDigit(String(body)),
              let actual = Int(String(checkChar)) else { return false }
        return expected == actual
    }
    
    public static func computeGS1CheckDigit(_ bodyDigits: String) -> Int? {
        let ints = bodyDigits.compactMap { Int(String($0)) }
        guard ints.count == bodyDigits.count, !ints.isEmpty else { return nil }
        
        var sum = 0
        var positionFromRight = 1
        for d in ints.reversed() {
            let weight = (positionFromRight % 2 == 1) ? 3 : 1
            sum += d * weight
            positionFromRight += 1
        }
        
        let mod = sum % 10
        return (10 - mod) % 10
    }
}

private extension String {
    func leftPad(to length: Int, with char: Character) -> String {
        guard count < length else { return self }
        return String(repeating: String(char), count: length - count) + self
    }
}

// 3.2 FoodModels.swift

public struct FoodNutrients: Codable, Sendable, Equatable {
    public var kcalPer100g: Double?
    public var proteinPer100g: Double?
    public var carbsPer100g: Double?
    public var fatPer100g: Double?
    public var fibrePer100g: Double?
    
    public init(kcalPer100g: Double? = nil,
                proteinPer100g: Double? = nil,
                carbsPer100g: Double? = nil,
                fatPer100g: Double? = nil,
                fibrePer100g: Double? = nil) {
        self.kcalPer100g = kcalPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fibrePer100g = fibrePer100g
    }
}

@Model
public final class FoodProduct {
    @Attribute(.unique) public var gtin14: String
    
    public var name: String
    public var brand: String?
    public var imageURL: String?
    
    public var servingSizeG: Double?
    public var servingDescription: String?
    
    public var nutrientsBlob: Data?
    
    public var source: String?
    public var lastVerifiedAt: Date?
    
    public init(gtin14: String,
                name: String,
                brand: String? = nil,
                imageURL: String? = nil,
                servingSizeG: Double? = nil,
                servingDescription: String? = nil,
                nutrients: FoodNutrients? = nil,
                source: String? = nil,
                lastVerifiedAt: Date? = nil) {
        self.gtin14 = gtin14
        self.name = name
        self.brand = brand
        self.imageURL = imageURL
        self.servingSizeG = servingSizeG
        self.servingDescription = servingDescription
        self.source = source
        self.lastVerifiedAt = lastVerifiedAt
        self.nutrientsBlob = nutrients.flatMap { try? JSONEncoder().encode($0) }
    }
    
    public var nutrients: FoodNutrients? {
        get {
            guard let nutrientsBlob else { return nil }
            return try? JSONDecoder().decode(FoodNutrients.self, from: nutrientsBlob)
        }
        set {
            nutrientsBlob = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }
}

@Model
public final class UserFoodDefault {
    @Attribute(.unique) public var key: String
    
    public var userId: String
    public var gtin14: String
    
    public var defaultServingG: Double?
    public var defaultServingCount: Double?
    public var defaultMealSlot: String?
    public var lastUsedAt: Date?
    
    public init(userId: String, gtin14: String) {
        self.userId = userId
        self.gtin14 = gtin14
        self.key = "\(userId)|\(gtin14)"
    }
}

public struct FoodProductDTO: Codable, Sendable {
    public var gtin14: String
    public var name: String
    public var brand: String?
    public var imageURL: String?
    public var servingSizeG: Double?
    public var servingDescription: String?
    public var nutrients: FoodNutrients?
    public var source: String?
    public var lastVerifiedAt: Date?
    
    public func toModel() -> FoodProduct {
        FoodProduct(
            gtin14: gtin14,
            name: name,
            brand: brand,
            imageURL: imageURL,
            servingSizeG: servingSizeG,
            servingDescription: servingDescription,
            nutrients: nutrients,
            source: source,
            lastVerifiedAt: lastVerifiedAt
        )
    }
}

// 3.3 SwiftDataFoodCache.swift

public protocol FoodCache: Sendable {
    func getProduct(gtin14: String) async throws -> FoodProduct?
    func upsertProduct(_ product: FoodProduct) async throws
}

@MainActor
public final class SwiftDataFoodCache: FoodCache {
    private let context: ModelContext
    
    public init(context: ModelContext) {
        self.context = context
    }
    
    public func getProduct(gtin14: String) async throws -> FoodProduct? {
        let descriptor = FetchDescriptor<FoodProduct>(
            predicate: #Predicate { $0.gtin14 == gtin14 },
            sortBy: []
        )
        return try context.fetch(descriptor).first
    }
    
    public func upsertProduct(_ product: FoodProduct) async throws {
        if let existing = try await getProduct(gtin14: product.gtin14) {
            existing.name = product.name
            existing.brand = product.brand
            existing.imageURL = product.imageURL
            existing.servingSizeG = product.servingSizeG
            existing.servingDescription = product.servingDescription
            existing.nutrients = product.nutrients
            existing.source = product.source
            existing.lastVerifiedAt = product.lastVerifiedAt
        } else {
            context.insert(product)
        }
        try context.save()
    }
}

// 3.4 BackendClient.swift

public protocol FoodBackendClient: Sendable {
    func fetchByGTIN14(_ gtin14: String) async throws -> FoodProductDTO?
}

public struct HTTPFoodBackendClient: FoodBackendClient {
    public let baseURL: URL
    public let session: URLSession
    
    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    public func fetchByGTIN14(_ gtin14: String) async throws -> FoodProductDTO? {
        var url = baseURL
        url.append(path: "/v1/foods/gtin14/\(gtin14)")
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return nil }
        
        if http.statusCode == 404 { return nil }
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FoodProductDTO.self, from: data)
    }
}

// 3.5 FoodLookupService.swift

public enum FoodLookupSource: String, Sendable {
    case localCache
    case backend
}

public struct FoodLookupOutcome: Sendable {
    public let product: FoodProduct
    public let source: FoodLookupSource
    public let normalized: NormalizedBarcode
}

public enum FoodLookupError: Error {
    case normalizationFailed
    case notFound
}

public actor FoodLookupService {
    private let cache: FoodCache
    private let backend: FoodBackendClient
    
    public init(cache: FoodCache, backend: FoodBackendClient) {
        self.cache = cache
        self.backend = backend
    }
    
    public func lookup(rawBarcode: String) async throws -> FoodLookupOutcome {
        let normalized = try GS1Barcode.normalize(rawBarcode)
        
        for key in normalized.alternates {
            if let cached = try await cache.getProduct(gtin14: key) {
                return FoodLookupOutcome(product: cached, source: .localCache, normalized: normalized)
            }
        }
        
        for key in normalized.alternates {
            if let dto = try await backend.fetchByGTIN14(key) {
                let model = dto.toModel()
                try await cache.upsertProduct(model)
                return FoodLookupOutcome(product: model, source: .backend, normalized: normalized)
            }
        }
        
        throw FoodLookupError.notFound
    }
}

// 3.6 BarcodeScannerView.swift (VisionKit → SwiftUI; includes support checks + start/stop)

public struct BarcodeScannerView: UIViewControllerRepresentable {
    public typealias UIViewControllerType = UIViewController
    
    public var onBarcode: (String) -> Void
    public var onError: (Error) -> Void
    
    public init(onBarcode: @escaping (String) -> Void,
                onError: @escaping (Error) -> Void) {
        self.onBarcode = onBarcode
        self.onError = onError
    }
    
    public func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable else {
            return UnsupportedScannerViewController()
        }
        
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    
    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    public static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        if let vc = uiViewController as? DataScannerViewController {
            vc.stopScanning()
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(onBarcode: onBarcode, onError: onError)
    }
    
    public final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onBarcode: (String) -> Void
        private let onError: (Error) -> Void
        private var seen = Set<String>()
        
        init(onBarcode: @escaping (String) -> Void,
             onError: @escaping (Error) -> Void) {
            self.onBarcode = onBarcode
            self.onError = onError
        }
        
        public func dataScanner(_ dataScanner: DataScannerViewController,
                                didTapOn item: RecognizedItem) {
            handle(item)
        }
        
        public func dataScanner(_ dataScanner: DataScannerViewController,
                                didAdd addedItems: [RecognizedItem],
                                allItems: [RecognizedItem]) {
            for item in addedItems { handle(item) }
        }
        
        private func handle(_ item: RecognizedItem) {
            guard case let .barcode(barcode) = item,
                  let payload = barcode.payloadStringValue else { return }
            if seen.contains(payload) { return }
            seen.insert(payload)
            onBarcode(payload)
        }
        
        public func dataScanner(_ dataScanner: DataScannerViewController,
                                didFailWithError error: Error) {
            onError(error)
        }
    }
}

final class UnsupportedScannerViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        
        let label = UILabel()
        label.text = "Barcode scanning isn’t supported on this device."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

// 3.7 Voice Input Components

// MARK: - VoiceInputParser
struct VoiceInputParser {
    struct ParsedFoodEntry {
        let foodName: String
        let amount: Double
        let unit: String
        let mealCategory: MealCategory?
    }

    static func parse(_ text: String) -> ParsedFoodEntry? {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract meal category
        var mealCategory: MealCategory?
        var workingText = lowercased

        if lowercased.contains("breakfast") {
            mealCategory = .breakfast
            workingText = workingText.replacingOccurrences(of: "for breakfast", with: "")
                .replacingOccurrences(of: "breakfast", with: "")
        } else if lowercased.contains("lunch") {
            mealCategory = .lunch
            workingText = workingText.replacingOccurrences(of: "for lunch", with: "")
                .replacingOccurrences(of: "lunch", with: "")
        } else if lowercased.contains("dinner") {
            mealCategory = .dinner
            workingText = workingText.replacingOccurrences(of: "for dinner", with: "")
                .replacingOccurrences(of: "dinner", with: "")
        } else if lowercased.contains("snack") {
            mealCategory = .snack
            workingText = workingText.replacingOccurrences(of: "for snack", with: "")
                .replacingOccurrences(of: "snack", with: "")
        }

        // Clean up common words
        workingText = workingText.replacingOccurrences(of: "add ", with: "")
            .replacingOccurrences(of: "log ", with: "")
            .replacingOccurrences(of: "for ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern: "{amount}{unit} {food name}"
        // Examples: "200g chicken breast", "100 grams rice", "2 eggs"
        let pattern = #"(\d+\.?\d*)\s*(g|grams?|kg|kilograms?|ml|oz|ounces?|cups?|tbsp|tsp|pieces?)?\s+(.+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsRange = NSRange(workingText.startIndex..<workingText.endIndex, in: workingText)
        guard let match = regex.firstMatch(in: workingText, options: [], range: nsRange) else {
            return nil
        }

        // Extract components
        guard let amountRange = Range(match.range(at: 1), in: workingText),
              let foodRange = Range(match.range(at: 3), in: workingText) else {
            return nil
        }

        let amountStr = String(workingText[amountRange])
        guard let amount = Double(amountStr) else { return nil }

        var unit = "g"
        if match.range(at: 2).location != NSNotFound,
           let unitRange = Range(match.range(at: 2), in: workingText) {
            let extractedUnit = String(workingText[unitRange]).lowercased()
            unit = normalizeUnit(extractedUnit)
        }

        let foodName = String(workingText[foodRange]).trimmingCharacters(in: .whitespaces)

        return ParsedFoodEntry(
            foodName: foodName,
            amount: amount,
            unit: unit,
            mealCategory: mealCategory
        )
    }

    private static func normalizeUnit(_ unit: String) -> String {
        switch unit.lowercased() {
        case "g", "gram", "grams": return "g"
        case "kg", "kilogram", "kilograms": return "kg"
        case "ml", "milliliter", "milliliters": return "ml"
        case "oz", "ounce", "ounces": return "oz"
        case "cup", "cups": return "cups"
        case "tbsp", "tablespoon", "tablespoons": return "tbsp"
        case "tsp", "teaspoon", "teaspoons": return "tsp"
        case "piece", "pieces": return "pieces"
        default: return "g"
        }
    }
}

// MARK: - VoiceInputViewModel
@MainActor
final class VoiceInputViewModel: ObservableObject {
    enum State {
        case idle
        case requestingPermission
        case listening
        case processing
        case success(String)
        case error(String)
    }

    @Published var state: State = .idle
    @Published var recognizedText: String = ""

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func startRecording() {
        Task {
            await requestPermissions()
        }
    }

    private func requestPermissions() async {
        state = .requestingPermission

        // Request speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            state = .error("Speech recognition permission denied")
            return
        }

        // Request microphone permission
        let micStatus = await AVAudioSession.sharedInstance().requestRecordPermission()
        guard micStatus else {
            state = .error("Microphone permission denied")
            return
        }

        // Start recording
        do {
            try startRecognition()
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func startRecognition() throws {
        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "VoiceInput", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }

        recognitionRequest.shouldReportPartialResults = true

        // Get input node
        let inputNode = audioEngine.inputNode

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            var isFinal = false

            if let result = result {
                Task { @MainActor in
                    self.recognizedText = result.bestTranscription.formattedString
                }
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                Task { @MainActor in
                    self.stopRecording()
                    if error != nil {
                        self.state = .error("Recognition error")
                    } else {
                        self.state = .processing
                    }
                }
            }
        }

        // Configure audio tap
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        state = .listening
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        if state == .listening {
            state = .processing
        }
    }

    func reset() {
        state = .idle
        recognizedText = ""
    }
}

// MARK: - VoiceInputSheet
struct VoiceInputSheet: View {
    @StateObject private var viewModel = VoiceInputViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let selectedMealCategory: MealCategory
    let onFoodLogged: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                // Status icon
                Group {
                    switch viewModel.state {
                    case .idle:
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 100))
                            .foregroundColor(.gray)
                    case .requestingPermission:
                        ProgressView()
                            .scaleEffect(2)
                    case .listening:
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 100))
                            .foregroundColor(.red)
                            .symbolEffect(.pulse)
                    case .processing:
                        ProgressView()
                            .scaleEffect(2)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 100))
                            .foregroundColor(.green)
                    case .error:
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 100))
                            .foregroundColor(.red)
                    }
                }
                .padding()

                // Status text
                Group {
                    switch viewModel.state {
                    case .idle:
                        Text("Tap to start")
                            .font(.title2)
                    case .requestingPermission:
                        Text("Requesting permissions...")
                            .font(.title2)
                    case .listening:
                        Text("Listening...")
                            .font(.title2)
                            .foregroundColor(.red)
                    case .processing:
                        Text("Processing...")
                            .font(.title2)
                    case .success(let message):
                        Text(message)
                            .font(.title2)
                            .foregroundColor(.green)
                    case .error(let message):
                        Text(message)
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                }

                // Recognized text
                if !viewModel.recognizedText.isEmpty {
                    Text(viewModel.recognizedText)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                }

                Spacer()

                // Action button
                Group {
                    switch viewModel.state {
                    case .idle:
                        Button(action: {
                            viewModel.startRecording()
                        }) {
                            Text("Start Recording")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    case .listening:
                        Button(action: {
                            viewModel.stopRecording()
                        }) {
                            Text("Stop Recording")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    case .processing:
                        ProgressView()
                    case .success, .error:
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Done")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Voice Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.stopRecording()
                        dismiss()
                    }
                }
            }
            .onChange(of: viewModel.state) { oldState, newState in
                if case .processing = newState {
                    processVoiceInput()
                }
            }
        }
    }

    private func processVoiceInput() {
        guard let parsed = VoiceInputParser.parse(viewModel.recognizedText) else {
            viewModel.state = .error("Could not understand. Try saying: '200g chicken breast for lunch'")
            return
        }

        // Convert to grams if needed
        var servingSize = parsed.amount
        switch parsed.unit {
        case "kg": servingSize *= 1000
        case "ml": servingSize *= 1.0 // Assume 1ml = 1g for simplicity
        case "oz": servingSize *= 28.35
        case "cups": servingSize *= 240
        case "tbsp": servingSize *= 15
        case "tsp": servingSize *= 5
        default: break
        }

        // Use the meal category from voice input if provided, otherwise use selected
        let mealCategory = parsed.mealCategory ?? selectedMealCategory

        // Look up the food in generic foods first
        if let genericFood = GenericFood.seedData.first(where: {
            $0.name.lowercased().contains(parsed.foodName.lowercased()) ||
            parsed.foodName.lowercased().contains($0.name.lowercased())
        }) {
            // Log the food
            let factor = servingSize / 100.0
            let foodLog = FoodLog(
                timestamp: Date(),
                foodName: genericFood.name,
                servingSize: servingSize,
                calories: Int((genericFood.kcalPer100g * factor).rounded()),
                protein: genericFood.proteinPer100g * factor,
                carbs: genericFood.carbsPer100g * factor,
                fats: genericFood.fatPer100g * factor,
                category: mealCategory,
                isFavorite: false,
                sourceType: "voice",
                sourceId: genericFood.id
            )

            modelContext.insert(foodLog)
            try? modelContext.save()
            AchievementManager.shared.evaluateAfterPersistingLog(foodLog, context: modelContext)

            viewModel.state = .success("Added \(Int(servingSize))g \(genericFood.name) to \(mealCategory.rawValue)")
            onFoodLogged()

            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                dismiss()
            }
        } else {
            viewModel.state = .error("Food '\(parsed.foodName)' not found. Try scanning the barcode or adding manually.")
        }
    }
}

// 3.8 FoodScanViewModel.swift

@MainActor
public final class FoodScanViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case scanning
        case lookingUp
        case found(name: String, brand: String?)
        case notFound
        case error(message: String)
    }
    
    @Published public private(set) var state: State = .idle
    @Published public private(set) var lastOutcome: FoodLookupOutcome?
    
    private let lookupService: FoodLookupService
    
    public init(lookupService: FoodLookupService) {
        self.lookupService = lookupService
    }
    
    public func handleScannedBarcode(_ code: String) {
        if case .lookingUp = state { return } // ignore extra scans while looking up
        state = .lookingUp
        
        Task {
            do {
                let outcome = try await lookupService.lookup(rawBarcode: code)
                self.lastOutcome = outcome
                self.state = .found(name: outcome.product.name, brand: outcome.product.brand)
            } catch FoodLookupError.notFound {
                self.state = .notFound
            } catch {
                self.state = .error(message: error.localizedDescription)
            }
        }
    }
    
    public func reset() {
        lastOutcome = nil
        state = .idle
    }
}

// MARK: - 4) Managers (App Logic)

@Observable
class TrainingManager {
    static let shared = TrainingManager()
    private init() {}
    
    func calculatePlates(targetWeight: Double, barWeight: Double = 45.0) -> [Plate] {
        let oneSideWeight = (targetWeight - barWeight) / 2.0
        if oneSideWeight <= 0 { return [] }
        
        let availablePlates: [(Double, Color)] = [
            (45.0, .blue), (35.0, .yellow), (25.0, .green),
            (10.0, .white), (5.0, .red), (2.5, .black)
        ]
        
        var remaining = oneSideWeight
        var result: [Plate] = []
        
        for (weight, color) in availablePlates {
            while remaining >= weight {
                result.append(Plate(weight: weight, color: color))
                remaining -= weight
            }
        }
        return result
    }
    
    func calculateEstimated1RM(weight: Double, reps: Int) -> Double {
        if reps == 1 { return weight }
        if reps == 0 { return 0 }
        return weight * (1 + Double(reps) / 30.0)
    }
    
    @MainActor
    func getGhostSets(for exerciseName: String, context: ModelContext) -> [ExerciseSet] {
        let descriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate { $0.exerciseName == exerciseName },
            sortBy: [SortDescriptor(\.workout?.startTime, order: .reverse)]
        )
        do {
            let results = try context.fetch(descriptor)
            if let lastSession = results.first {
                return lastSession.sets
                    .sorted(by: { $0.orderIndex < $1.orderIndex })
                    .map { oldSet in
                        ExerciseSet(weight: oldSet.weight, reps: oldSet.reps, orderIndex: oldSet.orderIndex, type: oldSet.type)
                    }
            }
        } catch {
            print("Error fetching ghost sets: \(error)")
        }
        return [ExerciseSet(weight: 45, reps: 10, orderIndex: 0)]
    }
}

@Observable
class NutritionManager {
    static let shared = NutritionManager()
    private init() {}
    
    private func calculateBMR(profile: UserProfile) -> Double {
        let weight = profile.currentWeight
        let height = profile.heightCm
        let age = profile.age
        
        if profile.gender == .male {
            return (10 * weight) + (6.25 * height) - (5 * Double(age)) + 5
        } else {
            return (10 * weight) + (6.25 * height) - (5 * Double(age)) - 161
        }
    }
    
    func calculateTDEE(profile: UserProfile) -> Int {
        let bmr = calculateBMR(profile: profile)
        let tdee = bmr * profile.activityLevel.rawValue
        return Int(tdee.rounded())
    }
    
    @MainActor
    func applyMealBudgets(profile: UserProfile, breakfast: Double, lunch: Double, dinner: Double, snack: Double) {
        let total = max(0.01, breakfast + lunch + dinner + snack)
        profile.mealBudgetBreakfast = breakfast / total
        profile.mealBudgetLunch = lunch / total
        profile.mealBudgetDinner = dinner / total
        profile.mealBudgetSnack = snack / total
    }
    
    func currentBudgets(for profile: UserProfile) -> (breakfast: Double, lunch: Double, dinner: Double, snack: Double) {
        (
            breakfast: profile.mealBudgetBreakfast,
            lunch: profile.mealBudgetLunch,
            dinner: profile.mealBudgetDinner,
            snack: profile.mealBudgetSnack
        )
    }
    
    @MainActor
    func calculateCaloricTarget(profile: UserProfile) -> Int {
        let tdee = Double(calculateTDEE(profile: profile))
        let kcalPerKg = 7700.0
        let dailyAdjustment = (profile.goalRatePerWeekKg * kcalPerKg) / 7.0
        let target = tdee + dailyAdjustment
        return Int(max(1200.0, target).rounded())
    }
    
    func calculateTrendWeight(logs: [WeightLog]) -> Double? {
        let sorted = logs.sorted { $0.date > $1.date }
        guard !sorted.isEmpty else { return nil }
        guard sorted.count >= 7 else { return sorted.first?.weight }
        
        let last7 = Array(sorted.prefix(7))
        let sum = last7.reduce(0.0) { $0 + $1.weight }
        return sum / Double(last7.count)
    }
    
    @MainActor
    func getDailySummary(for date: Date, context: ModelContext) -> (kcal: Int, protein: Double, carbs: Double, fats: Double)? {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        
        let predicate = #Predicate<FoodLog> { log in
            log.timestamp >= start && log.timestamp < end
        }
        
        let descriptor = FetchDescriptor<FoodLog>(predicate: predicate)
        
        do {
            let logs = try context.fetch(descriptor)
            guard !logs.isEmpty else { return nil }
            
            let totalKcal = logs.reduce(0) { $0 + $1.calories }
            let totalProtein = logs.reduce(0.0) { $0 + $1.protein }
            let totalCarbs = logs.reduce(0.0) { $0 + $1.carbs }
            let totalFats = logs.reduce(0.0) { $0 + $1.fats }
            
            return (totalKcal, totalProtein, totalCarbs, totalFats)
        } catch {
            print("Error fetching daily food logs: \(error)")
            return nil
        }
    }
    
    /// Calculate target macros for a specific meal
    @MainActor
    func getMealTarget(meal: MealCategory, profile: UserProfile) -> (kcal: Int, protein: Double, carbs: Double) {
        let dailyKcal = calculateCaloricTarget(profile: profile)
        let dailyProtein = Double(profile.proteinGoal)
        let percentage = profile.getBudgetPercentage(for: meal)
        
        // Estimate carbs from remaining calories (after protein/fat allocation)
        let proteinCals = dailyProtein * 4.0
        let estimatedFatCals = Double(dailyKcal) * 0.25  // ~25% from fat
        let carbCals = Double(dailyKcal) - proteinCals - estimatedFatCals
        let dailyCarbs = max(0, carbCals / 4.0)
        
        return (
            Int(Double(dailyKcal) * percentage),
            dailyProtein * percentage,
            dailyCarbs * percentage
        )
    }
    
    /// Get macros logged for a specific meal on a date
    @MainActor
    func getMealSummary(for date: Date, meal: MealCategory, context: ModelContext) -> (kcal: Int, protein: Double, carbs: Double, fats: Double) {
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            return (0, 0, 0, 0)
        }
        
        let predicate = #Predicate<FoodLog> { log in
            log.timestamp >= start && log.timestamp < end
        }
        
        let descriptor = FetchDescriptor<FoodLog>(predicate: predicate)
        
        do {
            let logs = try context.fetch(descriptor)
            let mealLogs = logs.filter { $0.category == meal }
            
            let totalKcal = mealLogs.reduce(0) { $0 + $1.calories }
            let totalProtein = mealLogs.reduce(0.0) { $0 + $1.protein }
            let totalCarbs = mealLogs.reduce(0.0) { $0 + $1.carbs }
            let totalFats = mealLogs.reduce(0.0) { $0 + $1.fats }
            
            return (totalKcal, totalProtein, totalCarbs, totalFats)
        } catch {
            print("Error fetching meal logs: \(error)")
            return (0, 0, 0, 0)
        }
    }
    
    /// Get remaining macros for the entire day
    @MainActor
    func getRemainingMacros(for date: Date, profile: UserProfile, context: ModelContext) -> (kcal: Int, protein: Double, carbs: Double) {
        let target = (
            kcal: calculateCaloricTarget(profile: profile),
            protein: Double(profile.proteinGoal),
            carbs: Double(profile.proteinGoal) * 2  // rough estimate
        )
        
        let consumed = getDailySummary(for: date, context: context) ?? (0, 0, 0, 0)
        
        return (
            max(0, target.kcal - consumed.kcal),
            max(0, target.protein - consumed.protein),
            max(0, target.carbs - consumed.carbs)
        )
    }
}

@Observable
class AchievementManager {
    static let shared = AchievementManager()
    private init() {}
    
    private let badgeCatalog: [BadgeType: (title: String, detail: String, icon: String)] = [
        .firstLog: ("First Log", "Logged your first meal", "1.circle.fill"),
        .streak3: ("3-Day Streak", "Logged meals three days in a row", "flame.fill"),
        .streak7: ("7-Day Streak", "An entire week of consistency", "flame.circle.fill"),
        .proteinGoal: ("Protein Hit", "Met your daily protein goal", "bolt.heart.fill"),
        .recipeCreator: ("Recipe Creator", "Built your first recipe", "fork.knife")
    ]
    
    @MainActor
    func earnedBadges(context: ModelContext) -> [AchievementBadge] {
        let descriptor = FetchDescriptor<AchievementBadge>(sortBy: [SortDescriptor(\.unlockedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }
    
    @MainActor
    func award(_ type: BadgeType, context: ModelContext) {
        guard badgeCatalog[type] != nil else { return }
        if hasBadge(type, context: context) { return }
        let meta = badgeCatalog[type]!
        let badge = AchievementBadge(type: type, title: meta.title, detail: meta.detail, icon: meta.icon)
        context.insert(badge)
        try? context.save()
    }
    
    @MainActor
    func hasBadge(_ type: BadgeType, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<AchievementBadge>(predicate: #Predicate { $0.type == type })
        let count = (try? context.fetch(descriptor).count) ?? 0
        return count > 0
    }
    
    @MainActor
    func evaluateAfterLogging(on date: Date, context: ModelContext, profile: UserProfile?) {
        let totalLogs = (try? context.fetch(FetchDescriptor<FoodLog>()).count) ?? 0
        if totalLogs == 1 {
            award(.firstLog, context: context)
        }
        
        let streak = currentStreak(context: context)
        if streak >= 3 { award(.streak3, context: context) }
        if streak >= 7 { award(.streak7, context: context) }
        
        if let profile = profile {
            let summary = NutritionManager.shared.getDailySummary(for: date, context: context)
            if let summary, summary.protein >= Double(profile.proteinGoal) {
                award(.proteinGoal, context: context)
            }
        }
    }
    
    @MainActor
    func evaluateAfterPersistingLog(_ log: FoodLog, context: ModelContext) {
        let descriptor = FetchDescriptor<UserProfile>()
        let profile = try? context.fetch(descriptor).first
        evaluateAfterLogging(on: log.timestamp, context: context, profile: profile ?? nil)
    }
    
    @MainActor
    func evaluateAfterRecipeCreated(context: ModelContext) {
        award(.recipeCreator, context: context)
    }
    
    private func currentStreak(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<FoodLog>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        guard let logs = try? context.fetch(descriptor), !logs.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let uniqueDays = Array(Set(logs.map { calendar.startOfDay(for: $0.timestamp) })).sorted(by: >)
        
        var streak = 0
        var cursor = calendar.startOfDay(for: Date())
        
        for day in uniqueDays {
            if day == cursor {
                streak += 1
                if let previous = calendar.date(byAdding: .day, value: -1, to: cursor) {
                    cursor = previous
                }
            } else if day < cursor {
                break
            }
        }
        
        return streak
    }
}

// MARK: - 5) Camera Permission Helper (for scan UX)

@MainActor
final class CameraPermission: ObservableObject {
    @Published var authorised: Bool = false
    @Published var denied: Bool = false
    
    func refresh() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorised = (status == .authorized)
        denied = (status == .denied || status == .restricted)
    }
    
    func request() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            refresh()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorised = granted
            denied = !granted
        case .denied, .restricted:
            refresh()
        @unknown default:
            refresh()
        }
    }
}

// MARK: - 6) App Root

struct ContentView: View {
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "house.fill") }
                .tag(0)
            
            Text("Workout (next)") // training UI can be added later
                .tabItem { Label("Workout", systemImage: "figure.strengthtraining.functional") }
                .tag(1)
            
            FoodLogView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife.circle.fill") }
                .tag(2)
        }
    }
}

// MARK: - 7) Dashboard Views

struct DailySummaryCard: View {
    @Bindable var profile: UserProfile
    var summary: (kcal: Int, protein: Double, carbs: Double, fats: Double)?
    
    var caloricTarget: Int { NutritionManager.shared.calculateCaloricTarget(profile: profile) }
    
    var body: some View {
        let remaining = max(0, caloricTarget - (summary?.kcal ?? 0))
        let proteinRemaining = max(0, profile.proteinGoal - Int(summary?.protein ?? 0))
        
        VStack(alignment: .leading, spacing: 10) {
            Text("Nutrition Goal: \(caloricTarget) kcal")
                .font(.headline)
            
            HStack {
                VStack {
                    Text("\(remaining)")
                        .font(.largeTitle).bold()
                        .foregroundColor(remaining < caloricTarget / 5 ? .red : .green)
                    Text("Calories Left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack {
                    Text("\(proteinRemaining)g")
                        .font(.largeTitle).bold()
                        .foregroundColor(proteinRemaining <= 0 ? .green : .orange)
                    Text("Protein Left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            
            Divider()
            
            VStack(spacing: 5) {
                MacroProgressView(label: "Protein", current: summary?.protein ?? 0, goal: Double(profile.proteinGoal))
                let fatCals = (summary?.fats ?? 0) * 9
                let proteinCals = Double(profile.proteinGoal) * 4
                let remainingForCarbs = max(0.0, Double(caloricTarget) - proteinCals - fatCals)
                MacroProgressView(label: "Carbs", current: summary?.carbs ?? 0, goal: remainingForCarbs / 4.0)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

struct MacroProgressView: View {
    let label: String
    let current: Double
    let goal: Double
    
    var progress: Double { goal > 0 ? min(current / goal, 1.0) : 0 }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 60, alignment: .leading)
            ProgressView(value: progress)
            Text("\(Int(current))/\(Int(goal))g")
                .font(.caption)
                .frame(width: 85, alignment: .trailing)
        }
    }
}

// MARK: - Remaining Macros UI Components

/// Floating bar showing remaining daily macros
struct RemainingMacrosBar: View {
    let remainingKcal: Int
    let remainingProtein: Double
    let remainingCarbs: Double
    let targetKcal: Int
    
    private var kcalPercentUsed: Double {
        guard targetKcal > 0 else { return 0 }
        return 1.0 - (Double(remainingKcal) / Double(targetKcal))
    }
    
    private var statusColor: Color {
        if kcalPercentUsed > 1.0 { return .red }
        if kcalPercentUsed > 0.8 { return .orange }
        return .green
    }
    
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(statusColor)
                Text("\(remainingKcal)")
                    .font(.headline).bold()
                Text("kcal")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider().frame(height: 20)
            
            HStack(spacing: 4) {
                Text("🥩")
                Text("\(Int(remainingProtein))g")
                    .font(.headline).bold()
                Text("protein")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider().frame(height: 20)
            
            HStack(spacing: 4) {
                Text("🍚")
                Text("\(Int(remainingCarbs))g")
                    .font(.headline).bold()
                Text("carbs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 3)
    }
}

/// Card showing remaining macros for a specific meal
struct MealBudgetCard: View {
    let meal: MealCategory
    let consumed: (kcal: Int, protein: Double, carbs: Double, fats: Double)
    let target: (kcal: Int, protein: Double, carbs: Double)
    
    private var percentUsed: Double {
        guard target.kcal > 0 else { return 0 }
        return Double(consumed.kcal) / Double(target.kcal)
    }
    
    private var statusColor: Color {
        if percentUsed > 1.0 { return .red }
        if percentUsed > 0.8 { return .orange }
        return .green
    }
    
    private var remainingKcal: Int { max(0, target.kcal - consumed.kcal) }
    private var remainingProtein: Double { max(0, target.protein - consumed.protein) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(meal.rawValue.capitalized) Budget")
                    .font(.subheadline).bold()
                Spacer()
                Text("\(Int(percentUsed * 100))% used")
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            
            ProgressView(value: min(percentUsed, 1.0))
                .tint(statusColor)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("\(remainingKcal) kcal left")
                        .font(.caption)
                    Text("\(Int(remainingProtein))g protein left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if remainingKcal > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Generic Foods Sheet

struct GenericFoodsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let selectedMealCategory: MealCategory
    let onLogged: () -> Void
    
    @State private var searchText = ""
    @State private var selectedCategory: FoodCategory? = nil
    @State private var selectedFood: GenericFood? = nil
    
    private var filteredFoods: [GenericFood] {
        var foods = GenericFood.seedData
        if let category = selectedCategory {
            foods = foods.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            foods = foods.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return foods.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryPill(title: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(FoodCategory.allCases, id: \.self) { cat in
                            CategoryPill(title: cat.rawValue, isSelected: selectedCategory == cat) {
                                selectedCategory = cat
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                List(filteredFoods, id: \.id) { food in
                    Button {
                        selectedFood = food
                    } label: {
                        GenericFoodRow(food: food)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search ingredients...")
            .navigationTitle("Generic Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $selectedFood) { food in
                GenericFoodLogSheet(food: food, category: selectedMealCategory) { entry in
                    modelContext.insert(entry)
                    try? modelContext.save()
                    AchievementManager.shared.evaluateAfterPersistingLog(entry, context: modelContext)
                    onLogged()
                    dismiss()
                }
            }
        }
    }
}

struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

struct GenericFoodRow: View {
    let food: GenericFood
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(food.name).font(.headline).foregroundColor(.primary)
            HStack {
                Text("\(Int(food.kcalPer100g)) kcal")
                Text("P:\(Int(food.proteinPer100g)) C:\(Int(food.carbsPer100g)) F:\(Int(food.fatPer100g))")
            }
            .font(.caption).foregroundColor(.secondary)
        }
    }
}

struct GenericFoodLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let food: GenericFood
    let category: MealCategory
    let onLog: (FoodLog) -> Void
    
    @State private var servingSize: Double
    
    init(food: GenericFood, category: MealCategory, onLog: @escaping (FoodLog) -> Void) {
        self.food = food
        self.category = category
        self.onLog = onLog
        _servingSize = State(initialValue: food.typicalServingG)
    }
    
    private var factor: Double { servingSize / 100.0 }
    private var kcal: Int { Int((food.kcalPer100g * factor).rounded()) }
    private var protein: Double { food.proteinPer100g * factor }
    private var carbs: Double { food.carbsPer100g * factor }
    private var fats: Double { food.fatPer100g * factor }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Serving") {
                    Text("\(Int(servingSize))g").font(.title).bold()
                    Slider(value: $servingSize, in: 10...500, step: 5)
                    HStack {
                        ForEach([50, 100, Int(food.typicalServingG), 200], id: \.self) { g in
                            Button("\(g)g") { servingSize = Double(g) }.buttonStyle(.bordered)
                        }
                    }
                }
                Section("Macros") {
                    HStack {
                        VStack { Text("\(kcal)").bold(); Text("kcal").font(.caption) }
                        Spacer()
                        VStack { Text(String(format: "%.0f", protein)).bold(); Text("P").font(.caption) }
                        Spacer()
                        VStack { Text(String(format: "%.0f", carbs)).bold(); Text("C").font(.caption) }
                        Spacer()
                        VStack { Text(String(format: "%.0f", fats)).bold(); Text("F").font(.caption) }
                    }
                }
            }
            .navigationTitle(food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onLog(FoodLog(foodName: food.name, servingSize: servingSize, calories: kcal, protein: protein, carbs: carbs, fats: fats, category: category, sourceType: "generic", sourceId: food.id))
                        dismiss()
                    }.bold()
                }
            }
        }
    }
}

struct WeightTrackingCard: View {
    let currentWeight: Double
    let trendWeight: Double?
    
    var weightChange: Double? {
        guard let trend = trendWeight else { return nil }
        return currentWeight - trend
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Weight Today")
                .font(.headline)
            
            HStack(spacing: 15) {
                VStack(alignment: .leading) {
                    Text("\(currentWeight, specifier: "%.1f") kg")
                        .font(.largeTitle)
                        .bold()
                    Text("Last Weigh-in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let trend = trendWeight {
                    VStack(alignment: .leading) {
                        Text("\(trend, specifier: "%.1f") kg")
                            .font(.title2)
                            .foregroundColor(.purple)
                        Text("7-Day Trend")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let change = weightChange {
                    VStack {
                        Image(systemName: change > 0.05 ? "arrow.up.right" : (change < -0.05 ? "arrow.down.right" : "equal"))
                            .foregroundColor(change > 0.05 ? .red : (change < -0.05 ? .green : .gray))
                        Text("\(abs(change), specifier: "%.1f") kg")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

struct WeightTrendChart: View {
    var weightLogs: [WeightLog]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Weight Progress")
                .font(.headline)
                .padding(.leading)
            
            Chart {
                ForEach(weightLogs.sorted(by: { $0.date < $1.date }), id: \.date) { log in
                    LineMark(
                        x: .value("Date", log.date),
                        y: .value("Weight", log.weight)
                    )
                    .symbol(.circle)
                }
            }
            .chartYAxisLabel("Weight (kg)")
            .chartXAxis(.hidden)
            .padding(.top, 10)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var profile: UserProfile?
    
    @Query(sort: \WeightLog.date, order: .reverse) private var weightLogs: [WeightLog]
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var workouts: [WorkoutSession]
    
    private let nutritionManager = NutritionManager.shared
    private let today = Date()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let profile = profile {
                        DailySummaryCard(profile: profile, summary: nutritionManager.getDailySummary(for: today, context: modelContext))
                        
                        WeightTrackingCard(
                            currentWeight: profile.currentWeight,
                            trendWeight: nutritionManager.calculateTrendWeight(logs: weightLogs)
                        )
                    } else {
                        Text("Setting up User Profile…")
                    }
                    
                    WeightTrendChart(weightLogs: weightLogs)
                        .frame(height: 220)
                        .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Today’s Fuel ⚡️")
        }
        .onAppear {
            fetchUserProfile()
        }
    }
    
    private func fetchUserProfile() {
        do {
            let descriptor = FetchDescriptor<UserProfile>()
            if let existing = try modelContext.fetch(descriptor).first {
                self.profile = existing
            } else {
                let newProfile = UserProfile()
                modelContext.insert(newProfile)
                self.profile = newProfile
            }
        } catch {
            print("Error fetching or creating profile: \(error)")
        }
    }
}

// MARK: - 8) Food Scan Sheet (module wired into app)

struct FoodScanSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let selectedMealCategory: MealCategory
    let onLogged: () -> Void
    
    @StateObject private var vm: FoodScanViewModel
    
    // Backend API URL
    // Development: Use localhost (requires backend running on same machine or network)
    // Production: Replace with your deployed server URL (e.g., "https://api.ironfuel.com")
    private let backendBaseURL = URL(string: "http://localhost:8000")!
    
    init(selectedMealCategory: MealCategory, onLogged: @escaping () -> Void) {
        self.selectedMealCategory = selectedMealCategory
        self.onLogged = onLogged
        
        // placeholder; replaced in onAppear
        let dummyService = FoodLookupService(cache: DummyCache(), backend: DummyBackend())
        _vm = StateObject(wrappedValue: FoodScanViewModel(lookupService: dummyService))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                
                BarcodeScannerView(
                    onBarcode: { code in vm.handleScannedBarcode(code) },
                    onError: { err in vm.reset(); print("Scanner error: \(err)") }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
                
                switch vm.state {
                case .lookingUp:
                    ProgressView("Looking up…")
                        .padding(.bottom)
                    
                case .found(let name, let brand):
                    VStack(spacing: 6) {
                        Text("Found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(name)\(brand.map { " (\($0))" } ?? "")")
                            .font(.title3)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom)
                    
                    Button {
                        guard let product = vm.lastOutcome?.product else { return }
                        log(product: product)
                    } label: {
                        Label("Log this food", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                case .notFound:
                    VStack(spacing: 8) {
                        Text("Not found")
                            .font(.headline)
                        Text("This barcode isn’t in your cache or backend yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Add it manually for now.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom)
                    
                case .error(let message):
                    Text(message)
                        .foregroundColor(.red)
                        .padding(.bottom)
                    
                default:
                    EmptyView()
                }
                
                Spacer()
            }
            .navigationTitle("Scan Barcode")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                let cache = SwiftDataFoodCache(context: modelContext)
                let backend = HTTPFoodBackendClient(baseURL: backendBaseURL)
                let service = FoodLookupService(cache: cache, backend: backend)
                _vm.wrappedValue = FoodScanViewModel(lookupService: service)
            }
        }
    }
    
    private var title: String {
        switch vm.state {
        case .idle, .scanning: return "Scan a barcode"
        case .lookingUp: return "Looking up…"
        case .found: return "Product found"
        case .notFound: return "Barcode not found"
        case .error: return "Error"
        }
    }
    
    private func log(product: FoodProduct) {
        let servingG = product.servingSizeG ?? 100
        let n = product.nutrients ?? FoodNutrients()
        
        let kcalPer100 = n.kcalPer100g ?? 0
        let pPer100 = n.proteinPer100g ?? 0
        let cPer100 = n.carbsPer100g ?? 0
        let fPer100 = n.fatPer100g ?? 0
        
        let factor = servingG / 100.0
        
        let entry = FoodLog(
            timestamp: Date(),
            foodName: product.name,
            servingSize: servingG,
            calories: Int((kcalPer100 * factor).rounded()),
            protein: pPer100 * factor,
            carbs: cPer100 * factor,
            fats: fPer100 * factor,
            category: selectedMealCategory
        )
        
        modelContext.insert(entry)
        try? modelContext.save()
        AchievementManager.shared.evaluateAfterPersistingLog(entry, context: modelContext)
        
        onLogged()
        dismiss()
    }
}

// Dummy placeholders only used while initialising vm before modelContext exists
private struct DummyBackend: FoodBackendClient {
    func fetchByGTIN14(_ gtin14: String) async throws -> FoodProductDTO? { nil }
}
@MainActor private final class DummyCache: FoodCache {
    func getProduct(gtin14: String) async throws -> FoodProduct? { nil }
    func upsertProduct(_ product: FoodProduct) async throws {}
}

// MARK: - 9) Food Diary UI (FoodLogView) – now uses FoodScanSheet

struct FoodLogView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Phase 4: multi-day diary
    @State private var selectedDate: Date = Date()
    
    // Scan UX
    @StateObject private var cameraPermission = CameraPermission()
    @State private var showingScanSheet = false
    @State private var showCameraDeniedAlert = false
    @State private var showGenericFoodsSheet = false
    @State private var showVoiceInputSheet = false
    
    @State private var selectedMealCategory: MealCategory = .breakfast
    @State private var searchFoodText: String = ""
    @State private var showLogFoodSheet: Bool = false
    @State private var selectedFoodForLogging: FoodItem?
    @State private var profile: UserProfile?
    @State private var showBudgetEditor = false
    @State private var showTemplateBuilder = false
    @State private var showRecipeBuilder = false
    @State private var showBadges = false
    
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var foodLogs: [FoodLog]
    @Query(sort: \MealTemplate.createdAt, order: .reverse) private var mealTemplates: [MealTemplate]
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \AchievementBadge.unlockedAt, order: .reverse) private var badges: [AchievementBadge]
    
    private let nutritionManager = NutritionManager.shared
    
    var filteredFoodLogs: [FoodLog] {
        foodLogs.filter { log in
            Calendar.current.isDate(log.timestamp, inSameDayAs: selectedDate) &&
            (searchFoodText.isEmpty || log.foodName.localizedCaseInsensitiveContains(searchFoodText)) &&
            (log.category == selectedMealCategory)
        }
    }
    
    // Computed remaining macros for the day
    private var remainingMacros: (kcal: Int, protein: Double, carbs: Double) {
        guard let profile = profile else { return (0, 0, 0) }
        return nutritionManager.getRemainingMacros(for: selectedDate, profile: profile, context: modelContext)
    }
    
    // Computed target/consumed for selected meal
    private var mealTarget: (kcal: Int, protein: Double, carbs: Double) {
        guard let profile = profile else { return (0, 0, 0) }
        return nutritionManager.getMealTarget(meal: selectedMealCategory, profile: profile)
    }
    
    private var mealConsumed: (kcal: Int, protein: Double, carbs: Double, fats: Double) {
        nutritionManager.getMealSummary(for: selectedDate, meal: selectedMealCategory, context: modelContext)
    }
    
    // Favorite foods for quick re-logging
    private var favoriteFoods: [FoodLog] {
        foodLogs.filter { $0.isFavorite }
            .reduce(into: [String: FoodLog]()) { dict, log in
                if dict[log.foodName] == nil { dict[log.foodName] = log }
            }
            .values.sorted { $0.foodName < $1.foodName }
    }
    
    private var recentFoods: [FoodLog] {
        var seen: Set<String> = []
        var results: [FoodLog] = []
        
        for log in foodLogs where log.category == selectedMealCategory {
            if !seen.contains(log.foodName) {
                seen.insert(log.foodName)
                results.append(log)
            }
            if results.count >= 6 { break }
        }
        return results
    }
    
    private var templatesForMeal: [MealTemplate] {
        mealTemplates.filter { $0.meal == selectedMealCategory }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // Remaining macros floating bar
                if profile != nil {
                    RemainingMacrosBar(
                        remainingKcal: remainingMacros.kcal,
                        remainingProtein: remainingMacros.protein,
                        remainingCarbs: remainingMacros.carbs,
                        targetKcal: nutritionManager.calculateCaloricTarget(profile: profile!)
                    )
                    .padding(.horizontal)
                }
                
                DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .padding(.horizontal)
                
                // Meal budget card for selected meal
                if profile != nil {
                    MealBudgetCard(
                        meal: selectedMealCategory,
                        consumed: mealConsumed,
                        target: mealTarget
                    )
                        .padding(.horizontal)
                    
                    Button {
                        showBudgetEditor = true
                    } label: {
                        Label("Adjust meal budgets", systemImage: "slider.horizontal.3")
                            .font(.caption)
                    }
                    .padding(.horizontal)
                }
                
                if !badges.isEmpty {
                    BadgeRibbon(badges: Array(badges.prefix(5)))
                        .padding(.horizontal)
                        .onTapGesture { showBadges = true }
                }
                
                Button(action: {
                    Task {
                        cameraPermission.refresh()
                        if !cameraPermission.authorised {
                            await cameraPermission.request()
                        }
                        if cameraPermission.authorised {
                            showingScanSheet = true
                        } else {
                            showCameraDeniedAlert = true
                        }
                    }
                }) {
                    Label("Barcode Scan", systemImage: "barcode.viewfinder")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .alert("Camera permission needed", isPresented: $showCameraDeniedAlert) {
                    Button("OK", role: .cancel) {}
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } message: {
                    Text("Enable camera access in Settings to scan barcodes.")
                }

                Button(action: {
                    showVoiceInputSheet = true
                }) {
                    Label("Voice Input", systemImage: "mic.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                TextField("Search foods…", text: $searchFoodText)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                
                Picker("Meal", selection: $selectedMealCategory) {
                    ForEach(MealCategory.allCases, id: \.self) { category in
                        Text(category.rawValue.capitalized).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                List {
                    // Quick access section
                    Section("Quick Add") {
                        Button {
                            showGenericFoodsSheet = true
                        } label: {
                            Label("Generic Ingredients", systemImage: "leaf.fill")
                        }
                        
                        Button("Add Food Manually") {
                            selectedFoodForLogging = FoodItem(name: "Custom Food", calories: 0, protein: 0, carbs: 0, fats: 0)
                            showLogFoodSheet = true
                        }
                        
                        Button {
                            showRecipeBuilder = true
                        } label: {
                            Label("Recipe Builder", systemImage: "wand.and.stars")
                        }
                    }
                    
                    // Favorites section
                    if !favoriteFoods.isEmpty {
                        Section("⭐ Favorites") {
                            ForEach(favoriteFoods.prefix(5)) { log in
                                Button {
                                    logAgain(from: log)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(log.foodName).font(.subheadline)
                                            Text("\(Int(log.servingSize))g • \(log.calories) kcal")
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                    
                    if !recentFoods.isEmpty {
                        Section("🕑 Recent") {
                            ForEach(recentFoods) { log in
                                Button {
                                    logAgain(from: log, markFavorite: false)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(log.foodName).font(.subheadline)
                                            Text("\(Int(log.servingSize))g • \(log.calories) kcal")
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    
                    Section("🍱 Meal Templates") {
                        Button {
                            showTemplateBuilder = true
                        } label: {
                            Label("Save current meal as template", systemImage: "tray.and.arrow.down")
                        }
                        .disabled(filteredFoodLogs.isEmpty)
                        
                        if templatesForMeal.isEmpty {
                            Text("No templates yet for \(selectedMealCategory.rawValue).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(templatesForMeal) { template in
                                Button {
                                    logTemplate(template)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(template.name).font(.subheadline)
                                            Text("\(template.items.count) items • \(template.totalCalories) kcal")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.app.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                    
                    Section("🍳 Recipes") {
                        ForEach(recipes) { recipe in
                            Button {
                                logRecipe(recipe)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(recipe.name).font(.subheadline)
                                        Text("\(recipe.servings) servings • \(recipe.caloriesPerServing) kcal/serving")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        Button {
                            showRecipeBuilder = true
                        } label: {
                            Label(recipes.isEmpty ? "Build your first recipe" : "New recipe", systemImage: "plus.square.on.square")
                        }
                    }
                    
                    if !badges.isEmpty {
                        Section("🎖️ Badges") {
                            BadgeRibbon(badges: Array(badges.prefix(5)))
                                .onTapGesture { showBadges = true }
                        }
                    }
                    
                    Section("\(selectedMealCategory.rawValue.capitalized) on \(selectedDate.formatted(date: .abbreviated, time: .omitted))") {
                        if filteredFoodLogs.isEmpty {
                            Text("No entries yet.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(filteredFoodLogs) { log in
                                FoodLogRow(log: log)
                            }
                            .onDelete(perform: deleteFoodLog)
                        }
                    }
                }
                .navigationTitle("Nutrition Log")
            }
            .sheet(isPresented: $showingScanSheet) {
                FoodScanSheet(selectedMealCategory: selectedMealCategory) {
                    // achievements handled inside scan sheet
                }
            }
            .sheet(isPresented: $showLogFoodSheet) {
                if let food = selectedFoodForLogging {
                    LogFoodEntryView(foodItem: food, category: selectedMealCategory) { newFoodLog in
                        persistLog(newFoodLog)
                    }
                }
            }
            .sheet(isPresented: $showGenericFoodsSheet) {
                GenericFoodsSheet(selectedMealCategory: selectedMealCategory) {
                    // Refresh after logging
                }
            }
            .sheet(isPresented: $showVoiceInputSheet) {
                VoiceInputSheet(selectedMealCategory: selectedMealCategory) {
                    // Refresh after logging
                }
            }
            .sheet(isPresented: $showBudgetEditor) {
                if let profile = profile {
                    BudgetEditorSheet(profile: profile) {
                        try? modelContext.save()
                    }
                }
            }
            .sheet(isPresented: $showTemplateBuilder) {
                MealTemplateBuilderSheet(meal: selectedMealCategory, logs: filteredFoodLogs) { name in
                    saveTemplate(named: name)
                }
            }
            .sheet(isPresented: $showRecipeBuilder) {
                RecipeBuilderSheet { recipe in
                    modelContext.insert(recipe)
                    try? modelContext.save()
                    AchievementManager.shared.evaluateAfterRecipeCreated(context: modelContext)
                }
            }
            .sheet(isPresented: $showBadges) {
                BadgeShelfView(badges: badges)
            }
            .onAppear {
                fetchProfile()
            }
        }
    }
    
    private func fetchProfile() {
        do {
            let descriptor = FetchDescriptor<UserProfile>()
            if let existing = try modelContext.fetch(descriptor).first {
                self.profile = existing
            } else {
                let newProfile = UserProfile()
                modelContext.insert(newProfile)
                self.profile = newProfile
            }
        } catch {
            print("Error fetching profile in FoodLogView: \(error)")
        }
    }
    
    private func persistLog(_ log: FoodLog) {
        modelContext.insert(log)
        try? modelContext.save()
        AchievementManager.shared.evaluateAfterPersistingLog(log, context: modelContext)
    }
    
    private func logAgain(from original: FoodLog, markFavorite: Bool = true) {
        let newLog = FoodLog(
            foodName: original.foodName,
            servingSize: original.servingSize,
            calories: original.calories,
            protein: original.protein,
            carbs: original.carbs,
            fats: original.fats,
            category: selectedMealCategory,
            isFavorite: markFavorite || original.isFavorite,
            sourceType: original.sourceType,
            sourceId: original.sourceId
        )
        persistLog(newLog)
    }
    
    private func saveTemplate(named name: String) {
        guard !filteredFoodLogs.isEmpty else { return }
        let template = MealTemplate(name: name, meal: selectedMealCategory)
        filteredFoodLogs.forEach { log in
            let item = MealTemplateItem(
                foodName: log.foodName,
                servingSize: log.servingSize,
                calories: log.calories,
                protein: log.protein,
                carbs: log.carbs,
                fats: log.fats,
                template: template
            )
            template.items.append(item)
        }
        modelContext.insert(template)
        try? modelContext.save()
    }
    
    private func logTemplate(_ template: MealTemplate) {
        for item in template.items {
            let entry = FoodLog(
                timestamp: Date(),
                foodName: item.foodName,
                servingSize: item.servingSize,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fats: item.fats,
                category: template.meal,
                isFavorite: false,
                sourceType: "template",
                sourceId: template.id.uuidString
            )
            persistLog(entry)
        }
    }
    
    private func logRecipe(_ recipe: Recipe) {
        let entry = FoodLog(
            timestamp: Date(),
            foodName: recipe.name,
            servingSize: 1,
            calories: recipe.caloriesPerServing,
            protein: recipe.proteinPerServing,
            carbs: recipe.carbsPerServing,
            fats: recipe.fatsPerServing,
            category: selectedMealCategory,
            isFavorite: false,
            sourceType: "recipe",
            sourceId: recipe.id.uuidString
        )
        persistLog(entry)
    }
    
    private func deleteFoodLog(at offsets: IndexSet) {
        for index in offsets {
            let logToDelete = filteredFoodLogs[index]
            modelContext.delete(logToDelete)
        }
        try? modelContext.save()
    }
}

struct FoodLogRow: View {
    @Bindable var log: FoodLog
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(log.foodName).font(.headline)
                HStack {
                    Text("\(Int(log.servingSize))g")
                    Spacer()
                    Text("\(log.calories) kcal")
                    Text("P:\(Int(log.protein)) C:\(Int(log.carbs)) F:\(Int(log.fats))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                log.isFavorite.toggle()
            } label: {
                Image(systemName: log.isFavorite ? "star.fill" : "star")
                    .foregroundColor(log.isFavorite ? .yellow : .gray)
            }
            .buttonStyle(.plain)
        }
    }
}

struct BadgeRibbon: View {
    let badges: [AchievementBadge]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(badges) { badge in
                    HStack(spacing: 8) {
                        Image(systemName: badge.icon)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(badge.title).font(.caption).bold()
                            Text(badge.detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct BudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: UserProfile
    let onSave: () -> Void
    
    @State private var breakfastPct: Double
    @State private var lunchPct: Double
    @State private var dinnerPct: Double
    @State private var snackPct: Double
    
    init(profile: UserProfile, onSave: @escaping () -> Void) {
        _profile = Bindable(profile)
        _breakfastPct = State(initialValue: profile.mealBudgetBreakfast * 100)
        _lunchPct = State(initialValue: profile.mealBudgetLunch * 100)
        _dinnerPct = State(initialValue: profile.mealBudgetDinner * 100)
        _snackPct = State(initialValue: profile.mealBudgetSnack * 100)
        self.onSave = onSave
    }
    
    private var totalPct: Double { breakfastPct + lunchPct + dinnerPct + snackPct }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Allocate your day") {
                    budgetRow(title: "Breakfast", value: $breakfastPct)
                    budgetRow(title: "Lunch", value: $lunchPct)
                    budgetRow(title: "Dinner", value: $dinnerPct)
                    budgetRow(title: "Snacks", value: $snackPct)
                    
                    HStack {
                        Text("Total")
                        Spacer()
                        Text("\(Int(totalPct))%")
                            .foregroundColor(abs(totalPct - 100) < 1 ? .green : .orange)
                    }
                }
                
                Section("Tip") {
                    Text("Budgets always add to 100%. We’ll rebalance for you if they’re a little off.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Meal Budgets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        NutritionManager.shared.applyMealBudgets(
                            profile: profile,
                            breakfast: breakfastPct / 100,
                            lunch: lunchPct / 100,
                            dinner: dinnerPct / 100,
                            snack: snackPct / 100
                        )
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func budgetRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.0f")%")
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: 5...70, step: 1)
        }
    }
}

struct MealTemplateBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meal: MealCategory
    let logs: [FoodLog]
    let onSave: (String) -> Void
    
    @State private var name: String
    
    init(meal: MealCategory, logs: [FoodLog], onSave: @escaping (String) -> Void) {
        self.meal = meal
        self.logs = logs
        self.onSave = onSave
        _name = State(initialValue: "Usual \(meal.rawValue.capitalized)")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Template name", text: $name)
                }
                
                Section("\(meal.rawValue.capitalized) items") {
                    if logs.isEmpty {
                        Text("Log this meal first, then save it as a template.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(logs) { log in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(log.foodName)
                                    Text("\(Int(log.servingSize))g • \(log.calories) kcal")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Save Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(logs.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct EditableIngredient: Identifiable {
    let id = UUID()
    var name: String
    var amount: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fats: Double
}

struct RecipeBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Recipe) -> Void
    
    @State private var name: String = "New Recipe"
    @State private var servings: Int = 1
    @State private var ingredients: [EditableIngredient] = [
        EditableIngredient(name: "Ingredient 1", amount: 100, calories: 100, protein: 0, carbs: 0, fats: 0)
    ]
    
    private var totals: (cal: Double, protein: Double, carbs: Double, fats: Double) {
        ingredients.reduce((0, 0, 0, 0)) { partial, ing in
            (
                partial.0 + ing.calories,
                partial.1 + ing.protein,
                partial.2 + ing.carbs,
                partial.3 + ing.fats
            )
        }
    }
    
    private var perServing: (cal: Double, protein: Double, carbs: Double, fats: Double) {
        let divisor = max(1, Double(servings))
        return (totals.cal / divisor, totals.protein / divisor, totals.carbs / divisor, totals.fats / divisor)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe info") {
                    TextField("Name", text: $name)
                    Stepper("Servings: \(servings)", value: $servings, in: 1...20)
                }
                
                Section("Ingredients") {
                    ForEach($ingredients) { $ingredient in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Name", text: $ingredient.name)
                            HStack {
                                Text("Amount (g/ml)")
                                Spacer()
                                TextField("100", value: $ingredient.amount, format: .number)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 80)
                            }
                            macroFields(for: $ingredient)
                        }
                    }
                    .onDelete { indices in
                        ingredients.remove(atOffsets: indices)
                    }
                    
                    Button {
                        ingredients.append(EditableIngredient(name: "Ingredient \(ingredients.count + 1)", amount: 100, calories: 50, protein: 0, carbs: 0, fats: 0))
                    } label: {
                        Label("Add ingredient", systemImage: "plus.circle")
                    }
                }
                
                Section("Per serving") {
                    macroSummaryRow(label: "Calories", value: perServing.cal, suffix: "kcal")
                    macroSummaryRow(label: "Protein", value: perServing.protein, suffix: "g")
                    macroSummaryRow(label: "Carbs", value: perServing.carbs, suffix: "g")
                    macroSummaryRow(label: "Fats", value: perServing.fats, suffix: "g")
                }
            }
            .navigationTitle("Recipe Builder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let recipe = Recipe(name: name.trimmingCharacters(in: .whitespacesAndNewlines), servings: servings)
                        for ing in ingredients {
                            let part = RecipeIngredient(
                                name: ing.name,
                                amount: ing.amount,
                                calories: Int(ing.calories.rounded()),
                                protein: ing.protein,
                                carbs: ing.carbs,
                                fats: ing.fats,
                                recipe: recipe
                            )
                            recipe.ingredients.append(part)
                        }
                        onSave(recipe)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ingredients.isEmpty)
                }
            }
        }
    }
    
    private func macroFields(for ingredient: Binding<EditableIngredient>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Calories")
                Spacer()
                TextField("100", value: ingredient.calories, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
            }
            HStack {
                Text("Protein (g)")
                Spacer()
                TextField("0", value: ingredient.protein, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
            }
            HStack {
                Text("Carbs (g)")
                Spacer()
                TextField("0", value: ingredient.carbs, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
            }
            HStack {
                Text("Fats (g)")
                Spacer()
                TextField("0", value: ingredient.fats, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
            }
        }
    }
    
    private func macroSummaryRow(label: String, value: Double, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value, specifier: "%.1f") \(suffix)")
                .foregroundColor(.secondary)
        }
    }
}

struct BadgeShelfView: View {
    @Environment(\.dismiss) private var dismiss
    let badges: [AchievementBadge]
    
    var body: some View {
        NavigationStack {
            List {
                if badges.isEmpty {
                    Text("No badges yet. Keep logging to unlock streaks and goals!")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(badges) { badge in
                        HStack(spacing: 12) {
                            Image(systemName: badge.icon)
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text(badge.title).bold()
                                Text(badge.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(badge.unlockedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Badges")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct LogFoodEntryView: View {
    @Environment(\.dismiss) var dismiss
    let foodItem: FoodItem
    let category: MealCategory
    let onSave: (FoodLog) -> Void
    
    @State private var servingSize: Double
    
    init(foodItem: FoodItem, category: MealCategory, onSave: @escaping (FoodLog) -> Void) {
        self.foodItem = foodItem
        self.category = category
        self.onSave = onSave
        _servingSize = State(initialValue: foodItem.defaultServingSize)
    }
    
    var calculatedCalories: Int {
        Int((Double(foodItem.calories) / foodItem.defaultServingSize * servingSize).rounded())
    }
    var calculatedProtein: Double { (foodItem.protein / foodItem.defaultServingSize * servingSize) }
    var calculatedCarbs: Double { (foodItem.carbs / foodItem.defaultServingSize * servingSize) }
    var calculatedFats: Double { (foodItem.fats / foodItem.defaultServingSize * servingSize) }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Food Details") {
                    Text(foodItem.name).font(.title3)
                    Text("Per \(Int(foodItem.defaultServingSize))g: P\(Int(foodItem.protein)) C\(Int(foodItem.carbs)) F\(Int(foodItem.fats))")
                        .font(.caption)
                }
                
                Section("Log Entry") {
                    VStack(alignment: .leading) {
                        Text("Serving Size: \(Int(servingSize))g")
                        Slider(value: $servingSize, in: 1...500, step: 1)
                    }
                    
                    HStack { Text("Calories:"); Spacer(); Text("\(calculatedCalories) kcal").bold() }
                    HStack { Text("Protein:"); Spacer(); Text("\(calculatedProtein, specifier: "%.1f")g").bold() }
                    HStack { Text("Carbs:"); Spacer(); Text("\(calculatedCarbs, specifier: "%.1f")g").bold() }
                    HStack { Text("Fats:"); Spacer(); Text("\(calculatedFats, specifier: "%.1f")g").bold() }
                }
            }
            .navigationTitle("Log \(foodItem.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let newFoodLog = FoodLog(
                            timestamp: Date(),
                            foodName: foodItem.name,
                            servingSize: servingSize,
                            calories: calculatedCalories,
                            protein: calculatedProtein,
                            carbs: calculatedCarbs,
                            fats: calculatedFats,
                            category: category
                        )
                        onSave(newFoodLog)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 10) SwiftData Container / App Entry (include module models)

@main
struct IronFuelApp: App {
    var container: ModelContainer = {
        let schema = Schema([
            // App models
            UserProfile.self,
            WeightLog.self,
            FoodItem.self,
            FoodLog.self,
            MealTemplate.self,
            MealTemplateItem.self,
            Recipe.self,
            RecipeIngredient.self,
            AchievementBadge.self,
            GenericFood.self,
            WorkoutSession.self,
            WorkoutExercise.self,
            ExerciseSet.self,
            
            // Module models
            FoodProduct.self,
            UserFoodDefault.self
        ])
        return try! ModelContainer(for: schema)
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
