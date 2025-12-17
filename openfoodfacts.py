"""
OpenFoodFacts API client for fetching product data.
https://world.openfoodfacts.org/
"""
import httpx
from typing import Optional, List
from datetime import datetime

from models import FoodProductDTO, FoodNutrients


class OpenFoodFactsClient:
    """Client for the OpenFoodFacts API."""
    
    BASE_URL = "https://world.openfoodfacts.org/api/v2"
    
    def __init__(self):
        self.client = httpx.AsyncClient(
            timeout=10.0,
            headers={
                "User-Agent": "IronFuel-App/1.0 (contact@ironfuel.app)"
            }
        )
    
    async def get_product(self, barcode: str) -> Optional[FoodProductDTO]:
        """
        Fetch a product by barcode from OpenFoodFacts.
        
        Args:
            barcode: Product barcode (EAN-13, UPC-A, etc.)
        
        Returns:
            FoodProductDTO if found, None otherwise
        """
        try:
            url = f"{self.BASE_URL}/product/{barcode}"
            response = await self.client.get(url)
            
            if response.status_code != 200:
                return None
            
            data = response.json()
            
            if data.get("status") != 1:
                return None
            
            product = data.get("product", {})
            return self._parse_product(product, barcode)
            
        except Exception as e:
            print(f"OpenFoodFacts API error: {e}")
            return None
    
    async def search(self, query: str, limit: int = 10) -> List[FoodProductDTO]:
        """
        Search for products by name.
        
        Args:
            query: Search term
            limit: Maximum results
        
        Returns:
            List of matching products
        """
        try:
            url = f"{self.BASE_URL}/search"
            params = {
                "search_terms": query,
                "page_size": limit,
                "json": True
            }
            response = await self.client.get(url, params=params)
            
            if response.status_code != 200:
                return []
            
            data = response.json()
            products = data.get("products", [])
            
            results = []
            for p in products:
                barcode = p.get("code", "")
                if barcode:
                    parsed = self._parse_product(p, barcode)
                    if parsed:
                        results.append(parsed)
            
            return results
            
        except Exception as e:
            print(f"OpenFoodFacts search error: {e}")
            return []
    
    def _parse_product(self, product: dict, barcode: str) -> Optional[FoodProductDTO]:
        """Parse OpenFoodFacts product JSON into our DTO."""
        try:
            # Get nutrient data
            nutriments = product.get("nutriments", {})
            
            nutrients = FoodNutrients(
                kcalPer100g=self._safe_float(nutriments.get("energy-kcal_100g")),
                proteinPer100g=self._safe_float(nutriments.get("proteins_100g")),
                carbsPer100g=self._safe_float(nutriments.get("carbohydrates_100g")),
                fatPer100g=self._safe_float(nutriments.get("fat_100g")),
                fibrePer100g=self._safe_float(nutriments.get("fiber_100g"))
            )
            
            # Get serving size
            serving_size = None
            serving_desc = product.get("serving_size")
            if serving_desc:
                # Try to extract numeric value from serving size string
                import re
                match = re.search(r"(\d+(?:\.\d+)?)\s*g", serving_desc)
                if match:
                    serving_size = float(match.group(1))
            
            # Normalize barcode to GTIN-14
            gtin14 = barcode.zfill(14)
            
            return FoodProductDTO(
                gtin14=gtin14,
                name=product.get("product_name", product.get("product_name_en", "Unknown")),
                brand=product.get("brands"),
                imageURL=product.get("image_url"),
                servingSizeG=serving_size,
                servingDescription=serving_desc,
                nutrients=nutrients,
                source="OpenFoodFacts",
                lastVerifiedAt=datetime.utcnow()
            )
            
        except Exception as e:
            print(f"Error parsing product: {e}")
            return None
    
    @staticmethod
    def _safe_float(value) -> Optional[float]:
        """Safely convert a value to float."""
        if value is None:
            return None
        try:
            return float(value)
        except (ValueError, TypeError):
            return None
