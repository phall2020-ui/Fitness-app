"""
IronFuel Backend API
FastAPI server for food barcode lookup with OpenFoodFacts integration.
"""
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import uvicorn

from models import FoodProductDTO
from database import init_db, get_cached_product, cache_product
from openfoodfacts import OpenFoodFactsClient

# Initialize OpenFoodFacts client
off_client = OpenFoodFactsClient()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize database on startup."""
    init_db()
    yield


app = FastAPI(
    title="IronFuel Food API",
    description="Backend API for food barcode lookup. Integrates with OpenFoodFacts.",
    version="1.0.0",
    lifespan=lifespan
)

# Enable CORS for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to your app's domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    """Health check endpoint."""
    return {"status": "ok", "service": "IronFuel Food API"}


@app.get("/health")
async def health():
    """Detailed health check."""
    return {
        "status": "healthy",
        "database": "connected",
        "openfoodfacts": "available"
    }


@app.get("/v1/foods/gtin14/{gtin14}", response_model=FoodProductDTO)
async def get_food_by_gtin14(gtin14: str):
    """
    Lookup food product by GTIN-14 barcode.
    
    The barcode is normalized and looked up in:
    1. Local SQLite cache
    2. OpenFoodFacts API (if not cached)
    
    Results from OpenFoodFacts are cached for future lookups.
    
    Args:
        gtin14: The 14-digit GTIN barcode (or shorter UPC/EAN variants)
    
    Returns:
        FoodProductDTO with product details and nutrients
    
    Raises:
        404: Product not found in any data source
    """
    # Normalize barcode (strip leading zeros for lookup)
    normalized = gtin14.lstrip("0") or gtin14
    
    # Check local cache first
    cached = get_cached_product(gtin14)
    if cached:
        return cached
    
    # Lookup in OpenFoodFacts
    product = await off_client.get_product(normalized)
    
    if product is None:
        # Try with full GTIN-14
        product = await off_client.get_product(gtin14)
    
    if product is None:
        raise HTTPException(status_code=404, detail="Product not found")
    
    # Cache for future lookups
    cache_product(product)
    
    return product


@app.get("/v1/foods/search")
async def search_foods(query: str, limit: int = 10):
    """
    Search for foods by name (OpenFoodFacts text search).
    
    Args:
        query: Search term
        limit: Maximum results to return (default 10)
    
    Returns:
        List of matching products
    """
    results = await off_client.search(query, limit=limit)
    return {"results": results, "count": len(results)}


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
