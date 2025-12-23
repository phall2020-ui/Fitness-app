import requests
import math
from datetime import datetime

BASE_URL = "http://localhost:8000"

def calculate_caloric_target(weight, height, age, gender, activity_level, goal_rate):
    # Mifflin-St Jeor
    if gender == 'male':
        bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5
    else:
        bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161
    
    tdee = bmr * activity_level
    kcal_per_kg = 7700.0
    daily_adjustment = (goal_rate * kcal_per_kg) / 7.0
    target = tdee + daily_adjustment
    return int(max(1200.0, round(target)))

def test_full_flow():
    print("--- Starting Full Flow Test ---")
    
    # 1. User Profile Setup
    profile = {
        "weight": 85.0,
        "height": 180.0,
        "age": 30,
        "gender": 'male',
        "activity_level": 1.55, # Moderately Active
        "goal_rate": -0.5 # Lose 0.5kg/week
    }
    
    target = calculate_caloric_target(**profile)
    print(f"Calculated Caloric Target: {target} kcal")
    
    expected_target = 2390 # (10*85 + 6.25*180 - 5*30 + 5) * 1.55 - (0.5 * 7700 / 7)
    # math: (850 + 1125 - 150 + 5) * 1.55 - 550 = 1830 * 1.55 - 550 = 2836.5 - 550 = 2286.5 -> 2287
    print(f"Manual check: (10*85 + 6.25*180 - 5*30 + 5) * 1.55 - 550 = {1830 * 1.55 - 550}")
    
    # 2. Food Search
    print("\nSearching for 'Oats'...")
    response = requests.get(f"{BASE_URL}/v1/foods/search", params={"query": "Oats", "limit": 3})
    if response.status_code == 200:
        results = response.json().get("results", [])
        print(f"Found {len(results)} results")
        for res in results:
            print(f" - {res['name']} ({res['gtin14']})")
    else:
        print(f"Search failed: {response.status_code}")

    # 3. Barcode Lookup (using a result from search or a known one)
    barcode = "06111242100992" # Perly
    print(f"\nLooking up barcode: {barcode}")
    response = requests.get(f"{BASE_URL}/v1/foods/gtin14/{barcode}")
    if response.status_code == 200:
        product = response.json()
        print(f"Product found: {product['name']} by {product['brand']}")
        print(f"Nutrients: {product['nutrients']}")
    else:
        print(f"Lookup failed: {response.status_code}")

    # 4. Simulate Logging
    if response.status_code == 200:
        logged_food = {
            "name": product['name'],
            "calories": product['nutrients']['kcalPer100g'],
            "protein": product['nutrients']['proteinPer100g'],
            "carbs": product['nutrients']['carbsPer100g'],
            "fats": product['nutrients']['fatPer100g'],
            "serving": 150 # 150g logged
        }
        
        # Scaling
        multiplier = logged_food['serving'] / 100.0
        total_kcal = int(logged_food['calories'] * multiplier)
        total_protein = logged_food['protein'] * multiplier
        
        print(f"\nLogged 150g of {logged_food['name']}")
        print(f"Calculated: {total_kcal} kcal, {total_protein:.1f}g Protein")
        
        remaining = target - total_kcal
        print(f"Remaining: {remaining} kcal")

if __name__ == "__main__":
    test_full_flow()
