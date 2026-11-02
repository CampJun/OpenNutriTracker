# Food Catalogue

The foods a user can find and log by weight, and where their nutrient values come from.

## Language

**Staple Food**:
A single-ingredient food as purchased, before cooking: raw produce, meat and fish, dry grains and legumes, flours, dairy, oils, and similar. Anything cooked, prepared, or mixed is not a Staple Food.
_Avoid_: raw food, whole food, ingredient

**Edible Portion**:
The part of a food that is eaten, excluding bone, peel, pits, and other refuse. A Staple Food's nutrient values are stated per 100 g of Edible Portion, so a weighed amount scales them directly.
_Avoid_: serving, net weight

**Household Serving**:
A measure someone can actually take, such as a cup, a tablespoon, or one large egg, with its weight in grams of Edible Portion. It is a shortcut when no scale is at hand; grams are always the default.
_Avoid_: serving size, portion, RACC

## Relationships

- A **Staple Food** comes from USDA FoodData Central: from Foundation Foods when it exists there, otherwise from SR Legacy.
- A **Staple Food** has zero or more **Household Servings**.
- Food search finds **Staple Foods** and the user's own foods and recipes, nothing from the network.
