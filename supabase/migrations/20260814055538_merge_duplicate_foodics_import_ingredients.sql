-- Cleanup for two raw-ingredient duplicates created by the Foodics
-- import (20260813184055): name-only matching missed these because the
-- Foodics label shares no text with the existing product's curated
-- name. Both confirmed safe to merge -- checked every FK-referencing
-- table (stock_ledger, sales_lines, product_aliases, etc.) and found
-- zero references to either shadow row outside recipe_lines.
--
-- 'صدور دجاج جاهزة' (شادو) -> 'Marinated Chicken Breast' (canonical):
-- the canonical row already had a recipe line on the 6 "...Sandwich"
-- items pre-dating this import; the shadow row's import-added lines on
-- those same 6 items are exact duplicates (dropped), while its lines on
-- the 6 "...Meal" items are new information (repointed, not dropped).
--
-- 'جبنة شيدر اصفر شرائح' (شادو) -> 'Cheddar Slices' (canonical): the
-- canonical row had zero prior recipe usage, so every shadow line is
-- new information and gets repointed with no duplicates to drop.
--
-- NOTE: 'خس ايسبرغ' and 'خس برجر' (also flagged in the import's
-- migration header as possible Lettuce duplicates) were investigated
-- and are NOT merged here -- they're used on entirely non-overlapping
-- menu items (iceberg on crispy-plate/wrap items, burger-lettuce on
-- burger items), indicating Foodics genuinely tracks them as distinct
-- ingredients. The old unused generic 'Lettuce' product is left as an
-- inactive-in-practice leftover.

DELETE FROM recipe_lines
WHERE component_product_id = '4179b6c5-e96d-4941-bf6b-80fdb54e65b5'
  AND parent_product_id IN (
    SELECT parent_product_id FROM recipe_lines WHERE component_product_id = 'aa182739-4235-4f91-8b96-2fd972a2bd78'
  );

UPDATE recipe_lines
SET component_product_id = 'aa182739-4235-4f91-8b96-2fd972a2bd78'
WHERE component_product_id = '4179b6c5-e96d-4941-bf6b-80fdb54e65b5';

DELETE FROM products WHERE id = '4179b6c5-e96d-4941-bf6b-80fdb54e65b5';

UPDATE products SET
  foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae',
  sku = COALESCE(sku, 'sk-0328'),
  recipe_unit = COALESCE(recipe_unit, 'جرام'),
  storage_to_recipe_factor = CASE WHEN recipe_unit IS NULL THEN 1000 ELSE storage_to_recipe_factor END
WHERE id = 'aa182739-4235-4f91-8b96-2fd972a2bd78';

UPDATE recipe_lines
SET component_product_id = '00688dbb-1d3a-4b88-8b0e-d04e8c0f70ad'
WHERE component_product_id = '6d676032-1e14-4bda-9983-17a57ffd9918';

DELETE FROM products WHERE id = '6d676032-1e14-4bda-9983-17a57ffd9918';

UPDATE products SET
  foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f',
  sku = COALESCE(sku, 'sk-0382'),
  recipe_unit = COALESCE(recipe_unit, 'سلايز'),
  storage_to_recipe_factor = CASE WHEN recipe_unit IS NULL THEN 87 ELSE storage_to_recipe_factor END
WHERE id = '00688dbb-1d3a-4b88-8b0e-d04e8c0f70ad';
