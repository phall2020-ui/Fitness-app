"""
Pydantic models matching the Swift FoodProductDTO and FoodNutrients structs.
"""
from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class FoodNutrients(BaseModel):
    """Nutritional information per 100g."""
    kcalPer100g: Optional[float] = None
    proteinPer100g: Optional[float] = None
    carbsPer100g: Optional[float] = None
    fatPer100g: Optional[float] = None
    fibrePer100g: Optional[float] = None


class FoodProductDTO(BaseModel):
    """
    Food product data transfer object.
    Matches the Swift FoodProductDTO struct exactly.
    """
    gtin14: str
    name: str
    brand: Optional[str] = None
    imageURL: Optional[str] = None
    servingSizeG: Optional[float] = None
    servingDescription: Optional[str] = None
    nutrients: Optional[FoodNutrients] = None
    source: Optional[str] = None
    lastVerifiedAt: Optional[datetime] = None

    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat() if v else None
        }


class FoodSearchResult(BaseModel):
    """Search result item."""
    gtin14: str
    name: str
    brand: Optional[str] = None
    imageURL: Optional[str] = None
