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
    
    init(currentWeight: Double = 70.0, caloricGoal: Int = 2500, proteinGoal: Int = 150) {
        self.currentWeight = currentWeight
        self.caloricGoal = caloricGoal
        self.proteinGoal = proteinGoal
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
    var category: String?  // "Cheat Meal", "McDonald's", "KFC", etc.
    var restaurant: String?
    
    init(name: String, calories: Int, protein: Double, carbs: Double, fats: Double, defaultServingSize: Double = 100, barcode: String? = nil, category: String? = nil, restaurant: String? = nil) {
        self.id = UUID()
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.defaultServingSize = defaultServingSize
        self.barcode = barcode
        self.category = category
        self.restaurant = restaurant
    }
}

// MARK: - Cheat Meals Database

enum CheatMealCategory: String, CaseIterable {
    case burgers = "Burgers"
    case chicken = "Chicken"
    case pizza = "Pizza"
    case mexican = "Mexican"
    case asian = "Asian"
    case subs = "Subs & Sandwiches"
    case sides = "Sides"
    case desserts = "Desserts"
    case drinks = "Drinks"
}

struct CheatMealDatabase {
    
    static let allMeals: [(name: String, calories: Int, protein: Double, carbs: Double, fats: Double, serving: Double, restaurant: String, category: CheatMealCategory)] = [
        // === McDONALD'S ===
        ("Big Mac", 550, 25, 45, 30, 1, "McDonald's", .burgers),
        ("Quarter Pounder with Cheese", 520, 30, 42, 26, 1, "McDonald's", .burgers),
        ("McChicken", 400, 14, 40, 21, 1, "McDonald's", .chicken),
        ("Chicken McNuggets (6pc)", 250, 15, 15, 15, 1, "McDonald's", .chicken),
        ("Chicken McNuggets (20pc)", 830, 49, 51, 50, 1, "McDonald's", .chicken),
        ("Large Fries", 490, 7, 66, 23, 1, "McDonald's", .sides),
        ("McFlurry Oreo", 510, 12, 80, 17, 1, "McDonald's", .desserts),
        ("Double Cheeseburger", 450, 25, 34, 24, 1, "McDonald's", .burgers),
        ("Filet-O-Fish", 390, 16, 39, 19, 1, "McDonald's", .burgers),
        ("Egg McMuffin", 310, 17, 30, 13, 1, "McDonald's", .burgers),
        
        // === BURGER KING ===
        ("Whopper", 660, 28, 49, 40, 1, "Burger King", .burgers),
        ("Whopper with Cheese", 740, 32, 50, 46, 1, "Burger King", .burgers),
        ("Double Whopper", 900, 48, 49, 56, 1, "Burger King", .burgers),
        ("Chicken Royale", 570, 24, 48, 31, 1, "Burger King", .chicken),
        ("Bacon Double Cheeseburger", 370, 22, 27, 19, 1, "Burger King", .burgers),
        
        // === KFC ===
        ("Original Recipe Chicken Breast", 390, 39, 11, 21, 1, "KFC", .chicken),
        ("Original Recipe Chicken Thigh", 280, 19, 9, 18, 1, "KFC", .chicken),
        ("Zinger Burger", 450, 22, 40, 22, 1, "KFC", .chicken),
        ("Boneless Banquet", 680, 35, 60, 32, 1, "KFC", .chicken),
        ("Popcorn Chicken (Large)", 560, 28, 36, 33, 1, "KFC", .chicken),
        ("Gravy (Regular)", 70, 2, 10, 2, 1, "KFC", .sides),
        ("Coleslaw (Regular)", 150, 1, 14, 10, 1, "KFC", .sides),
        ("Fries (Regular)", 280, 4, 38, 12, 1, "KFC", .sides),
        
        // === NANDO'S ===
        ("1/2 Chicken", 550, 65, 2, 32, 1, "Nando's", .chicken),
        ("Butterfly Chicken", 340, 53, 1, 14, 1, "Nando's", .chicken),
        ("Chicken Thighs (3pc)", 380, 30, 0, 28, 1, "Nando's", .chicken),
        ("Peri-Peri Chips (Regular)", 340, 5, 45, 15, 1, "Nando's", .sides),
        ("Spicy Rice (Regular)", 250, 6, 48, 4, 1, "Nando's", .sides),
        ("Garlic Bread", 180, 4, 22, 9, 1, "Nando's", .sides),
        
        // === SUBWAY ===
        ("Meatball Marinara (Footlong)", 960, 44, 108, 36, 1, "Subway", .subs),
        ("Italian BMT (Footlong)", 820, 38, 90, 32, 1, "Subway", .subs),
        ("Chicken Teriyaki (Footlong)", 740, 48, 100, 14, 1, "Subway", .subs),
        ("Tuna (Footlong)", 940, 40, 90, 44, 1, "Subway", .subs),
        ("Steak & Cheese (Footlong)", 740, 48, 90, 20, 1, "Subway", .subs),
        ("Turkey Breast (6 inch)", 280, 18, 46, 4, 1, "Subway", .subs),
        ("Cookies (3 pack)", 540, 6, 72, 24, 1, "Subway", .desserts),
        
        // === DOMINO'S ===
        ("Pepperoni Passion (Medium, whole)", 1800, 78, 168, 86, 1, "Domino's", .pizza),
        ("Pepperoni Passion (1 slice)", 225, 10, 21, 11, 1, "Domino's", .pizza),
        ("Mighty Meaty (Medium, whole)", 1920, 90, 168, 92, 1, "Domino's", .pizza),
        ("Mighty Meaty (1 slice)", 240, 11, 21, 12, 1, "Domino's", .pizza),
        ("Margherita (Medium, whole)", 1440, 60, 168, 56, 1, "Domino's", .pizza),
        ("Texas BBQ (Medium, whole)", 1760, 84, 176, 76, 1, "Domino's", .pizza),
        ("Garlic Pizza Bread", 670, 18, 72, 34, 1, "Domino's", .sides),
        ("Chicken Strippers (7pc)", 470, 42, 24, 22, 1, "Domino's", .sides),
        ("Cookies (4 pack)", 680, 8, 92, 32, 1, "Domino's", .desserts),
        
        // === PIZZA HUT ===
        ("Super Supreme (Medium, whole)", 2160, 96, 192, 104, 1, "Pizza Hut", .pizza),
        ("Meat Feast (Medium, whole)", 2080, 104, 184, 100, 1, "Pizza Hut", .pizza),
        ("Stuffed Crust Margherita (1 slice)", 280, 12, 28, 14, 1, "Pizza Hut", .pizza),
        ("Garlic Bread (4pc)", 460, 10, 52, 24, 1, "Pizza Hut", .sides),
        
        // === FIVE GUYS ===
        ("Cheeseburger", 840, 47, 40, 55, 1, "Five Guys", .burgers),
        ("Bacon Cheeseburger", 920, 51, 40, 62, 1, "Five Guys", .burgers),
        ("Little Hamburger", 480, 23, 39, 26, 1, "Five Guys", .burgers),
        ("Cajun Fries (Regular)", 520, 8, 60, 28, 1, "Five Guys", .sides),
        ("Cajun Fries (Large)", 950, 14, 110, 51, 1, "Five Guys", .sides),
        ("Bacon Dog", 620, 22, 40, 42, 1, "Five Guys", .burgers),
        
        // === TACO BELL ===
        ("Crunchy Taco", 170, 8, 13, 10, 1, "Taco Bell", .mexican),
        ("Crunchy Taco Supreme", 190, 8, 14, 11, 1, "Taco Bell", .mexican),
        ("Burrito Supreme - Beef", 390, 16, 43, 16, 1, "Taco Bell", .mexican),
        ("Quesadilla - Chicken", 510, 27, 37, 28, 1, "Taco Bell", .mexican),
        ("Nachos BellGrande", 740, 16, 82, 38, 1, "Taco Bell", .mexican),
        ("Cinnamon Twists", 170, 1, 26, 7, 1, "Taco Bell", .desserts),
        
        // === CHIPOTLE ===
        ("Chicken Burrito (Full Build)", 1050, 58, 102, 42, 1, "Chipotle", .mexican),
        ("Steak Bowl", 680, 42, 52, 32, 1, "Chipotle", .mexican),
        ("Chicken Quesadilla", 780, 48, 52, 42, 1, "Chipotle", .mexican),
        ("Chips & Guacamole", 770, 10, 73, 49, 1, "Chipotle", .sides),
        
        // === CHINESE TAKEAWAY ===
        ("Sweet & Sour Chicken Balls", 680, 28, 68, 32, 1, "Chinese Takeaway", .asian),
        ("Chicken Chow Mein", 520, 32, 58, 16, 1, "Chinese Takeaway", .asian),
        ("Egg Fried Rice (Large)", 480, 12, 72, 16, 1, "Chinese Takeaway", .asian),
        ("Crispy Aromatic Duck (Quarter)", 620, 38, 4, 50, 1, "Chinese Takeaway", .asian),
        ("Spring Rolls (4pc)", 320, 8, 36, 16, 1, "Chinese Takeaway", .asian),
        ("Prawn Crackers", 280, 2, 24, 20, 1, "Chinese Takeaway", .sides),
        
        // === INDIAN TAKEAWAY ===
        ("Chicken Tikka Masala", 580, 42, 22, 36, 1, "Indian Takeaway", .asian),
        ("Lamb Bhuna", 640, 38, 14, 48, 1, "Indian Takeaway", .asian),
        ("Pilau Rice", 350, 8, 62, 8, 1, "Indian Takeaway", .sides),
        ("Naan Bread", 320, 10, 52, 8, 1, "Indian Takeaway", .sides),
        ("Onion Bhaji (2pc)", 280, 6, 28, 16, 1, "Indian Takeaway", .sides),
        ("Samosa (2pc)", 340, 8, 36, 18, 1, "Indian Takeaway", .sides),
        
        // === GREGGS ===
        ("Sausage Roll", 327, 7, 24, 22, 1, "Greggs", .subs),
        ("Steak Bake", 408, 13, 35, 24, 1, "Greggs", .subs),
        ("Chicken Bake", 457, 17, 38, 27, 1, "Greggs", .subs),
        ("Vegan Sausage Roll", 312, 11, 26, 18, 1, "Greggs", .subs),
        ("Festive Bake", 458, 14, 37, 28, 1, "Greggs", .subs),
        ("Yum Yum (3 pack)", 450, 4, 54, 24, 1, "Greggs", .desserts),
        
        // === DRINKS ===
        ("Coca-Cola (500ml)", 210, 0, 53, 0, 1, "Drinks", .drinks),
        ("Coca-Cola (Large McDonald's)", 290, 0, 76, 0, 1, "McDonald's", .drinks),
        ("Milkshake Chocolate (Large)", 580, 14, 92, 18, 1, "McDonald's", .drinks),
        ("Fanta Orange (500ml)", 225, 0, 54, 0, 1, "Drinks", .drinks),
        ("Costa Latte (Large)", 180, 10, 16, 8, 1, "Costa", .drinks),
        ("Starbucks Frappuccino (Grande)", 380, 5, 60, 14, 1, "Starbucks", .drinks),
        
        // === DESSERTS ===
        ("Ben & Jerry's Cookie Dough (500ml)", 1200, 16, 140, 62, 1, "Ice Cream", .desserts),
        ("Häagen-Dazs Salted Caramel (500ml)", 1160, 16, 112, 72, 1, "Ice Cream", .desserts),
        ("Krispy Kreme Original Glazed", 190, 3, 22, 11, 1, "Krispy Kreme", .desserts),
        ("Krispy Kreme Chocolate Dreamcake", 350, 4, 42, 19, 1, "Krispy Kreme", .desserts),
    ]
    
    @MainActor
    static func seedDatabase(context: ModelContext) {
        // Check if already seeded
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.category == "Cheat Meal" })
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        
        guard existingCount == 0 else { return }  // Already seeded
        
        for meal in allMeals {
            let foodItem = FoodItem(
                name: "\(meal.restaurant) - \(meal.name)",
                calories: meal.calories,
                protein: meal.protein,
                carbs: meal.carbs,
                fats: meal.fats,
                defaultServingSize: meal.serving,
                category: "Cheat Meal",
                restaurant: meal.restaurant
            )
            context.insert(foodItem)
        }
        
        try? context.save()
        print("🍔 Cheat meals database seeded with \(allMeals.count) items")
    }
    
    static func getRestaurants() -> [String] {
        Array(Set(allMeals.map { $0.restaurant })).sorted()
    }
    
    static func getMealsByRestaurant(_ restaurant: String) -> [(name: String, calories: Int, protein: Double, carbs: Double, fats: Double, serving: Double, restaurant: String, category: CheatMealCategory)] {
        allMeals.filter { $0.restaurant == restaurant }
    }
    
    static func getMealsByCategory(_ category: CheatMealCategory) -> [(name: String, calories: Int, protein: Double, carbs: Double, fats: Double, serving: Double, restaurant: String, category: CheatMealCategory)] {
        allMeals.filter { $0.category == category }
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
    
    init(timestamp: Date = Date(), foodName: String, servingSize: Double, calories: Int, protein: Double, carbs: Double, fats: Double, category: MealCategory) {
        self.timestamp = timestamp
        self.foodName = foodName
        self.servingSize = servingSize
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.category = category
    }
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

// 3.7 FoodScanViewModel.swift

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
    
    // MARK: - Weekly Summary
    
    struct WeeklySummaryData {
        let averageCalories: Int
        let averageProtein: Double
        let averageCarbs: Double
        let averageFats: Double
        let proteinAdherencePercent: Double
        let daysLogged: Int
    }
    
    @MainActor
    func getWeeklySummary(profile: UserProfile, context: ModelContext) -> WeeklySummaryData? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) else { return nil }
        
        let predicate = #Predicate<FoodLog> { log in
            log.timestamp >= weekAgo && log.timestamp < calendar.date(byAdding: .day, value: 1, to: today)!
        }
        
        let descriptor = FetchDescriptor<FoodLog>(predicate: predicate)
        
        do {
            let logs = try context.fetch(descriptor)
            guard !logs.isEmpty else { return nil }
            
            // Group logs by day
            var dailyTotals: [Date: (kcal: Int, protein: Double, carbs: Double, fats: Double)] = [:]
            
            for log in logs {
                let day = calendar.startOfDay(for: log.timestamp)
                let current = dailyTotals[day] ?? (0, 0, 0, 0)
                dailyTotals[day] = (
                    current.kcal + log.calories,
                    current.protein + log.protein,
                    current.carbs + log.carbs,
                    current.fats + log.fats
                )
            }
            
            let daysLogged = dailyTotals.count
            guard daysLogged > 0 else { return nil }
            
            let totalKcal = dailyTotals.values.reduce(0) { $0 + $1.kcal }
            let totalProtein = dailyTotals.values.reduce(0.0) { $0 + $1.protein }
            let totalCarbs = dailyTotals.values.reduce(0.0) { $0 + $1.carbs }
            let totalFats = dailyTotals.values.reduce(0.0) { $0 + $1.fats }
            
            // Calculate protein adherence (days meeting protein goal)
            let proteinGoal = Double(profile.proteinGoal)
            let daysMeetingProtein = dailyTotals.values.filter { $0.protein >= proteinGoal }.count
            let adherencePercent = (Double(daysMeetingProtein) / 7.0) * 100.0
            
            return WeeklySummaryData(
                averageCalories: totalKcal / daysLogged,
                averageProtein: totalProtein / Double(daysLogged),
                averageCarbs: totalCarbs / Double(daysLogged),
                averageFats: totalFats / Double(daysLogged),
                proteinAdherencePercent: adherencePercent,
                daysLogged: daysLogged
            )
        } catch {
            print("Error fetching weekly summary: \(error)")
            return nil
        }
    }
    
    // MARK: - Trend Analysis
    
    struct TrendInsight: Identifiable {
        let id = UUID()
        let message: String
        let trend: TrendDirection
        let icon: String
    }
    
    enum TrendDirection {
        case up, down, neutral
        
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .neutral: return .gray
            }
        }
    }
    
    @MainActor
    func getTrendAnalysis(profile: UserProfile, context: ModelContext) -> [TrendInsight] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        guard let thisWeekStart = calendar.date(byAdding: .day, value: -7, to: today),
              let lastWeekStart = calendar.date(byAdding: .day, value: -14, to: today) else { return [] }
        
        // Fetch this week's logs
        let thisWeekPredicate = #Predicate<FoodLog> { log in
            log.timestamp >= thisWeekStart && log.timestamp < today
        }
        let thisWeekDescriptor = FetchDescriptor<FoodLog>(predicate: thisWeekPredicate)
        
        // Fetch last week's logs
        let lastWeekPredicate = #Predicate<FoodLog> { log in
            log.timestamp >= lastWeekStart && log.timestamp < thisWeekStart
        }
        let lastWeekDescriptor = FetchDescriptor<FoodLog>(predicate: lastWeekPredicate)
        
        do {
            let thisWeekLogs = try context.fetch(thisWeekDescriptor)
            let lastWeekLogs = try context.fetch(lastWeekDescriptor)
            
            var insights: [TrendInsight] = []
            
            // Calculate weekly averages
            let thisWeekProtein = thisWeekLogs.reduce(0.0) { $0 + $1.protein }
            let lastWeekProtein = lastWeekLogs.reduce(0.0) { $0 + $1.protein }
            
            let thisWeekCalories = thisWeekLogs.reduce(0) { $0 + $1.calories }
            let lastWeekCalories = lastWeekLogs.reduce(0) { $0 + $1.calories }
            
            // Protein trend
            if lastWeekProtein > 0 {
                let proteinChange = ((thisWeekProtein - lastWeekProtein) / lastWeekProtein) * 100
                if abs(proteinChange) >= 5 {
                    let direction: TrendDirection = proteinChange > 0 ? .up : .down
                    let verb = proteinChange > 0 ? "improved" : "decreased"
                    insights.append(TrendInsight(
                        message: "Your protein intake \(verb) \(Int(abs(proteinChange)))% this week",
                        trend: direction,
                        icon: proteinChange > 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"
                    ))
                }
            }
            
            // Calorie consistency
            if lastWeekCalories > 0 {
                let calorieChange = ((Double(thisWeekCalories) - Double(lastWeekCalories)) / Double(lastWeekCalories)) * 100
                if abs(calorieChange) < 10 {
                    insights.append(TrendInsight(
                        message: "Great calorie consistency! Staying within 10% of last week",
                        trend: .neutral,
                        icon: "checkmark.circle.fill"
                    ))
                } else if calorieChange > 10 {
                    insights.append(TrendInsight(
                        message: "Calorie intake up \(Int(calorieChange))% from last week",
                        trend: .up,
                        icon: "flame.fill"
                    ))
                }
            }
            
            // Logging consistency
            let thisWeekDays = Set(thisWeekLogs.map { calendar.startOfDay(for: $0.timestamp) }).count
            if thisWeekDays >= 6 {
                insights.append(TrendInsight(
                    message: "Excellent tracking! You logged \(thisWeekDays) of 7 days",
                    trend: .up,
                    icon: "star.fill"
                ))
            } else if thisWeekDays >= 4 {
                insights.append(TrendInsight(
                    message: "Good effort! \(thisWeekDays) days logged this week",
                    trend: .neutral,
                    icon: "hand.thumbsup.fill"
                ))
            } else if thisWeekDays > 0 {
                insights.append(TrendInsight(
                    message: "Try to log more consistently - only \(thisWeekDays) days tracked",
                    trend: .down,
                    icon: "exclamationmark.triangle.fill"
                ))
            }
            
            // Empty state
            if insights.isEmpty && thisWeekLogs.isEmpty {
                insights.append(TrendInsight(
                    message: "Start logging to see your trends!",
                    trend: .neutral,
                    icon: "chart.line.uptrend.xyaxis"
                ))
            }
            
            return insights
        } catch {
            print("Error fetching trend analysis: \(error)")
            return []
        }
    }
    
    // MARK: - Weight vs Nutrition Correlation
    
    struct WeightNutritionCorrelation {
        let weightChange: Double  // in kg
        let avgDailyCalories: Int
        let avgDailyDeficit: Int  // positive = deficit, negative = surplus
        let expectedWeightChange: Double  // based on calories
        let daysAnalyzed: Int
        let correlation: CorrelationType
    }
    
    enum CorrelationType: String {
        case onTrack = "On Track"
        case aheadOfPlan = "Ahead of Plan"
        case behindPlan = "Behind Plan"
        case noData = "Insufficient Data"
        
        var color: Color {
            switch self {
            case .onTrack: return .green
            case .aheadOfPlan: return .blue
            case .behindPlan: return .orange
            case .noData: return .gray
            }
        }
        
        var icon: String {
            switch self {
            case .onTrack: return "checkmark.circle.fill"
            case .aheadOfPlan: return "arrow.up.circle.fill"
            case .behindPlan: return "arrow.down.circle.fill"
            case .noData: return "questionmark.circle.fill"
            }
        }
    }
    
    @MainActor
    func getWeightNutritionCorrelation(profile: UserProfile, weightLogs: [WeightLog], context: ModelContext) -> WeightNutritionCorrelation? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today) else { return nil }
        
        // Get weight change over 2 weeks
        let recentWeights = weightLogs
            .filter { $0.date >= twoWeeksAgo }
            .sorted { $0.date < $1.date }
        
        guard recentWeights.count >= 2 else { return nil }
        
        let startWeight = recentWeights.first!.weight
        let endWeight = recentWeights.last!.weight
        let weightChange = endWeight - startWeight
        
        // Get food logs for the same period
        let predicate = #Predicate<FoodLog> { log in
            log.timestamp >= twoWeeksAgo && log.timestamp < today
        }
        let descriptor = FetchDescriptor<FoodLog>(predicate: predicate)
        
        do {
            let logs = try context.fetch(descriptor)
            guard !logs.isEmpty else { return nil }
            
            // Group by day and calculate daily totals
            var dailyCalories: [Date: Int] = [:]
            for log in logs {
                let day = calendar.startOfDay(for: log.timestamp)
                dailyCalories[day, default: 0] += log.calories
            }
            
            let daysLogged = dailyCalories.count
            guard daysLogged >= 3 else { return nil }
            
            let totalCalories = dailyCalories.values.reduce(0, +)
            let avgDailyCalories = totalCalories / daysLogged
            
            // Calculate TDEE and deficit/surplus
            let tdee = calculateTDEE(profile: profile)
            let avgDailyDeficit = tdee - avgDailyCalories
            
            // Expected weight change: 7700 kcal ≈ 1kg
            // Over the logged days, what should the weight change be?
            let totalDeficit = avgDailyDeficit * daysLogged
            let expectedWeightChange = Double(totalDeficit) / 7700.0 * -1  // negative deficit = weight loss
            
            // Determine correlation type
            let correlation: CorrelationType
            let actualVsExpected = weightChange - expectedWeightChange
            
            if abs(actualVsExpected) < 0.3 {
                correlation = .onTrack
            } else if weightChange < expectedWeightChange {
                correlation = .aheadOfPlan  // Lost more than expected
            } else {
                correlation = .behindPlan  // Lost less than expected
            }
            
            return WeightNutritionCorrelation(
                weightChange: weightChange,
                avgDailyCalories: avgDailyCalories,
                avgDailyDeficit: avgDailyDeficit,
                expectedWeightChange: expectedWeightChange,
                daysAnalyzed: daysLogged,
                correlation: correlation
            )
        } catch {
            print("Error calculating weight-nutrition correlation: \(error)")
            return nil
        }
    }
    
    // MARK: - Streak Tracking
    
    struct StreakData {
        let currentStreak: Int
        let longestStreak: Int
        let totalDaysLogged: Int
        let lastLogDate: Date?
    }
    
    @MainActor
    func getStreakData(context: ModelContext) -> StreakData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Get all food logs
        let descriptor = FetchDescriptor<FoodLog>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        
        do {
            let logs = try context.fetch(descriptor)
            guard !logs.isEmpty else {
                return StreakData(currentStreak: 0, longestStreak: 0, totalDaysLogged: 0, lastLogDate: nil)
            }
            
            // Get unique days
            let loggedDays = Set(logs.map { calendar.startOfDay(for: $0.timestamp) }).sorted(by: >)
            let totalDays = loggedDays.count
            let lastLogDate = loggedDays.first
            
            // Calculate current streak (consecutive days ending today or yesterday)
            var currentStreak = 0
            var checkDate = today
            
            for day in loggedDays {
                if day == checkDate || day == calendar.date(byAdding: .day, value: -1, to: checkDate) {
                    currentStreak += 1
                    checkDate = day
                } else if day < calendar.date(byAdding: .day, value: -1, to: checkDate)! {
                    break
                }
            }
            
            // Calculate longest streak
            var longestStreak = 0
            var tempStreak = 1
            let sortedDays = loggedDays.sorted()
            
            for i in 1..<sortedDays.count {
                let prevDay = sortedDays[i - 1]
                let currentDay = sortedDays[i]
                
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: prevDay), nextDay == currentDay {
                    tempStreak += 1
                } else {
                    longestStreak = max(longestStreak, tempStreak)
                    tempStreak = 1
                }
            }
            longestStreak = max(longestStreak, tempStreak)
            
            return StreakData(
                currentStreak: currentStreak,
                longestStreak: longestStreak,
                totalDaysLogged: totalDays,
                lastLogDate: lastLogDate
            )
        } catch {
            print("Error fetching streak data: \(error)")
            return StreakData(currentStreak: 0, longestStreak: 0, totalDaysLogged: 0, lastLogDate: nil)
        }
    }
    
    // MARK: - Weekly Progress Data (for chart)
    
    struct WeeklyProgressPoint: Identifiable {
        let id = UUID()
        let date: Date
        let calories: Int
        let weight: Double?
    }
    
    @MainActor
    func getWeeklyProgressData(weightLogs: [WeightLog], context: ModelContext) -> [WeeklyProgressPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var points: [WeeklyProgressPoint] = []
        
        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let nextDay = calendar.date(byAdding: .day, value: 1, to: date)!
            
            // Get calories for this day
            let predicate = #Predicate<FoodLog> { log in
                log.timestamp >= date && log.timestamp < nextDay
            }
            let descriptor = FetchDescriptor<FoodLog>(predicate: predicate)
            
            do {
                let logs = try context.fetch(descriptor)
                let dailyCalories = logs.reduce(0) { $0 + $1.calories }
                
                // Get weight for this day if available
                let weight = weightLogs.first { calendar.isDate($0.date, inSameDayAs: date) }?.weight
                
                points.append(WeeklyProgressPoint(date: date, calories: dailyCalories, weight: weight))
            } catch {
                points.append(WeeklyProgressPoint(date: date, calories: 0, weight: nil))
            }
        }
        
        return points
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
            
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
                .tag(3)
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

// MARK: - Insights & Analytics Views

struct WeeklySummaryCard: View {
    let summary: NutritionManager.WeeklySummaryData?
    let targetCalories: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("📊 Weekly Summary")
                    .font(.headline)
                Spacer()
                if let summary = summary {
                    Text("\(summary.daysLogged)/7 days logged")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let summary = summary {
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("\(summary.averageCalories)")
                            .font(.title)
                            .bold()
                            .foregroundColor(.orange)
                        Text("Avg Calories")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                        .frame(height: 50)
                    
                    VStack(spacing: 4) {
                        Text("\(Int(summary.proteinAdherencePercent))%")
                            .font(.title)
                            .bold()
                            .foregroundColor(summary.proteinAdherencePercent >= 70 ? .green : .orange)
                        Text("Protein Goal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
                
                HStack {
                    MacroLabel(name: "P", value: summary.averageProtein, color: .blue)
                    MacroLabel(name: "C", value: summary.averageCarbs, color: .green)
                    MacroLabel(name: "F", value: summary.averageFats, color: .orange)
                }
            } else {
                Text("Log food for 7 days to see your weekly summary")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

struct MacroLabel: View {
    let name: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.caption2)
                .bold()
                .foregroundColor(color)
            Text("\(Int(value))g")
                .font(.caption)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MacroPieChartView: View {
    let protein: Double
    let carbs: Double
    let fats: Double
    
    var total: Double { protein + carbs + fats }
    
    var macroData: [(name: String, value: Double, color: Color)] {
        [
            ("Protein", protein, .blue),
            ("Carbs", carbs, .green),
            ("Fats", fats, .orange)
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🥧 Macro Distribution")
                .font(.headline)
            
            if total > 0 {
                HStack(spacing: 20) {
                    Chart(macroData, id: \.name) { item in
                        SectorMark(
                            angle: .value("Grams", item.value),
                            innerRadius: .ratio(0.5),
                            angularInset: 2
                        )
                        .foregroundStyle(item.color)
                        .cornerRadius(4)
                    }
                    .frame(width: 120, height: 120)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(macroData, id: \.name) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                        .font(.caption)
                                        .bold()
                                    Text("\(Int(item.value))g (\(Int((item.value / total) * 100))%)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text("No macro data available yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

struct TrendAnalysisCard: View {
    let insights: [NutritionManager.TrendInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📈 Trend Analysis")
                .font(.headline)
            
            if insights.isEmpty {
                Text("Keep logging to unlock trend insights!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(insights) { insight in
                        HStack(spacing: 12) {
                            Image(systemName: insight.icon)
                                .font(.title2)
                                .foregroundColor(insight.trend.color)
                                .frame(width: 32)
                            
                            Text(insight.message)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(insight.trend.color.opacity(0.1))
                        .cornerRadius(8)
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

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var profile: UserProfile?
    @State private var weeklySummary: NutritionManager.WeeklySummaryData?
    @State private var trendInsights: [NutritionManager.TrendInsight] = []
    @State private var todayMacros: (protein: Double, carbs: Double, fats: Double) = (0, 0, 0)
    @State private var weightCorrelation: NutritionManager.WeightNutritionCorrelation?
    @State private var streakData: NutritionManager.StreakData?
    @State private var progressData: [NutritionManager.WeeklyProgressPoint] = []
    @State private var todaySummary: (kcal: Int, protein: Double, carbs: Double, fats: Double)?
    @State private var showDailyConfirmation = false
    @State private var dayConfirmed = false
    
    @Query(sort: \WeightLog.date, order: .reverse) private var weightLogs: [WeightLog]
    
    private let nutritionManager = NutritionManager.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Daily Confirmation Card
                    DailyConfirmationCard(
                        todaySummary: todaySummary,
                        profile: profile,
                        isConfirmed: dayConfirmed,
                        onConfirm: { dayConfirmed = true }
                    )
                    
                    // Streak Card
                    if let streak = streakData {
                        StreakCard(streakData: streak)
                    }
                    
                    // Weekly Summary
                    WeeklySummaryCard(
                        summary: weeklySummary,
                        targetCalories: profile.map { nutritionManager.calculateCaloricTarget(profile: $0) } ?? 2000
                    )
                    
                    // Macro Pie Chart
                    MacroPieChartView(
                        protein: weeklySummary?.averageProtein ?? todayMacros.protein,
                        carbs: weeklySummary?.averageCarbs ?? todayMacros.carbs,
                        fats: weeklySummary?.averageFats ?? todayMacros.fats
                    )
                    
                    // Weight vs Nutrition Correlation
                    if let correlation = weightCorrelation {
                        WeightNutritionCard(correlation: correlation)
                    }
                    
                    // Weekly Progress Chart
                    if !progressData.isEmpty {
                        WeeklyProgressChart(
                            data: progressData,
                            targetCalories: profile.map { nutritionManager.calculateCaloricTarget(profile: $0) } ?? 2000
                        )
                    }
                    
                    // Trend Analysis
                    TrendAnalysisCard(insights: trendInsights)
                }
                .padding()
            }
            .navigationTitle("Insights ⚡️")
            .onAppear { loadData() }
            .refreshable { loadData() }
        }
    }
    
    private func loadData() {
        let profileDescriptor = FetchDescriptor<UserProfile>()
        if let existingProfile = try? modelContext.fetch(profileDescriptor).first {
            profile = existingProfile
            weeklySummary = nutritionManager.getWeeklySummary(profile: existingProfile, context: modelContext)
            trendInsights = nutritionManager.getTrendAnalysis(profile: existingProfile, context: modelContext)
            weightCorrelation = nutritionManager.getWeightNutritionCorrelation(profile: existingProfile, weightLogs: weightLogs, context: modelContext)
        }
        
        streakData = nutritionManager.getStreakData(context: modelContext)
        progressData = nutritionManager.getWeeklyProgressData(weightLogs: weightLogs, context: modelContext)
        
        if let dailySummary = nutritionManager.getDailySummary(for: Date(), context: modelContext) {
            todayMacros = (dailySummary.protein, dailySummary.carbs, dailySummary.fats)
            todaySummary = dailySummary
        }
    }
}

// MARK: - Daily Confirmation Card

struct DailyConfirmationCard: View {
    let todaySummary: (kcal: Int, protein: Double, carbs: Double, fats: Double)?
    let profile: UserProfile?
    let isConfirmed: Bool
    let onConfirm: () -> Void
    
    var targetCalories: Int {
        profile.map { NutritionManager.shared.calculateCaloricTarget(profile: $0) } ?? 2000
    }
    
    var proteinGoal: Int { profile?.proteinGoal ?? 150 }
    
    var encouragingMessage: String {
        guard let summary = todaySummary else {
            return "📝 Start logging your meals to track progress!"
        }
        
        let caloriesDiff = summary.kcal - targetCalories
        let proteinMet = summary.protein >= Double(proteinGoal)
        
        if isConfirmed {
            return "✅ Day confirmed! Great job staying accountable!"
        }
        
        // Under calories + hit protein = perfect
        if caloriesDiff <= 0 && proteinMet {
            return "🎯 Perfect day! Under calories AND hit protein goal!"
        }
        // Under calories but missed protein
        else if caloriesDiff <= 0 && !proteinMet {
            return "💪 Good calorie control! Try to get more protein tomorrow."
        }
        // Over calories but hit protein
        else if caloriesDiff > 0 && caloriesDiff <= 200 && proteinMet {
            return "👍 Solid effort! Just slightly over, great protein intake."
        }
        // Significantly over
        else if caloriesDiff > 200 {
            let overBy = caloriesDiff
            return "📊 \(overBy) over target. Tomorrow's a new day—stay consistent!"
        }
        else {
            return "🌟 Keep logging to see your progress!"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("📅 Today's Summary")
                    .font(.headline)
                Spacer()
                if isConfirmed {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                }
            }
            
            if let summary = todaySummary {
                HStack(spacing: 15) {
                    VStack {
                        Text("\(summary.kcal)")
                            .font(.title2).bold()
                            .foregroundColor(summary.kcal <= targetCalories ? .green : .orange)
                        Text("/ \(targetCalories)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("kcal")
                            .font(.caption2)
                    }
                    
                    Divider().frame(height: 40)
                    
                    VStack {
                        Text("\(Int(summary.protein))g")
                            .font(.title2).bold()
                            .foregroundColor(summary.protein >= Double(proteinGoal) ? .green : .orange)
                        Text("/ \(proteinGoal)g")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("protein")
                            .font(.caption2)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            
            Text(encouragingMessage)
                .font(.subheadline)
                .foregroundColor(.primary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if todaySummary != nil && !isConfirmed {
                Button(action: onConfirm) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Confirm Today's Diary")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

// MARK: - Streak Card

struct StreakCard: View {
    let streakData: NutritionManager.StreakData
    
    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("🔥")
                    .font(.largeTitle)
                Text("\(streakData.currentStreak)")
                    .font(.title).bold()
                    .foregroundColor(.orange)
                Text("Current")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Divider().frame(height: 60)
            
            VStack(spacing: 4) {
                Text("🏆")
                    .font(.largeTitle)
                Text("\(streakData.longestStreak)")
                    .font(.title).bold()
                    .foregroundColor(.yellow)
                Text("Best")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Divider().frame(height: 60)
            
            VStack(spacing: 4) {
                Text("📊")
                    .font(.largeTitle)
                Text("\(streakData.totalDaysLogged)")
                    .font(.title).bold()
                    .foregroundColor(.blue)
                Text("Total Days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

// MARK: - Weight vs Nutrition Correlation Card

struct WeightNutritionCard: View {
    let correlation: NutritionManager.WeightNutritionCorrelation
    
    var weightChangeText: String {
        let change = correlation.weightChange
        if abs(change) < 0.1 {
            return "No change"
        } else if change < 0 {
            return "\(String(format: "%.1f", abs(change)))kg lost"
        } else {
            return "\(String(format: "%.1f", change))kg gained"
        }
    }
    
    var deficitText: String {
        if correlation.avgDailyDeficit > 0 {
            return "\(correlation.avgDailyDeficit) cal deficit"
        } else {
            return "\(abs(correlation.avgDailyDeficit)) cal surplus"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("⚖️ Weight vs Nutrition")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: correlation.correlation.icon)
                        .foregroundColor(correlation.correlation.color)
                    Text(correlation.correlation.rawValue)
                        .font(.caption)
                        .foregroundColor(correlation.correlation.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(correlation.correlation.color.opacity(0.15))
                .cornerRadius(8)
            }
            
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(weightChangeText)
                        .font(.title3).bold()
                        .foregroundColor(correlation.weightChange <= 0 ? .green : .orange)
                    Text("Actual")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 4) {
                    Text(deficitText)
                        .font(.title3).bold()
                        .foregroundColor(.blue)
                    Text("Avg Daily")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            
            Text("Based on \(correlation.daysAnalyzed) days of data")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

// MARK: - Weekly Progress Chart

struct WeeklyProgressChart: View {
    let data: [NutritionManager.WeeklyProgressPoint]
    let targetCalories: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📈 Weekly Progress")
                .font(.headline)
            
            Chart {
                ForEach(data) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Calories", point.calories)
                    )
                    .foregroundStyle(point.calories <= targetCalories ? Color.green : Color.orange)
                }
                
                RuleMark(y: .value("Target", targetCalories))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
            }
            .frame(height: 150)
            .chartYAxisLabel("Calories")
            
            HStack {
                Circle().fill(.green).frame(width: 10, height: 10)
                Text("Under target").font(.caption)
                Circle().fill(.orange).frame(width: 10, height: 10)
                Text("Over target").font(.caption)
                Spacer()
            }
            .foregroundColor(.secondary)
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
    
    // Quick Add Food states
    @State private var showQuickAddMenu = false
    @State private var showQuickScanSheet = false
    @State private var showQuickAddSheet = false
    @State private var selectedQuickMeal: MealCategory = .snack
    @StateObject private var cameraPermission = CameraPermission()
    @State private var showCameraDeniedAlert = false
    
    private let nutritionManager = NutritionManager.shared
    private let today = Date()
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
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
                        
                        // Extra padding at bottom for FAB
                        Spacer().frame(height: 80)
                    }
                    .padding()
                }
                
                // Floating Action Button for Quick Add Food
                QuickAddFoodButton(
                    showMenu: $showQuickAddMenu,
                    selectedMeal: $selectedQuickMeal,
                    onScanTapped: {
                        Task {
                            cameraPermission.refresh()
                            if !cameraPermission.authorised {
                                await cameraPermission.request()
                            }
                            if cameraPermission.authorised {
                                showQuickScanSheet = true
                            } else {
                                showCameraDeniedAlert = true
                            }
                        }
                    },
                    onManualTapped: {
                        showQuickAddSheet = true
                    }
                )
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Today's Fuel ⚡️")
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
            .sheet(isPresented: $showQuickScanSheet) {
                FoodScanSheet(selectedMealCategory: selectedQuickMeal) {
                    // Food logged successfully
                }
            }
            .sheet(isPresented: $showQuickAddSheet) {
                QuickAddFoodSheet(mealCategory: selectedQuickMeal)
            }
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
    
    // Set your backend base URL here
    private let backendBaseURL = URL(string: "https://api.yourapp.com")!
    
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
    
    @State private var selectedMealCategory: MealCategory = .breakfast
    @State private var searchFoodText: String = ""
    @State private var showLogFoodSheet: Bool = false
    @State private var selectedFoodForLogging: FoodItem?
    @State private var showCheatMeals: Bool = false
    
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var foodLogs: [FoodLog]
    
    var filteredFoodLogs: [FoodLog] {
        foodLogs.filter { log in
            Calendar.current.isDate(log.timestamp, inSameDayAs: selectedDate) &&
            (searchFoodText.isEmpty || log.foodName.localizedCaseInsensitiveContains(searchFoodText)) &&
            (log.category == selectedMealCategory)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .padding(.horizontal)
                
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
                    Section {
                        Button(action: { showCheatMeals = true }) {
                            Label("🍔 Cheat Meals", systemImage: "flame.fill")
                                .foregroundColor(.orange)
                        }
                        
                        Button("Add Food Manually (Mock)") {
                            selectedFoodForLogging = FoodItem(name: "Custom Food", calories: 0, protein: 0, carbs: 0, fats: 0)
                            showLogFoodSheet = true
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
                    // Optional hook: refresh UI, etc.
                }
            }
            .sheet(isPresented: $showLogFoodSheet) {
                if let food = selectedFoodForLogging {
                    LogFoodEntryView(foodItem: food, category: selectedMealCategory) { newFoodLog in
                        modelContext.insert(newFoodLog)
                        try? modelContext.save()
                    }
                }
            }
            .sheet(isPresented: $showCheatMeals) {
                CheatMealsView(mealCategory: selectedMealCategory) { _ in
                    // Food logged, sheet will dismiss
                }
            }
        }
    }
    
    private func deleteFoodLog(at offsets: IndexSet) {
        for index in offsets {
            let logToDelete = filteredFoodLogs[index]
            modelContext.delete(logToDelete)
        }
        try? modelContext.save()
    }
}

// MARK: - Cheat Meals Browser

struct CheatMealsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let mealCategory: MealCategory
    let onLog: (FoodLog) -> Void
    
    @State private var selectedRestaurant: String?
    @State private var searchText = ""
    
    var restaurants: [String] {
        CheatMealDatabase.getRestaurants()
    }
    
    var filteredMeals: [(name: String, calories: Int, protein: Double, carbs: Double, fats: Double, serving: Double, restaurant: String, category: CheatMealCategory)] {
        var meals = CheatMealDatabase.allMeals
        
        if let restaurant = selectedRestaurant {
            meals = meals.filter { $0.restaurant == restaurant }
        }
        
        if !searchText.isEmpty {
            meals = meals.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.restaurant.localizedCaseInsensitiveContains(searchText) }
        }
        
        return meals
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Restaurant filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: selectedRestaurant == nil) {
                            selectedRestaurant = nil
                        }
                        ForEach(restaurants, id: \.self) { restaurant in
                            FilterChip(title: restaurant, isSelected: selectedRestaurant == restaurant) {
                                selectedRestaurant = restaurant
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
                
                List {
                    ForEach(filteredMeals, id: \.name) { meal in
                        CheatMealRow(meal: meal) {
                            logMeal(meal)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search meals...")
            .navigationTitle("🍔 Cheat Meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func logMeal(_ meal: (name: String, calories: Int, protein: Double, carbs: Double, fats: Double, serving: Double, restaurant: String, category: CheatMealCategory)) {
        let foodLog = FoodLog(
            timestamp: Date(),
            foodName: "\(meal.restaurant) - \(meal.name)",
            servingSize: meal.serving,
            calories: meal.calories,
            protein: meal.protein,
            carbs: meal.carbs,
            fats: meal.fats,
            category: mealCategory
        )
        
        modelContext.insert(foodLog)
        try? modelContext.save()
        onLog(foodLog)
        dismiss()
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

struct CheatMealRow: View {
    let meal: (name: String, calories: Int, protein: Double, carbs: Double, fats: Double, serving: Double, restaurant: String, category: CheatMealCategory)
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(meal.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(meal.calories) kcal")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
                
                HStack {
                    Text(meal.restaurant)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        MacroBadge(label: "P", value: meal.protein, color: .blue)
                        MacroBadge(label: "C", value: meal.carbs, color: .green)
                        MacroBadge(label: "F", value: meal.fats, color: .orange)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct MacroBadge: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text("\(Int(value))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct FoodLogRow: View {
    let log: FoodLog
    
    var body: some View {
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

// MARK: - Quick Add Food Button (FAB)

struct QuickAddFoodButton: View {
    @Binding var showMenu: Bool
    @Binding var selectedMeal: MealCategory
    let onScanTapped: () -> Void
    let onManualTapped: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            if showMenu {
                // Meal category selector
                VStack(spacing: 8) {
                    ForEach(MealCategory.allCases, id: \.self) { category in
                        Button {
                            selectedMeal = category
                        } label: {
                            HStack {
                                Image(systemName: category == selectedMeal ? "checkmark.circle.fill" : "circle")
                                Text(category.rawValue.capitalized)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(category == selectedMeal ? Color.accentColor : Color(.systemGray5))
                            .foregroundColor(category == selectedMeal ? .white : .primary)
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                
                // Action buttons
                HStack(spacing: 12) {
                    // Scan button
                    Button(action: {
                        withAnimation { showMenu = false }
                        onScanTapped()
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.title2)
                            Text("Scan")
                                .font(.caption)
                        }
                        .frame(width: 60, height: 60)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(30)
                        .shadow(radius: 4)
                    }
                    
                    // Manual button
                    Button(action: {
                        withAnimation { showMenu = false }
                        onManualTapped()
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                                .font(.title2)
                            Text("Manual")
                                .font(.caption)
                        }
                        .frame(width: 60, height: 60)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(30)
                        .shadow(radius: 4)
                    }
                }
            }
            
            // Main FAB
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    showMenu.toggle()
                }
            }) {
                Image(systemName: showMenu ? "xmark" : "plus")
                    .font(.title.weight(.semibold))
                    .frame(width: 60, height: 60)
                    .background(
                        LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(30)
                    .shadow(color: .orange.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .rotationEffect(.degrees(showMenu ? 45 : 0))
        }
    }
}

// MARK: - Quick Add Food Sheet

struct QuickAddFoodSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let mealCategory: MealCategory
    
    @State private var foodName: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fats: String = ""
    @State private var servingSize: String = "100"
    
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var recentLogs: [FoodLog]
    
    var recentFoods: [FoodLog] {
        // Get unique food names from last 20 logs
        var seen = Set<String>()
        return recentLogs.prefix(50).filter { log in
            if seen.contains(log.foodName) { return false }
            seen.insert(log.foodName)
            return true
        }.prefix(10).map { $0 }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Recent Foods") {
                    if recentFoods.isEmpty {
                        Text("No recent foods")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(recentFoods, id: \.foodName) { food in
                            Button {
                                logFood(name: food.foodName, cal: food.calories, p: food.protein, c: food.carbs, f: food.fats, serving: food.servingSize)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(food.foodName).foregroundColor(.primary)
                                        Text("\(food.calories) kcal • P:\(Int(food.protein)) C:\(Int(food.carbs)) F:\(Int(food.fats))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
                
                Section("Quick Entry") {
                    TextField("Food name", text: $foodName)
                    
                    HStack {
                        Text("Serving (g)")
                        TextField("100", text: $servingSize)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Calories")
                        TextField("0", text: $calories)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Protein (g)")
                        TextField("0", text: $protein)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Carbs (g)")
                        TextField("0", text: $carbs)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Fats (g)")
                        TextField("0", text: $fats)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section {
                    Button {
                        logFood(
                            name: foodName,
                            cal: Int(calories) ?? 0,
                            p: Double(protein) ?? 0,
                            c: Double(carbs) ?? 0,
                            f: Double(fats) ?? 0,
                            serving: Double(servingSize) ?? 100
                        )
                    } label: {
                        HStack {
                            Spacer()
                            Label("Add to \(mealCategory.rawValue.capitalized)", systemImage: "plus.circle.fill")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(foodName.isEmpty)
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func logFood(name: String, cal: Int, p: Double, c: Double, f: Double, serving: Double) {
        let entry = FoodLog(
            timestamp: Date(),
            foodName: name,
            servingSize: serving,
            calories: cal,
            protein: p,
            carbs: c,
            fats: f,
            category: mealCategory
        )
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - App Intents for Siri & Shortcuts (iOS 16+)

import AppIntents

/// App Intent for logging food via Siri or Shortcuts
@available(iOS 16.0, *)
struct LogFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Food"
    static var description = IntentDescription("Quickly log a food item to your nutrition diary")
    
    // Opens app when invoked
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Food Name")
    var foodName: String?
    
    @Parameter(title: "Calories")
    var calories: Int?
    
    @Parameter(title: "Meal", default: .snack)
    var meal: MealCategoryEntity
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // This will open the app to the nutrition section
        // The actual food logging happens in the app UI
        return .result(dialog: "Opening IronFuel to log \(foodName ?? "food")...")
    }
}

/// Entity for meal category selection in Shortcuts
@available(iOS 16.0, *)
struct MealCategoryEntity: AppEntity {
    var id: String
    var name: String
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    static var defaultQuery = MealCategoryQuery()
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
    
    static let breakfast = MealCategoryEntity(id: "breakfast", name: "Breakfast")
    static let lunch = MealCategoryEntity(id: "lunch", name: "Lunch")
    static let dinner = MealCategoryEntity(id: "dinner", name: "Dinner")
    static let snack = MealCategoryEntity(id: "snack", name: "Snack")
    
    static let allCases: [MealCategoryEntity] = [.breakfast, .lunch, .dinner, .snack]
}

@available(iOS 16.0, *)
struct MealCategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [MealCategoryEntity] {
        MealCategoryEntity.allCases.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [MealCategoryEntity] {
        MealCategoryEntity.allCases
    }
}

/// Quick scan intent
@available(iOS 16.0, *)
struct ScanFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Food Barcode"
    static var description = IntentDescription("Open the barcode scanner to log food")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "Opening barcode scanner...")
    }
}

/// App Shortcuts provider - makes shortcuts available in Shortcuts app & Spotlight
@available(iOS 16.0, *)
struct IronFuelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log food in \(.applicationName)",
                "Add food to \(.applicationName)",
                "Track meal in \(.applicationName)",
                "Log my meal in \(.applicationName)"
            ],
            shortTitle: "Log Food",
            systemImageName: "fork.knife"
        )
        
        AppShortcut(
            intent: ScanFoodIntent(),
            phrases: [
                "Scan food in \(.applicationName)",
                "Scan barcode with \(.applicationName)"
            ],
            shortTitle: "Scan Barcode",
            systemImageName: "barcode.viewfinder"
        )
    }
}

// MARK: - Lock Screen Widget (WidgetKit)
// Note: This code needs to be in a separate Widget Extension target in Xcode
// The following is the complete widget code to add to your Widget Extension

/*
 * ===== WIDGET EXTENSION CODE =====
 * Create a new Widget Extension target in Xcode and add this code:
 * File: IronFuelWidget.swift
 */

import WidgetKit

// Widget Entry - the data displayed on the widget
struct NutritionWidgetEntry: TimelineEntry {
    let date: Date
    let caloriesConsumed: Int
    let caloriesTarget: Int
    let proteinConsumed: Double
    let proteinTarget: Int
    
    var caloriesRemaining: Int { max(0, caloriesTarget - caloriesConsumed) }
    var proteinRemaining: Double { max(0, Double(proteinTarget) - proteinConsumed) }
    var calorieProgress: Double { caloriesTarget > 0 ? min(1, Double(caloriesConsumed) / Double(caloriesTarget)) : 0 }
    var proteinProgress: Double { proteinTarget > 0 ? min(1, proteinConsumed / Double(proteinTarget)) : 0 }
}

// Widget Timeline Provider
struct NutritionWidgetProvider: TimelineProvider {
    typealias Entry = NutritionWidgetEntry
    
    func placeholder(in context: Context) -> NutritionWidgetEntry {
        NutritionWidgetEntry(
            date: Date(),
            caloriesConsumed: 1200,
            caloriesTarget: 2000,
            proteinConsumed: 80,
            proteinTarget: 150
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NutritionWidgetEntry) -> Void) {
        // For preview, use placeholder data
        completion(placeholder(in: context))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionWidgetEntry>) -> Void) {
        // In a real implementation, fetch from App Group shared container
        // For now, use sample data
        let entry = NutritionWidgetEntry(
            date: Date(),
            caloriesConsumed: 1200,
            caloriesTarget: 2000,
            proteinConsumed: 80,
            proteinTarget: 150
        )
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// Lock Screen Widget Views
struct NutritionLockScreenWidget: View {
    let entry: NutritionWidgetEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            // Circular lock screen widget
            Gauge(value: entry.calorieProgress) {
                Text("Cal")
                    .font(.caption2)
            } currentValueLabel: {
                Text("\(entry.caloriesRemaining)")
                    .font(.caption)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            
        case .accessoryRectangular:
            // Rectangular lock screen widget
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "flame.fill")
                    Text("\(entry.caloriesRemaining) cal left")
                        .font(.headline)
                }
                
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("\(Int(entry.proteinRemaining))g protein left")
                        .font(.caption)
                }
                
                ProgressView(value: entry.calorieProgress)
                    .tint(.orange)
            }
            
        case .accessoryInline:
            // Inline widget (single line on lock screen)
            Label("\(entry.caloriesRemaining) cal • \(Int(entry.proteinRemaining))g protein", systemImage: "fork.knife")
            
        default:
            Text("IronFuel")
        }
    }
}

// Widget Definition
struct IronFuelWidget: Widget {
    let kind: String = "IronFuelWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NutritionWidgetProvider()) { entry in
            NutritionLockScreenWidget(entry: entry)
        }
        .configurationDisplayName("Nutrition Tracker")
        .description("Track your remaining calories and protein from your lock screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - URL Scheme Handler for Widget Deep Links

extension ContentView {
    /// Handle deep links from widgets/shortcuts
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "ironfuel" else { return }
        
        switch url.host {
        case "addFood":
            // Navigate to nutrition tab and show quick add
            // This would set selectedTab = 2 and trigger the quick add sheet
            break
        case "scanFood":
            // Navigate to nutrition tab and show scanner
            break
        default:
            break
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
                .onAppear {
                    // Seed cheat meals database on first launch
                    let context = container.mainContext
                    CheatMealDatabase.seedDatabase(context: context)
                }
                .onOpenURL { url in
                    // Handle deep links from widgets
                    handleDeepLink(url)
                }
        }
        .modelContainer(container)
    }
    
    private func handleDeepLink(_ url: URL) {
        // Widget/Shortcut deep link handling
        // ironfuel://addFood, ironfuel://scanFood
        print("Deep link received: \(url)")
    }
}

