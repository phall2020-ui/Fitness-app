"""
SQLite database for caching food products.
Reduces API calls to OpenFoodFacts by storing previously looked-up products.
"""
import sqlite3
import json
from typing import Optional
from datetime import datetime
from pathlib import Path

from models import FoodProductDTO, FoodNutrients

# Database file path
DB_PATH = Path(__file__).parent / "food_cache.db"


def get_connection() -> sqlite3.Connection:
    """Get a database connection."""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    """Initialize the database schema."""
    conn = get_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS food_products (
            gtin14 TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            brand TEXT,
            image_url TEXT,
            serving_size_g REAL,
            serving_description TEXT,
            kcal_per_100g REAL,
            protein_per_100g REAL,
            carbs_per_100g REAL,
            fat_per_100g REAL,
            fibre_per_100g REAL,
            source TEXT,
            last_verified_at TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Index for faster lookups
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_food_products_gtin14 
        ON food_products(gtin14)
    """)
    
    conn.commit()
    conn.close()
    print(f"Database initialized at {DB_PATH}")


def get_cached_product(gtin14: str) -> Optional[FoodProductDTO]:
    """
    Retrieve a cached product by GTIN-14.
    
    Args:
        gtin14: The product barcode
    
    Returns:
        FoodProductDTO if found, None otherwise
    """
    conn = get_connection()
    cursor = conn.cursor()
    
    cursor.execute(
        "SELECT * FROM food_products WHERE gtin14 = ?",
        (gtin14,)
    )
    row = cursor.fetchone()
    conn.close()
    
    if row is None:
        return None
    
    # Parse nutrients
    nutrients = FoodNutrients(
        kcalPer100g=row["kcal_per_100g"],
        proteinPer100g=row["protein_per_100g"],
        carbsPer100g=row["carbs_per_100g"],
        fatPer100g=row["fat_per_100g"],
        fibrePer100g=row["fibre_per_100g"]
    )
    
    # Parse datetime
    last_verified = None
    if row["last_verified_at"]:
        try:
            last_verified = datetime.fromisoformat(row["last_verified_at"])
        except ValueError:
            pass
    
    return FoodProductDTO(
        gtin14=row["gtin14"],
        name=row["name"],
        brand=row["brand"],
        imageURL=row["image_url"],
        servingSizeG=row["serving_size_g"],
        servingDescription=row["serving_description"],
        nutrients=nutrients,
        source=row["source"],
        lastVerifiedAt=last_verified
    )


def cache_product(product: FoodProductDTO):
    """
    Cache a product in the database.
    
    Args:
        product: The product to cache
    """
    conn = get_connection()
    cursor = conn.cursor()
    
    nutrients = product.nutrients or FoodNutrients()
    
    cursor.execute("""
        INSERT OR REPLACE INTO food_products (
            gtin14, name, brand, image_url,
            serving_size_g, serving_description,
            kcal_per_100g, protein_per_100g, carbs_per_100g,
            fat_per_100g, fibre_per_100g,
            source, last_verified_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        product.gtin14,
        product.name,
        product.brand,
        product.imageURL,
        product.servingSizeG,
        product.servingDescription,
        nutrients.kcalPer100g,
        nutrients.proteinPer100g,
        nutrients.carbsPer100g,
        nutrients.fatPer100g,
        nutrients.fibrePer100g,
        product.source,
        product.lastVerifiedAt.isoformat() if product.lastVerifiedAt else None
    ))
    
    conn.commit()
    conn.close()


def clear_cache():
    """Clear all cached products."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM food_products")
    conn.commit()
    conn.close()
