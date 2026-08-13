-- =====================================================================
-- Foodics -> Menu/Add-ons/Recipes one-time import script
-- Applied to Supabase project ebezknmbzpcdxgjjbomr (in chunks, without
-- the outer BEGIN/COMMIT, to avoid transcribing the whole ~427KB file
-- in one shot -- every statement is ON CONFLICT/NOT EXISTS-guarded so
-- this was safe; the BEGIN/COMMIT wrapper below is restored for a
-- clean single-transaction replay in a fresh environment). Verified
-- post-apply: 24 addon_categories, 119 addons, 121 menu items (301
-- products total), 321 recipe_lines, 292 product_locations, 119
-- addon_category_options, 111 product_addon_categories.
--
-- KNOWN LIMITATION: matching was name-text-based only (exact match
-- against products.name_en/name_ar or product_aliases.raw_name), so a
-- handful of raw ingredients whose existing product name doesn't share
-- text with Foodics' label were NOT matched and got a duplicate "shadow"
-- row instead (e.g. existing "Marinated Chicken Breast" vs a newly
-- created "صدور دجاج جاهزة" for the same real ingredient, both now on
-- Fluffy Burger Sandwich's recipe; likely also "Cheddar Slices" vs
-- "جبنة شيدر اصفر شرائح", and possibly "Lettuce" vs "خس ايسبرغ"/"خس
-- برجر"). Harmless today (no sale-triggered deduction is wired up yet),
-- but should be reconciled by an admin via the Menu/Add-ons pages
-- before that gets built, or duplicate raw ingredients will each need
-- separate stock tracking.
--
-- Source data snapshot: Foodics search_products (91 total / 73 active,
-- non-deleted), search_modifiers (33 groups / 24 active, 119 active
-- options), search_categories (14), search_branches (7 / 4 active).
--
-- Matching was performed against 104 existing `products` rows and 58
-- `product_aliases` rows pulled from Supabase read-only beforehand.
-- See the per-section comments below for match/create/ambiguous counts
-- and the list of cross-entity name collisions that were resolved by
-- priority (menu item > add-on > raw ingredient) - the losers of those
-- collisions are created as new, distinct product rows rather than
-- being (incorrectly) linked to an already-claimed existing row.
-- =====================================================================
--
-- ############################# AMBIGUOUS / MANUAL-REVIEW ITEMS #############################
-- The following Foodics entities name-collided with an existing product that had ALREADY been
-- claimed (linked) by a higher-priority entity (menu item > add-on > raw ingredient), or whose
-- existing match target looked like a different real-world item (type mismatch). Each was NOT
-- auto-linked; instead a new, distinct product row was created for it. A human should check
-- whether any of these are true duplicates of an existing product and should be merged by hand.
--   Existing product 'Sweet Potato Fries' (8042ee25-a628-457d-9fa3-01477705b51f) - kept linked to: menu_item:بطاطا حلوة (9be25b05-001d-4cda-b9e4-54e8a65f2b96)
--     -> created new instead of linking: addon:بطاطا حلوة (a10bf65f-86d9-4c2e-b1fd-3928eaf58eac)
--     -> created new instead of linking: raw_ingredient:بطاطا حلوة (9fde38ce-cd55-4a93-bc4b-0424fc61e868)
--   Existing product 'French Fries' (5fd96f77-01ab-417d-8aa4-82418ac15f63) - kept linked to: menu_item:فرينش فرايز (9be25b05-25c9-43e6-99d2-29cbf33100b7)
--     -> created new instead of linking: menu_item:فرينش فرايز (9e668078-4d84-459a-98a3-c45f0b3f7d3a)
--     -> created new instead of linking: addon:فرينش فرايز (9be26191-a117-4702-9e88-5cda0d556f7f)
--   Existing product 'Curly Fries' (700cda71-37dd-430b-825c-fde77cc8ad50) - kept linked to: menu_item:كيرلي فرايز (9be25b05-37fe-4551-9b90-aff8cb277d9b)
--     -> created new instead of linking: raw_ingredient:كيرلي فرايز (9fe0ee1c-af42-4ea1-8bd8-918c429244f2)
--   Existing product 'Crisscut Fries' (ec2cac43-f144-4716-bc2c-c4346c803bab) - kept linked to: menu_item:بطاطا كرسكت (9be25b05-4bfa-4856-83f0-3b1125700b06)
--     -> created new instead of linking: addon:بطاطا كرسكت (a10bf650-d960-4dff-8572-ec13f1e82bb5)
--     -> created new instead of linking: raw_ingredient:بطاطا كرسكت (9fe0ee61-1cb7-4df6-98f7-0da221aedb2e)
--   Existing product 'Potato Bread' (6c2ed003-dd2b-4944-811b-c73454ad38a4) - kept linked to: menu_item:خبزة بطاطا (9c4f4d23-4475-4740-b142-5bfc4e6fd671)
--     -> created new instead of linking: addon:خبزة بطاطا (9c4f4c36-ce23-49a5-9171-2c9ce1753d65)
--   Existing product 'Juice' (8461841b-1468-49da-8367-a7827585b4b5) - kept linked to: menu_item:عصير (9cbb9998-702a-42fc-87e1-088a06d371b1)
--     -> created new instead of linking: raw_ingredient:عصير (9fdf7216-0b0a-4270-bf2b-478dded24a6c)
--   Existing product 'Garlic Dip' (46b70933-5730-4b4e-9655-326337a5ffb1) - kept linked to: (none - manual override)
--     -> created new instead of linking: manual_override:مثومة (9e667f89-23d2-4645-bfda-5a7d59b7d731) - menu item 'مثومة' (sellable, priced) name-matches existing 'Garlic Dip' which is type=processed with no selling_price - looks like a different real-world item than the intended 'Garlic Dip Box' (ar: علبة مثومة); not auto-linked.
-- ##############################################################################################
-- =====================================================================

BEGIN;

-- =====================================================================
-- SECTION 1: RAW INGREDIENTS
-- 5 matched to existing products (backfilled below).
-- 31 created as new 'raw' products (includes ambiguous cases; see notes).
-- =====================================================================

-- --- 1a. Backfill existing products matched to a Foodics raw ingredient ---
-- Foodics ingredient 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) matched to existing product 'Tomatoes'
UPDATE products SET
  foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af',
  sku = COALESCE(sku, 'sk-0384'),
  recipe_unit = CASE WHEN recipe_unit IS NULL THEN 'جرام' ELSE recipe_unit END,
  storage_to_recipe_factor = CASE WHEN storage_to_recipe_factor IS NULL OR storage_to_recipe_factor = 1 THEN 1000 ELSE storage_to_recipe_factor END
WHERE id = 'e480feae-5033-467b-911a-cfe710ab3359';

-- Foodics ingredient 'تيركي' (9fdf82a7-a17d-4330-a700-8d4ae85086a4) matched to existing product 'Turkey'
UPDATE products SET
  foodics_id = '9fdf82a7-a17d-4330-a700-8d4ae85086a4',
  sku = COALESCE(sku, 'sk-0386'),
  recipe_unit = CASE WHEN recipe_unit IS NULL THEN 'جرام' ELSE recipe_unit END,
  storage_to_recipe_factor = CASE WHEN storage_to_recipe_factor IS NULL OR storage_to_recipe_factor = 1 THEN 1000 ELSE storage_to_recipe_factor END
WHERE id = '4d18acde-57b3-4f93-a906-49d7fb88c308';

-- Foodics ingredient 'روست بيف' (9fdf8836-85c7-4562-8888-e3c77418a505) matched to existing product 'Roast Beef'
UPDATE products SET
  foodics_id = '9fdf8836-85c7-4562-8888-e3c77418a505',
  sku = COALESCE(sku, 'sk-0388'),
  recipe_unit = CASE WHEN recipe_unit IS NULL THEN 'جرام' ELSE recipe_unit END,
  storage_to_recipe_factor = CASE WHEN storage_to_recipe_factor IS NULL OR storage_to_recipe_factor = 1 THEN 1000 ELSE storage_to_recipe_factor END
WHERE id = '5c8ffe99-e540-42db-9626-c497fed4919a';

-- Foodics ingredient 'خبز تورتيلا' (9fe0c99d-6f81-430b-ae85-f416c5c2df84) matched to existing product 'Tortilla Wraps'
UPDATE products SET
  foodics_id = '9fe0c99d-6f81-430b-ae85-f416c5c2df84',
  sku = COALESCE(sku, 'sk-0391'),
  recipe_unit = CASE WHEN recipe_unit IS NULL THEN 'حبة' ELSE recipe_unit END,
  storage_to_recipe_factor = CASE WHEN storage_to_recipe_factor IS NULL OR storage_to_recipe_factor = 1 THEN 17 ELSE storage_to_recipe_factor END
WHERE id = '8b123b54-3cdc-4512-a8a1-bd4cdbe8acf2';

-- Foodics ingredient 'خبزة بروستد' (9fe0d372-3fe4-4cd2-9475-370e0bac22bc) matched to existing product 'Broasted Bread'
UPDATE products SET
  foodics_id = '9fe0d372-3fe4-4cd2-9475-370e0bac22bc',
  sku = COALESCE(sku, 'sk-0394'),
  recipe_unit = CASE WHEN recipe_unit IS NULL THEN 'حبة' ELSE recipe_unit END,
  storage_to_recipe_factor = CASE WHEN storage_to_recipe_factor IS NULL OR storage_to_recipe_factor = 1 THEN 6 ELSE storage_to_recipe_factor END
WHERE id = 'b82de3c0-bf44-40da-9651-8deaac395707';

-- --- 1b. New raw ingredient products ---
-- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('كرسببي جاهز', 'كرسببي جاهز', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a', 'sk-0389', 'جرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('صدور دجاج جاهزة', 'صدور دجاج جاهزة', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fddf596-3bbe-4434-a440-dcc8d0c81cae', 'sk-0328', 'جرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('ورق صواني برجر 2000', 'ورق صواني برجر 2000', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fde09d0-2875-4bd5-b539-5677ecfacbdc', 'sk-0336', 'حبة', 2000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('ورق تغليف   950', 'ورق تغليف   950', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fde1774-8273-4bb0-a74c-718b81475982', 'sk-0337', 'ورقة', 950)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('علب برجر 120', 'علب برجر 120', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fde2bf6-0ad5-456c-9eea-17b3751fb209', 'sk-0348', 'حبة', 120)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('كياس سفري 150', 'كياس سفري 150', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fde31f5-c067-428c-b8c5-aa0034bed917', 'sk-0351', 'حبة', 150)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('خبز بطاطا  5 انش', 'خبز بطاطا  5 انش', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fdf763b-7de0-4f85-88e2-f947e3adc638', 'sk-0381', 'حبة', 1)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('جبنة شيدر اصفر شرائح', 'جبنة شيدر اصفر شرائح', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fdf76cd-292f-4443-8596-bf3418c5401f', 'sk-0382', 'سلايز', 87)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('خس برجر', 'خس برجر', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fdf776e-3aac-48ca-bb92-f5e67b7c758c', 'sk-0383', 'جرام', 200)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('صوص بجمبع الانواع', 'صوص بجمبع الانواع', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fe7fff8-d72c-431f-aacc-89eb5249f4d9', 'sk-0408', 'جرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('صحن مفتوح 250', 'صحن مفتوح 250', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fe8100a-d3b1-45e9-b13e-c23da7c4460f', 'sk-0409', 'حبة', 250)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'جرجير' (9fdf8262-2a7b-48a5-ae5e-3090533136ba)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('جرجير', 'جرجير', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fdf8262-2a7b-48a5-ae5e-3090533136ba', 'sk-0385', 'جرام', 100)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'مخلل خيار مقطع' (9fdf8801-a1b8-4808-a8ca-7397e1922e90)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('مخلل خيار مقطع', 'مخلل خيار مقطع', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fdf8801-a1b8-4808-a8ca-7397e1922e90', 'sk-0387', 'جرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('علب بطاطا برجر 750', 'علب بطاطا برجر 750', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fde22e9-cd29-41b0-994b-6ebc272fb82d', 'sk-0344', 'حبة', 750)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('ماتركس بكل الانواع', 'ماتركس بكل الانواع', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fde33c8-6609-4bf0-aa08-0cd11b814ceb', 'sk-0352', 'حبة', 24)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ', 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8', 'sk-0390', 'جرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'كياس شفاف مطبوعة' (9fecc602-5bd5-4c96-85ea-2b3e22762f94)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('كياس شفاف مطبوعة', 'كياس شفاف مطبوعة', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fecc602-5bd5-4c96-85ea-2b3e22762f94', 'sk-0423', 'غرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('علب صوص مشكل بالحبة جاهزة', 'علب صوص مشكل بالحبة جاهزة', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fe828c6-2352-4b59-8730-076f2faf5821', 'sk-0419', 'حبة', 1)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'لامبستون اصابع مزريلا' (9fe29b5a-3993-48fd-bcb7-4c994db6ff21)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('لامبستون اصابع مزريلا', 'لامبستون اصابع مزريلا', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fe29b5a-3993-48fd-bcb7-4c994db6ff21', 'sk-0402', 'حبة', 42)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'حلقات بصل' (9fe2b05a-663d-45c8-a0fb-9cf5108bf263)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('حلقات بصل', 'حلقات بصل', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fe2b05a-663d-45c8-a0fb-9cf5108bf263', 'sk-0404', 'حبة', 70)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'ناجتس شيدر حار 1 ك' (9fe29d9b-03d0-4a51-87f0-be00e863d5ad)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('ناجتس شيدر حار 1 ك', 'ناجتس شيدر حار 1 ك', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fe29d9b-03d0-4a51-87f0-be00e863d5ad', 'sk-0403', 'حبة', 48)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'عصير' (9fdf7216-0b0a-4270-bf2b-478dded24a6c)  -- AMBIGUOUS: name collided with another Foodics entity that already claimed the like-named existing product; created new instead. Please review for possible manual dedupe.
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('عصير', 'عصير', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fdf7216-0b0a-4270-bf2b-478dded24a6c', 'sk-0380', 'حبة', 27)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'خس ايسبرغ' (9fe0ca59-da4c-4534-a75e-b2a6b001db39)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('خس ايسبرغ', 'خس ايسبرغ', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fe0ca59-da4c-4534-a75e-b2a6b001db39', 'sk-0392', 'غرام', 200)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'صحن كرسبي  330 كرتونة' (9fea9c6b-456a-4d41-8f60-34421902e1dd)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('صحن كرسبي  330 كرتونة', 'صحن كرسبي  330 كرتونة', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fea9c6b-456a-4d41-8f60-34421902e1dd', 'sk-0421', 'كرتونة', 1)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'علب راب  500' (9fde207e-2b71-40e1-98aa-bb901310141a)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('علب راب  500', 'علب راب  500', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fde207e-2b71-40e1-98aa-bb901310141a', 'sk-0340', 'حبة', 500)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'سلطه علبة كولو سلوا' (9fddf68b-9ada-4da5-820c-181074ec3f40)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('سلطه علبة كولو سلوا', 'سلطه علبة كولو سلوا', 'raw', 'pcs', NULL, 0, true, NULL, NULL, false, false, '9fddf68b-9ada-4da5-820c-181074ec3f40', 'sk-0329', 'حبة', 1)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'بطاطا حلوة' (9fde38ce-cd55-4a93-bc4b-0424fc61e868)  -- AMBIGUOUS: name collided with another Foodics entity that already claimed the like-named existing product; created new instead. Please review for possible manual dedupe.
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('بطاطا حلوة', 'بطاطا حلوة', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fde38ce-cd55-4a93-bc4b-0424fc61e868', 'sk-0365', 'جرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'بطاطا زيجي' (9fe0ecf9-2cbd-412c-b29e-9d112e4df4d5)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('بطاطا زيجي', 'بطاطا زيجي', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fe0ecf9-2cbd-412c-b29e-9d112e4df4d5', 'sk-0397', 'جرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'بطاطا ويدجز' (9fe0edc1-ed5b-4323-92be-912a156a0b5a)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('بطاطا ويدجز', 'بطاطا ويدجز', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fe0edc1-ed5b-4323-92be-912a156a0b5a', 'sk-0399', 'جرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'كيرلي فرايز' (9fe0ee1c-af42-4ea1-8bd8-918c429244f2)  -- AMBIGUOUS: name collided with another Foodics entity that already claimed the like-named existing product; created new instead. Please review for possible manual dedupe.
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('كيرلي فرايز', 'كيرلي فرايز', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fe0ee1c-af42-4ea1-8bd8-918c429244f2', 'sk-0400', 'جرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- 'بطاطا كرسكت' (9fe0ee61-1cb7-4df6-98f7-0da221aedb2e)  -- AMBIGUOUS: name collided with another Foodics entity that already claimed the like-named existing product; created new instead. Please review for possible manual dedupe.
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku, recipe_unit, storage_to_recipe_factor)
VALUES ('بطاطا كرسكت', 'بطاطا كرسكت', 'raw', 'kg', NULL, 0, true, NULL, NULL, false, false, '9fe0ee61-1cb7-4df6-98f7-0da221aedb2e', 'sk-0401', 'جرام', 1000)
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  recipe_unit = COALESCE(products.recipe_unit, EXCLUDED.recipe_unit),
  storage_to_recipe_factor = CASE WHEN products.storage_to_recipe_factor IS NULL OR products.storage_to_recipe_factor = 1 THEN EXCLUDED.storage_to_recipe_factor ELSE products.storage_to_recipe_factor END;

-- =====================================================================
-- SECTION 2: ADD-ON CATEGORIES (24 active Foodics modifier groups)
-- All created/upserted by foodics_id (addon_categories has no separate
-- 'existing row' matching source per the spec - these are new to our schema).
-- =====================================================================

-- 'خيارات خبز الثوم المحمص' (a1f73c14-9878-4fd6-ac1b-f3ee01535ea8)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('خيارات خبز الثوم المحمص', 'خيارات خبز الثوم المحمص', 'a1f73c14-9878-4fd6-ac1b-f3ee01535ea8', true, true, 0)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'Sauces' (9be25b1c-8440-440f-8364-a7ee4981e7d9)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('Sauces', 'Sauces', '9be25b1c-8440-440f-8364-a7ee4981e7d9', true, true, 1)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'Crispy adds' (9be25b51-2dfc-47f4-b940-89bb7ebfdb71)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('Crispy adds', 'Crispy adds', '9be25b51-2dfc-47f4-b940-89bb7ebfdb71', true, true, 2)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'اضافات' (9be25ba9-57e5-44cf-9752-b4639fc3a294)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('اضافات', 'اضافات', '9be25ba9-57e5-44cf-9752-b4639fc3a294', true, true, 3)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'جايانت' (9be2606f-f35c-4ba9-95c8-396037dbebfc)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('جايانت', 'جايانت', '9be2606f-f35c-4ba9-95c8-396037dbebfc', true, true, 4)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'بدون' (9be25bb5-ba28-4be9-a970-0546f844d555)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('بدون', 'بدون', '9be25bb5-ba28-4be9-a970-0546f844d555', true, true, 5)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'Drinks' (9be6d07c-3b78-4eac-aa87-7a8856237153)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('Drinks', 'Drinks', '9be6d07c-3b78-4eac-aa87-7a8856237153', true, true, 6)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'Crispy Plate Options' (9d3c0d18-b434-48db-ba6c-b641004f3c34)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('Crispy Plate Options', 'Crispy Plate Options', '9d3c0d18-b434-48db-ba6c-b641004f3c34', true, true, 7)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'إضافات الراب' (9d6b13e7-839f-427e-b8cc-2265d9e49fda)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('إضافات الراب', 'إضافات الراب', '9d6b13e7-839f-427e-b8cc-2265d9e49fda', true, true, 8)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'الحجم' (9e667267-6704-4caf-88ba-a118c3b420c5)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('الحجم', 'الحجم', '9e667267-6704-4caf-88ba-a118c3b420c5', true, true, 9)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'اضافات بروستد' (9e667a0a-9187-43f7-aa8f-016d77cad146)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('اضافات بروستد', 'اضافات بروستد', '9e667a0a-9187-43f7-aa8f-016d77cad146', true, true, 10)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'انواع البيتزا' (9e6a53be-ce48-466b-8066-8654ca9eaa5e)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('انواع البيتزا', 'انواع البيتزا', '9e6a53be-ce48-466b-8066-8654ca9eaa5e', true, true, 11)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'نوع العجينة' (9e6e1dca-8729-4c2a-b813-2cdc8e1b8588)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('نوع العجينة', 'نوع العجينة', '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588', true, true, 12)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'درجة الحرارة' (9e700ef7-1945-41f8-a5ce-101a65fef015)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('درجة الحرارة', 'درجة الحرارة', '9e700ef7-1945-41f8-a5ce-101a65fef015', true, true, 13)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'حجم (المارغريتا)' (9e708e43-4574-483b-ab93-e4b2d6da1d52)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('حجم (المارغريتا)', 'حجم (المارغريتا)', '9e708e43-4574-483b-ab93-e4b2d6da1d52', true, true, 14)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'عرض ال3 بيتزا' (9e74941b-d5f6-4920-b649-7e1db55fad04)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('عرض ال3 بيتزا', 'عرض ال3 بيتزا', '9e74941b-d5f6-4920-b649-7e1db55fad04', true, true, 15)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'إضافات البيتزا' (9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('إضافات البيتزا', 'إضافات البيتزا', '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6', true, true, 16)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'بيتزا - بدون اضافة' (9e90bdc2-f696-4ab0-b63d-2f9786abeaf6)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('بيتزا - بدون اضافة', 'بيتزا - بدون اضافة', '9e90bdc2-f696-4ab0-b63d-2f9786abeaf6', true, true, 17)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'انواع البيتزا (صغير)' (9fb63379-cbe7-4686-b9f0-5c94a052a34d)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('انواع البيتزا (صغير)', 'انواع البيتزا (صغير)', '9fb63379-cbe7-4686-b9f0-5c94a052a34d', true, true, 18)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'انواع البيتزا (وسط)' (9fb63704-c43f-4e56-9d29-bb3cacf7fb76)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('انواع البيتزا (وسط)', 'انواع البيتزا (وسط)', '9fb63704-c43f-4e56-9d29-bb3cacf7fb76', true, true, 19)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'انواع البيتزا (كبير)' (9fb63a48-ed76-48e0-ae11-c84c375cb50d)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('انواع البيتزا (كبير)', 'انواع البيتزا (كبير)', '9fb63a48-ed76-48e0-ae11-c84c375cb50d', true, true, 20)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'أنواع الساندويشات' (a0df96aa-a269-4dcd-b69f-21db1f07a422)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('أنواع الساندويشات', 'أنواع الساندويشات', 'a0df96aa-a269-4dcd-b69f-21db1f07a422', true, true, 21)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'مقبلات' (a0df986d-df29-46ce-ba4a-e21bdaef36ae)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('مقبلات', 'مقبلات', 'a0df986d-df29-46ce-ba4a-e21bdaef36ae', true, true, 22)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- 'اضافات بوكس الجمعات - كرسبي' (a10bf5bf-8c1a-4ba0-8028-079a4dbced0f)
INSERT INTO addon_categories (name_en, name_ar, foodics_id, is_ready, active, sort_order)
VALUES ('اضافات بوكس الجمعات - كرسبي', 'اضافات بوكس الجمعات - كرسبي', 'a10bf5bf-8c1a-4ba0-8028-079a4dbced0f', true, true, 23)
ON CONFLICT (foodics_id) DO UPDATE SET
  name_en = EXCLUDED.name_en,
  name_ar = EXCLUDED.name_ar,
  is_ready = EXCLUDED.is_ready,
  active = true,
  sort_order = EXCLUDED.sort_order;

-- =====================================================================
-- SECTION 3: ADD-ONS (119 active Foodics modifier options)
-- 0 matched to existing products (backfilled below).
-- 119 created as new 'sellable' is_addon=true products (includes ambiguous cases; see notes).
-- =====================================================================

-- --- 3a. Backfill existing products matched to a Foodics add-on option ---
-- --- 3b. New add-on products ---
-- 'اضافة جبنة' (a1f73c46-2447-4ff5-9094-694315d23af3)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('اضافة جبنة', 'اضافة جبنة', 'sellable', 'pcs', NULL, 0, true, NULL, 0.5, true, false, 'a1f73c46-2447-4ff5-9094-694315d23af3', 'sk-0176')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بافلو صوص' (9be26191-cdc3-4e73-9ec3-ff3b2a1672be)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بافلو صوص', 'بافلو صوص', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-cdc3-4e73-9ec3-ff3b2a1672be', 'modi-018')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'تشيلي صوص' (9be26191-d6c3-4bd4-a3fe-c9929fc8e179)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('تشيلي صوص', 'تشيلي صوص', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-d6c3-4bd4-a3fe-c9929fc8e179', 'modi-019')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'سويت تشيلي صوص' (9be26191-df30-44dc-9747-1c6bce27abbb)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('سويت تشيلي صوص', 'سويت تشيلي صوص', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-df30-44dc-9747-1c6bce27abbb', 'modi-020')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'هني ماسترد صوص' (9be26191-e7a1-4f30-9a9c-5a72d9b64c5b)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('هني ماسترد صوص', 'هني ماسترد صوص', 'sellable', 'pcs', NULL, 0, false, NULL, 0, true, false, '9be26191-e7a1-4f30-9a9c-5a72d9b64c5b', 'modi-021')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'باربيكيو  صوص' (9be26191-efe0-4d11-b8b4-1a1f5dc1559e)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('باربيكيو  صوص', 'باربيكيو  صوص', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-efe0-4d11-b8b4-1a1f5dc1559e', 'modi-022')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'رانش صوص' (9be26191-f822-464e-8960-412fce9e81d3)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('رانش صوص', 'رانش صوص', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-f822-464e-8960-412fce9e81d3', 'modi-023')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'فلافي صوص' (9be26192-000e-4ae0-a4bc-9f93a0a116ba)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('فلافي صوص', 'فلافي صوص', 'sellable', 'pcs', NULL, 0, false, NULL, 0, true, false, '9be26192-000e-4ae0-a4bc-9f93a0a116ba', 'modi-024')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'إضافة قطعة' (9be26191-c56a-4f66-a605-ac56deebb81a)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('إضافة قطعة', 'إضافة قطعة', 'sellable', 'pcs', NULL, 0, true, NULL, 1.1, true, false, '9be26191-c56a-4f66-a605-ac56deebb81a', 'modi-029')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'خبزة بطاطا' (9c4f4c36-ce23-49a5-9171-2c9ce1753d65)  -- AMBIGUOUS: name collided with another Foodics entity that already claimed the like-named existing product; created new instead. Please review for possible manual dedupe.
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('خبزة بطاطا', 'خبزة بطاطا', 'sellable', 'pcs', NULL, 0, true, NULL, 0.25, true, false, '9c4f4c36-ce23-49a5-9171-2c9ce1753d65', 'sk-0046')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'CUT' (9be26191-68fc-4b91-9f8c-6a0edfef92fe)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('CUT', 'CUT', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-68fc-4b91-9f8c-6a0edfef92fe', 'modi-028')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'اكسترا تشيز' (9be26191-7391-461d-9ae1-ccbe2b7604ea)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('اكسترا تشيز', 'اكسترا تشيز', 'sellable', 'pcs', NULL, 0, true, NULL, 0.25, true, false, '9be26191-7391-461d-9ae1-ccbe2b7604ea', 'modi-009')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'زيادة صوص' (9be26191-7df9-488f-a38a-daf024599397)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('زيادة صوص', 'زيادة صوص', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-7df9-488f-a38a-daf024599397', 'modi-010')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بطاطا حلوة - تبديل' (9be26191-86a5-4c24-9faa-2afcc0d0af4a)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بطاطا حلوة - تبديل', 'بطاطا حلوة - تبديل', 'sellable', 'pcs', NULL, 0, true, NULL, 0.8, true, false, '9be26191-86a5-4c24-9faa-2afcc0d0af4a', 'modi-011')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بطاطا زيجي - تبديل' (9be26191-8e9e-4054-bf7b-bd7ec6423818)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بطاطا زيجي - تبديل', 'بطاطا زيجي - تبديل', 'sellable', 'pcs', NULL, 0, true, NULL, 0.8, true, false, '9be26191-8e9e-4054-bf7b-bd7ec6423818', 'modi-012')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بطاطا ديبرز - تبديل' (9be26191-9933-4087-b144-91f95a864324)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بطاطا ديبرز - تبديل', 'بطاطا ديبرز - تبديل', 'sellable', 'pcs', NULL, 0, true, NULL, 0.8, true, false, '9be26191-9933-4087-b144-91f95a864324', 'modi-013')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'فرينش فرايز' (9be26191-a117-4702-9e88-5cda0d556f7f)  -- AMBIGUOUS: name collided with another Foodics entity that already claimed the like-named existing product; created new instead. Please review for possible manual dedupe.
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('فرينش فرايز', 'فرينش فرايز', 'sellable', 'pcs', NULL, 0, true, NULL, 0.8, true, false, '9be26191-a117-4702-9e88-5cda0d556f7f', 'modi-014')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بطاطا ويدجز - تبديل' (9be26191-a97d-4f06-bf55-5402ee08170b)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بطاطا ويدجز - تبديل', 'بطاطا ويدجز - تبديل', 'sellable', 'pcs', NULL, 0, true, NULL, 0.25, true, false, '9be26191-a97d-4f06-bf55-5402ee08170b', 'modi-015')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'كيرلي فرايز - تبديل' (9be26191-b106-4750-8f38-57a9f9d0d5e4)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('كيرلي فرايز - تبديل', 'كيرلي فرايز - تبديل', 'sellable', 'pcs', NULL, 0, true, NULL, 0.8, true, false, '9be26191-b106-4750-8f38-57a9f9d0d5e4', 'modi-016')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بطاطا كرسكت - تبديل' (9be26191-bd6e-467a-8565-f2d9de750aeb)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بطاطا كرسكت - تبديل', 'بطاطا كرسكت - تبديل', 'sellable', 'pcs', NULL, 0, true, NULL, 0.8, true, false, '9be26191-bd6e-467a-8565-f2d9de750aeb', 'modi-017')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'جبنة سائلة' (9d4438d3-22bf-4d0a-9331-c117a5860577)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('جبنة سائلة', 'جبنة سائلة', 'sellable', 'pcs', NULL, 0, true, NULL, 0.55, true, false, '9d4438d3-22bf-4d0a-9331-c117a5860577', 'sk-0056')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'جاينت فلافي' (9be26192-0781-4a2b-8dfc-b70aa309103f)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('جاينت فلافي', 'جاينت فلافي', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26192-0781-4a2b-8dfc-b70aa309103f', 'modi-025')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'جاينت كلاسيك' (9be26192-0ebf-4edf-a15d-b7ca4f4127f4)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('جاينت كلاسيك', 'جاينت كلاسيك', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26192-0ebf-4edf-a15d-b7ca4f4127f4', 'modi-026')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'جاينت بي' (9be26192-166b-44e7-ac70-687d61cec7ca)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('جاينت بي', 'جاينت بي', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26192-166b-44e7-ac70-687d61cec7ca', 'modi-027')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'جاينت سويت هيت' (9cb9af07-448c-44e1-aa1f-42eb3f71759a)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('جاينت سويت هيت', 'جاينت سويت هيت', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9cb9af07-448c-44e1-aa1f-42eb3f71759a', 'sk-0050')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون مخلل' (9be26191-1f8a-4f32-b226-8c3f432d3cca)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون مخلل', 'بدون مخلل', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-1f8a-4f32-b226-8c3f432d3cca', 'modi-001')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون بندورة' (9be26191-3157-45c7-adb6-07e74e2f3e6c)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون بندورة', 'بدون بندورة', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-3157-45c7-adb6-07e74e2f3e6c', 'modi-002')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون خس' (9be26191-3930-4aa2-ae98-418c8dc5391a)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون خس', 'بدون خس', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-3930-4aa2-ae98-418c8dc5391a', 'modi-003')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون جرجير' (9be26191-40f5-4dec-9492-353c49187962)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون جرجير', 'بدون جرجير', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-40f5-4dec-9492-353c49187962', 'modi-004')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون جبنة' (9be26191-4908-461c-9eaa-d3a887e7cdbc)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون جبنة', 'بدون جبنة', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-4908-461c-9eaa-d3a887e7cdbc', 'modi-005')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون تيركي' (9be26191-51c3-43a4-a5b2-30dbc46e9b0c)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون تيركي', 'بدون تيركي', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-51c3-43a4-a5b2-30dbc46e9b0c', 'modi-006')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون روست بيف' (9be26191-596e-43c5-a97e-dd2b840e72a0)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون روست بيف', 'بدون روست بيف', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-596e-43c5-a97e-dd2b840e72a0', 'modi-007')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون صوص' (9be26191-615e-43f1-8fa1-4866cfc869d1)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون صوص', 'بدون صوص', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be26191-615e-43f1-8fa1-4866cfc869d1', 'modi-008')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'Cola' (9be6d0d7-262c-4837-a018-b7317c92e981)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('Cola', 'Cola', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be6d0d7-262c-4837-a018-b7317c92e981', 'sk-0030')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'Fanta' (9be6d0ec-d68f-40a1-a70a-281e074417d0)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('Fanta', 'Fanta', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be6d0ec-d68f-40a1-a70a-281e074417d0', 'sk-0031')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'Sprite' (9be6d210-9652-43ff-852a-8b44cbaa6f24)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('Sprite', 'Sprite', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be6d210-9652-43ff-852a-8b44cbaa6f24', 'sk-0032')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'Cola Zero' (9be6d248-e932-4d78-a238-35626ee79ab3)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('Cola Zero', 'Cola Zero', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be6d248-e932-4d78-a238-35626ee79ab3', 'sk-0033')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'Diet sprite' (9be6d26f-9442-420c-90ff-43b5e4523849)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('Diet sprite', 'Diet sprite', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9be6d26f-9442-420c-90ff-43b5e4523849', 'sk-0034')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'Spicy (chilli, Honey Master & pickles)' (9d3c0d6e-363c-49a7-bdfc-7982aff41587)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('Spicy (chilli, Honey Master & pickles)', 'Spicy (chilli, Honey Master & pickles)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9d3c0d6e-363c-49a7-bdfc-7982aff41587', 'sk-0053')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'Classic (Ranch)' (9d3c0dc7-298e-4a20-9d12-07d0eacd432c)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('Classic (Ranch)', 'Classic (Ranch)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9d3c0dc7-298e-4a20-9d12-07d0eacd432c', 'sk-0054')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون تشيلي' (9db22619-6ad2-45fa-a48b-2fa3e88a04c2)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون تشيلي', 'بدون تشيلي', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9db22619-6ad2-45fa-a48b-2fa3e88a04c2', 'sk-0064')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'حار' (9d6b1421-80a7-4d75-95bd-692a9fb820c1)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('حار', 'حار', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9d6b1421-80a7-4d75-95bd-692a9fb820c1', 'sk-0060')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'عادي - رانش' (9d6b1450-6978-4cf7-82bf-6dd28ce0d859)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('عادي - رانش', 'عادي - رانش', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9d6b1450-6978-4cf7-82bf-6dd28ce0d859', 'sk-0061')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'حار حلو' (9d6c68f0-aae0-4499-b04f-c7c7c2088ec8)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('حار حلو', 'حار حلو', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9d6c68f0-aae0-4499-b04f-c7c7c2088ec8', 'sk-0062')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'عادي - هني ماسترد' (9d6cad0d-a3f4-4d7b-a3e5-412e34935ae8)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('عادي - هني ماسترد', 'عادي - هني ماسترد', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9d6cad0d-a3f4-4d7b-a3e5-412e34935ae8', 'sk-0063')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا صغير' (9e6672cf-f6da-4d60-95c0-8229a8da58e3)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا صغير', 'بيتزا صغير', 'sellable', 'pcs', NULL, 0, true, NULL, 2.7, true, false, '9e6672cf-f6da-4d60-95c0-8229a8da58e3', 'sk-0066')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا وسط' (9e667310-d243-44a0-bdd1-ba69a8a0776e)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا وسط', 'بيتزا وسط', 'sellable', 'pcs', NULL, 0, true, NULL, 4.85, true, false, '9e667310-d243-44a0-bdd1-ba69a8a0776e', 'sk-0067')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا كبير' (9e667337-cb31-4395-a302-bcdbad7cb551)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا كبير', 'بيتزا كبير', 'sellable', 'pcs', NULL, 0, true, NULL, 7.3, true, false, '9e667337-cb31-4395-a302-bcdbad7cb551', 'sk-0068')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا صغير +' (9e6673e0-e082-4fce-97f5-467cd6425eef)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا صغير +', 'بيتزا صغير +', 'sellable', 'pcs', NULL, 0, true, NULL, 3, true, false, '9e6673e0-e082-4fce-97f5-467cd6425eef', 'sk-0070')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا وسط +' (9e667409-a553-45ed-a5b0-6e21c1c6f969)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا وسط +', 'بيتزا وسط +', 'sellable', 'pcs', NULL, 0, true, NULL, 5.15, true, false, '9e667409-a553-45ed-a5b0-6e21c1c6f969', 'sk-0071')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا كبير +' (9e667437-c90f-4e68-84b5-886f45d299c7)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا كبير +', 'بيتزا كبير +', 'sellable', 'pcs', NULL, 0, true, NULL, 8.1, true, false, '9e667437-c90f-4e68-84b5-886f45d299c7', 'sk-0072')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'كولسلو اضافية' (9e667a7d-dbe8-45db-80e2-20983ddc66f4)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('كولسلو اضافية', 'كولسلو اضافية', 'sellable', 'pcs', NULL, 0, true, NULL, 0.55, true, false, '9e667a7d-dbe8-45db-80e2-20983ddc66f4', 'sk-0078')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'مثومة اضافية' (9e667aa6-66fb-448c-bff1-a1d02093b933)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('مثومة اضافية', 'مثومة اضافية', 'sellable', 'pcs', NULL, 0, true, NULL, 0.4, true, false, '9e667aa6-66fb-448c-bff1-a1d02093b933', 'sk-0079')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'فرينش فرايز اضافية' (9e667ad1-2caf-4274-a58c-8c1d66a121a8)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('فرينش فرايز اضافية', 'فرينش فرايز اضافية', 'sellable', 'pcs', NULL, 0, true, NULL, 1, true, false, '9e667ad1-2caf-4274-a58c-8c1d66a121a8', 'sk-0080')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'خبزة للبروستد اضافية' (9e667eb3-7f96-4a9b-a42d-eaa0a3f758df)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('خبزة للبروستد اضافية', 'خبزة للبروستد اضافية', 'sellable', 'pcs', NULL, 0, true, NULL, 0.15, true, false, '9e667eb3-7f96-4a9b-a42d-eaa0a3f758df', 'sk-0083')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا الفريدو' (9e6a53ec-d339-4689-834a-5a168cd167ff)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا الفريدو', 'بيتزا الفريدو', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e6a53ec-d339-4689-834a-5a168cd167ff', 'sk-0091')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا خضار' (9e6a540f-20e2-4273-a79d-e312719a724e)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا خضار', 'بيتزا خضار', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e6a540f-20e2-4273-a79d-e312719a724e', 'sk-0092')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا سوبر سوبريم' (9e6a5427-507c-4987-8361-2254cc639661)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا سوبر سوبريم', 'بيتزا سوبر سوبريم', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e6a5427-507c-4987-8361-2254cc639661', 'sk-0093')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا مارغريتا' (9e6a543d-d0e5-4fc7-addf-7312842ed072)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا مارغريتا', 'بيتزا مارغريتا', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e6a543d-d0e5-4fc7-addf-7312842ed072', 'sk-0094')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا باباروني' (9e6a5459-4aad-4fcc-b9f9-5ba6cdfab9b8)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا باباروني', 'بيتزا باباروني', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e6a5459-4aad-4fcc-b9f9-5ba6cdfab9b8', 'sk-0095')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا تشيلي بي' (9ecea5e8-1bfa-47e2-a373-1875ebd09522)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا تشيلي بي', 'بيتزا تشيلي بي', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9ecea5e8-1bfa-47e2-a373-1875ebd09522', 'sk-0118')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا ببروني' (9fb5a8f8-32b0-4e63-88f5-dacf3b549cb0)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا ببروني', 'بيتزا ببروني', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb5a8f8-32b0-4e63-88f5-dacf3b549cb0', 'sk-0123')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'عجينة فورية' (9e6e1dde-2954-47d2-b7da-cbccbb2d0a6c)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('عجينة فورية', 'عجينة فورية', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e6e1dde-2954-47d2-b7da-cbccbb2d0a6c', 'sk-0097')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'عجينة مخمرة' (9e6e1df2-5c75-4967-9859-b8edd07be67a)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('عجينة مخمرة', 'عجينة مخمرة', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e6e1df2-5c75-4967-9859-b8edd07be67a', 'sk-0098')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'حار' (9e700f06-fac6-443c-abb1-3b8c81c269e2)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('حار', 'حار', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e700f06-fac6-443c-abb1-3b8c81c269e2', 'sk-0099')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'عادي' (9e700f16-b0be-47f4-b64d-aff0255f2e72)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('عادي', 'عادي', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e700f16-b0be-47f4-b64d-aff0255f2e72', 'sk-0100')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'مكس' (9e700f6f-34ea-4170-b360-47d2d69e6b01)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('مكس', 'مكس', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e700f6f-34ea-4170-b360-47d2d69e6b01', 'sk-0101')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا صغير-' (9e708e9c-9537-45e9-88c6-4adb50edbfb1)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا صغير-', 'بيتزا صغير-', 'sellable', 'pcs', NULL, 0, true, NULL, 2.15, true, false, '9e708e9c-9537-45e9-88c6-4adb50edbfb1', 'sk-0102')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا وسط -' (9e708f0e-b09f-4833-836f-927ddf8815b9)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا وسط -', 'بيتزا وسط -', 'sellable', 'pcs', NULL, 0, true, NULL, 4.3, true, false, '9e708f0e-b09f-4833-836f-927ddf8815b9', 'sk-0103')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'حجم كبير -' (9e708f34-4f95-425e-b027-63e806bf4ef6)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('حجم كبير -', 'حجم كبير -', 'sellable', 'pcs', NULL, 0, true, NULL, 6.5, true, false, '9e708f34-4f95-425e-b027-63e806bf4ef6', 'sk-0104')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- '3 كبير' (9e749446-bfc5-4d67-b2ef-16da8e5c09c8)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('3 كبير', '3 كبير', 'sellable', 'pcs', NULL, 0, true, NULL, 16.75, true, false, '9e749446-bfc5-4d67-b2ef-16da8e5c09c8', 'sk-0108')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- '3 وسط' (9e749472-77f8-4b2c-98d3-ca3c0ecf1d33)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('3 وسط', '3 وسط', 'sellable', 'pcs', NULL, 0, true, NULL, 13, true, false, '9e749472-77f8-4b2c-98d3-ca3c0ecf1d33', 'sk-0109')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- '3 صغير' (9e749498-f625-4f2d-9c71-17085b795935)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('3 صغير', '3 صغير', 'sellable', 'pcs', NULL, 0, true, NULL, 6.5, true, false, '9e749498-f625-4f2d-9c71-17085b795935', 'sk-0110')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'حشوات الاطراف وسط' (9e7cbc63-475b-456e-910e-142e1bd058fc)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('حشوات الاطراف وسط', 'حشوات الاطراف وسط', 'sellable', 'pcs', NULL, 0, true, NULL, 1, true, false, '9e7cbc63-475b-456e-910e-142e1bd058fc', 'sk-0112')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'حشوات الاطراف كبير' (9e7cbc92-5e83-4cd6-80e7-be07cec1bc00)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('حشوات الاطراف كبير', 'حشوات الاطراف كبير', 'sellable', 'pcs', NULL, 0, true, NULL, 1.6, true, false, '9e7cbc92-5e83-4cd6-80e7-be07cec1bc00', 'sk-0113')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون بصل' (9e90bdd9-1dad-4631-b7fd-096a719fe99f)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون بصل', 'بدون بصل', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e90bdd9-1dad-4631-b7fd-096a719fe99f', 'sk-0114')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون فطر' (9e90bdec-89cb-4669-92de-04c413dce6e5)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون فطر', 'بدون فطر', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e90bdec-89cb-4669-92de-04c413dce6e5', 'sk-0115')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون زيتون' (9e90be1c-1011-46e9-8864-b72f9cab8e83)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون زيتون', 'بدون زيتون', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9e90be1c-1011-46e9-8864-b72f9cab8e83', 'sk-0116')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بدون هالابينو' (9fb59fdf-9a99-47a5-9bad-04eb87909fb5)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بدون هالابينو', 'بدون هالابينو', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb59fdf-9a99-47a5-9bad-04eb87909fb5', 'sk-0122')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا سوبر سوبريم (S)' (9fb63476-3190-4cc4-b8b0-dcfc1b810aaf)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا سوبر سوبريم (S)', 'بيتزا سوبر سوبريم (S)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb63476-3190-4cc4-b8b0-dcfc1b810aaf', 'sk-0125')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا باباروني (S)' (9fb634a4-1ff0-409e-9028-fa8e668284da)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا باباروني (S)', 'بيتزا باباروني (S)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb634a4-1ff0-409e-9028-fa8e668284da', 'sk-0126')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا مارغريتا (S)' (9fb634ce-ee60-4b6b-b2e3-2e270a1b18ca)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا مارغريتا (S)', 'بيتزا مارغريتا (S)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb634ce-ee60-4b6b-b2e3-2e270a1b18ca', 'sk-0127')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا خضار  (S)' (9fb634f2-605b-44de-b242-e92c3737eb52)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا خضار  (S)', 'بيتزا خضار  (S)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb634f2-605b-44de-b242-e92c3737eb52', 'sk-0128')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا الفريدو (S)' (9fb6352d-7580-410c-b91b-6e699d76bb3b)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا الفريدو (S)', 'بيتزا الفريدو (S)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.3, true, false, '9fb6352d-7580-410c-b91b-6e699d76bb3b', 'sk-0129')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا باربيكيو (S)' (9fb63583-6615-4f63-9c3c-ba7d2e21eb85)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا باربيكيو (S)', 'بيتزا باربيكيو (S)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb63583-6615-4f63-9c3c-ba7d2e21eb85', 'sk-0130')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا تشيلي بي (S)' (9fb635b5-4580-47d5-9183-5cacf04165e8)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا تشيلي بي (S)', 'بيتزا تشيلي بي (S)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.3, true, false, '9fb635b5-4580-47d5-9183-5cacf04165e8', 'sk-0131')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا فلافي (S)' (9fb635e2-ca4e-4a59-bded-17bddadeba1c)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا فلافي (S)', 'بيتزا فلافي (S)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.3, true, false, '9fb635e2-ca4e-4a59-bded-17bddadeba1c', 'sk-0132')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا رانش (S)' (9fb63612-1df7-41c1-be6e-9248dbb4a4fe)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا رانش (S)', 'بيتزا رانش (S)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.3, true, false, '9fb63612-1df7-41c1-be6e-9248dbb4a4fe', 'sk-0133')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا سوبر سوبريم (M)' (9fb63758-7544-4986-be6a-03734f330773)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا سوبر سوبريم (M)', 'بيتزا سوبر سوبريم (M)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb63758-7544-4986-be6a-03734f330773', 'sk-0135')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا باباروني (M)' (9fb6377a-9047-442b-a27a-e663e810792e)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا باباروني (M)', 'بيتزا باباروني (M)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb6377a-9047-442b-a27a-e663e810792e', 'sk-0136')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا مارغريتا (M)' (9fb63826-e19b-4c19-b245-e9328d171743)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا مارغريتا (M)', 'بيتزا مارغريتا (M)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb63826-e19b-4c19-b245-e9328d171743', 'sk-0137')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا خضار (M)' (9fb6383a-57d2-455f-9e39-9260492d7adb)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا خضار (M)', 'بيتزا خضار (M)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb6383a-57d2-455f-9e39-9260492d7adb', 'sk-0138')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا الفريدو (M)' (9fb63854-3ab0-4755-bbc6-84770f1e4292)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا الفريدو (M)', 'بيتزا الفريدو (M)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.55, true, false, '9fb63854-3ab0-4755-bbc6-84770f1e4292', 'sk-0139')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا باربيكيو (M)' (9fb6386f-b517-4e2b-884e-bc06c717d394)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا باربيكيو (M)', 'بيتزا باربيكيو (M)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb6386f-b517-4e2b-884e-bc06c717d394', 'sk-0140')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا تشيلي بي (M)' (9fb6388f-eba9-4bf8-a86e-34f89643dc12)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا تشيلي بي (M)', 'بيتزا تشيلي بي (M)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.55, true, false, '9fb6388f-eba9-4bf8-a86e-34f89643dc12', 'sk-0141')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا فلافي (M)' (9fb638a1-ddc9-48ca-b3df-09092dff5361)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا فلافي (M)', 'بيتزا فلافي (M)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.55, true, false, '9fb638a1-ddc9-48ca-b3df-09092dff5361', 'sk-0142')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا رانش (M)' (9fb638bf-6b76-434a-bcf4-064372078fc3)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا رانش (M)', 'بيتزا رانش (M)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.55, true, false, '9fb638bf-6b76-434a-bcf4-064372078fc3', 'sk-0143')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا سوبر سوبريم (L)' (9fb63a71-f7a6-42fa-835f-cfe1ceccf0db)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا سوبر سوبريم (L)', 'بيتزا سوبر سوبريم (L)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb63a71-f7a6-42fa-835f-cfe1ceccf0db', 'sk-0145')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا باباروني (L)' (9fb63a8b-11a9-4dd0-a987-2a5fe8f42fe6)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا باباروني (L)', 'بيتزا باباروني (L)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb63a8b-11a9-4dd0-a987-2a5fe8f42fe6', 'sk-0146')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا مارغريتا (L)' (9fb63aa5-aaad-4a33-8060-a1c9cb144f39)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا مارغريتا (L)', 'بيتزا مارغريتا (L)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb63aa5-aaad-4a33-8060-a1c9cb144f39', 'sk-0147')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا خضار (L)' (9fb63abd-cb4a-4088-b8ec-1e466fc58e7b)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا خضار (L)', 'بيتزا خضار (L)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb63abd-cb4a-4088-b8ec-1e466fc58e7b', 'sk-0148')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا الفريدو (L)' (9fb63ad6-67c7-4adc-8b55-6314e91b6bb4)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا الفريدو (L)', 'بيتزا الفريدو (L)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.8, true, false, '9fb63ad6-67c7-4adc-8b55-6314e91b6bb4', 'sk-0149')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا باربيكيو (L)' (9fb63aec-8d7a-4b7a-a608-483ef2118d31)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا باربيكيو (L)', 'بيتزا باربيكيو (L)', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, '9fb63aec-8d7a-4b7a-a608-483ef2118d31', 'sk-0150')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا تشيلي بي (L)' (9fb63b15-b31b-470f-88f2-ce72ff474701)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا تشيلي بي (L)', 'بيتزا تشيلي بي (L)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.8, true, false, '9fb63b15-b31b-470f-88f2-ce72ff474701', 'sk-0151')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا فلافي (L)' (9fb63b2b-7055-428a-b94b-dbd125dfba5d)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا فلافي (L)', 'بيتزا فلافي (L)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.8, true, false, '9fb63b2b-7055-428a-b94b-dbd125dfba5d', 'sk-0152')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بيتزا رانش (L)' (9fb63b3c-eb4b-4be8-9373-19f7e7bcf8ca)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا رانش (L)', 'بيتزا رانش (L)', 'sellable', 'pcs', NULL, 0, true, NULL, 0.8, true, false, '9fb63b3c-eb4b-4be8-9373-19f7e7bcf8ca', 'sk-0153')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'فلافي برجر' (a0df9738-b044-47ba-aae1-0104d085e409)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('فلافي برجر', 'فلافي برجر', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a0df9738-b044-47ba-aae1-0104d085e409', 'sk-0158')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'كلاسك برجر' (a0df9748-53bc-47aa-88f1-453f7fa0b93a)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('كلاسك برجر', 'كلاسك برجر', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a0df9748-53bc-47aa-88f1-453f7fa0b93a', 'sk-0159')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بي برجر' (a0df9767-3f47-4d97-91c0-ee26909135e3)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بي برجر', 'بي برجر', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a0df9767-3f47-4d97-91c0-ee26909135e3', 'sk-0160')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'تشيلي برجر' (a0df9776-dc73-4d2d-9e44-0ab091e16bc6)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('تشيلي برجر', 'تشيلي برجر', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a0df9776-dc73-4d2d-9e44-0ab091e16bc6', 'sk-0161')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'سويت هيت برجر' (a0df978d-6133-4c04-af6b-fbc5e7a161e0)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('سويت هيت برجر', 'سويت هيت برجر', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a0df978d-6133-4c04-af6b-fbc5e7a161e0', 'sk-0162')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'حلقات البصل' (a0df9881-226a-41bf-bed1-f55059963778)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('حلقات البصل', 'حلقات البصل', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a0df9881-226a-41bf-bed1-f55059963778', 'sk-0163')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- '8 حبات كرسبي' (a0dfa625-2cc1-4826-9222-ff630a4a9d7c)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('8 حبات كرسبي', '8 حبات كرسبي', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a0dfa625-2cc1-4826-9222-ff630a4a9d7c', 'sk-0164')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- '10 حبات كرسبي' (a10bf5dc-3eff-4133-9c7b-2358eaece9db)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('10 حبات كرسبي', '10 حبات كرسبي', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a10bf5dc-3eff-4133-9c7b-2358eaece9db', 'sk-0166')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'فرنش فرايز' (a10bf639-3b53-4cee-9665-17f1857227fd)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('فرنش فرايز', 'فرنش فرايز', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a10bf639-3b53-4cee-9665-17f1857227fd', 'sk-0167')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بطاطا كرسكت' (a10bf650-d960-4dff-8572-ec13f1e82bb5)  -- AMBIGUOUS: name collided with another Foodics entity that already claimed the like-named existing product; created new instead. Please review for possible manual dedupe.
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بطاطا كرسكت', 'بطاطا كرسكت', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a10bf650-d960-4dff-8572-ec13f1e82bb5', 'sk-0168')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'بطاطا حلوة' (a10bf65f-86d9-4c2e-b1fd-3928eaf58eac)  -- AMBIGUOUS: name collided with another Foodics entity that already claimed the like-named existing product; created new instead. Please review for possible manual dedupe.
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بطاطا حلوة', 'بطاطا حلوة', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a10bf65f-86d9-4c2e-b1fd-3928eaf58eac', 'sk-0169')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'حلقات البصل' (a10bf6dc-8115-4d23-b669-12ff68dc03b7)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('حلقات البصل', 'حلقات البصل', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a10bf6dc-8115-4d23-b669-12ff68dc03b7', 'sk-0170')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- 'كرات تشيلي' (a10bf6fa-bf08-4366-96e8-f84054a02e6c)
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('كرات تشيلي', 'كرات تشيلي', 'sellable', 'pcs', NULL, 0, true, NULL, 0, true, false, 'a10bf6fa-bf08-4366-96e8-f84054a02e6c', 'sk-0171')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku),
  is_addon = true;

-- =====================================================================
-- SECTION 4: MENU ITEMS (73 active Foodics products)
-- 26 matched to existing products (backfilled below).
-- 47 created as new 'sellable' products (includes ambiguous cases; see notes).
-- =====================================================================

-- --- 4a. Backfill existing products matched to a Foodics menu product ---
-- Foodics product 'لازانيا' (a032e0d9-f3fd-40a4-8237-db917ff617c8) matched to existing product 'Lasagna'
UPDATE products SET
  foodics_id = 'a032e0d9-f3fd-40a4-8237-db917ff617c8',
  sku = COALESCE(sku, 'sk-0155')
WHERE id = '729dc38e-341f-4f98-b20e-7125d7f34a48';

-- Foodics product 'Fluffy Burger Sandwich' (9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f) matched to existing product 'Fluffy Burger Sandwich'
UPDATE products SET
  foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f',
  sku = COALESCE(sku, 'sku-001')
WHERE id = '4130c5cf-594a-48fb-8ccc-de44c6e674b0';

-- Foodics product 'Bee Burger Sandwich' (9be25b04-377e-4083-85b0-48ee5b38a1d7) matched to existing product 'Bee Burger Sandwich'
UPDATE products SET
  foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7',
  sku = COALESCE(sku, 'sku-002')
WHERE id = 'c619336b-a4fe-4b6f-b955-00f0a61db756';

-- Foodics product 'Classic Burger Sandwich' (9be25b04-415e-4ad6-90d1-34384055986c) matched to existing product 'Classic Burger Sandwich'
UPDATE products SET
  foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c',
  sku = COALESCE(sku, 'sku-003')
WHERE id = 'fbb8a69d-b341-4063-b966-a458eba1ba14';

-- Foodics product 'Chili Burger Sandwich' (9be25b04-4ad2-4605-8dff-f3277e471889) matched to existing product 'Chili Burger Sandwich'
UPDATE products SET
  foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889',
  sku = COALESCE(sku, 'sku-004')
WHERE id = '3342f79a-f7af-46a0-a8c3-0c446f08fcff';

-- Foodics product 'Giant Burger Sandwich' (9be25b04-546c-4936-b1bb-90f1e4130e72) matched to existing product 'Giant Burger Sandwich'
UPDATE products SET
  foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72',
  sku = COALESCE(sku, 'sku-005')
WHERE id = '3b945fe1-c884-42a3-aa3e-d668ca3186c4';

-- Foodics product 'Fluffy Burger Meal' (9be25b04-5d34-43c9-a8bf-994e0404abfd) matched to existing product 'Fluffy Burger Meal'
UPDATE products SET
  foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd',
  sku = COALESCE(sku, 'sku-006')
WHERE id = '4f56eb04-c256-4940-9ee0-89c55c62125f';

-- Foodics product 'Bee Burger Meal' (9be25b04-66fb-48b9-bdcc-2706ca34a40b) matched to existing product 'Bee Burger Meal'
UPDATE products SET
  foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b',
  sku = COALESCE(sku, 'sku-007')
WHERE id = '33dd9884-96b1-41aa-9ce5-607cfe16639b';

-- Foodics product 'Classic Burger Meal' (9be25b04-6f4f-4226-809d-ceaa6bdac7a5) matched to existing product 'Classic Burger Meal'
UPDATE products SET
  foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5',
  sku = COALESCE(sku, 'sku-008')
WHERE id = '1b5be96c-a460-4a5b-8959-629b77f1ee8d';

-- Foodics product 'Chili Burger Meal' (9be25b04-77c7-47f2-b8dd-540cdcea4a4b) matched to existing product 'Chili Burger Meal'
UPDATE products SET
  foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b',
  sku = COALESCE(sku, 'sku-009')
WHERE id = 'a8caedb8-1ae8-4355-8389-f3a859825393';

-- Foodics product 'Giant Burger Meal' (9be25b04-7ff6-4f39-9704-5a51037ce108) matched to existing product 'Giant Burger Meal'
UPDATE products SET
  foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108',
  sku = COALESCE(sku, 'sku-010')
WHERE id = 'ea6ca646-c9a3-417e-8fce-ab60230ee55e';

-- Foodics product 'بطاطا حلوة' (9be25b05-001d-4cda-b9e4-54e8a65f2b96) matched to existing product 'Sweet Potato Fries'
UPDATE products SET
  foodics_id = '9be25b05-001d-4cda-b9e4-54e8a65f2b96',
  sku = COALESCE(sku, 'sku-023')
WHERE id = '8042ee25-a628-457d-9fa3-01477705b51f';

-- Foodics product 'فرينش فرايز' (9be25b05-25c9-43e6-99d2-29cbf33100b7) matched to existing product 'French Fries'
UPDATE products SET
  foodics_id = '9be25b05-25c9-43e6-99d2-29cbf33100b7',
  sku = COALESCE(sku, 'sku-027')
WHERE id = '5fd96f77-01ab-417d-8aa4-82418ac15f63';

-- Foodics product 'كيرلي فرايز' (9be25b05-37fe-4551-9b90-aff8cb277d9b) matched to existing product 'Curly Fries'
UPDATE products SET
  foodics_id = '9be25b05-37fe-4551-9b90-aff8cb277d9b',
  sku = COALESCE(sku, 'sku-029')
WHERE id = '700cda71-37dd-430b-825c-fde77cc8ad50';

-- Foodics product 'بطاطا كرسكت' (9be25b05-4bfa-4856-83f0-3b1125700b06) matched to existing product 'Crisscut Fries'
UPDATE products SET
  foodics_id = '9be25b05-4bfa-4856-83f0-3b1125700b06',
  sku = COALESCE(sku, 'sku-031')
WHERE id = 'ec2cac43-f144-4716-bc2c-c4346c803bab';

-- Foodics product 'مشروب غازي' (9be25b05-70c1-4e86-9a01-24d6db9d9687) matched to existing product 'Soft Drink'
UPDATE products SET
  foodics_id = '9be25b05-70c1-4e86-9a01-24d6db9d9687',
  sku = COALESCE(sku, 'sku-035')
WHERE id = 'bbce57ea-dd46-4feb-a7a2-db54579c9c59';

-- Foodics product 'ماء' (9be25b05-795e-4bc8-af41-0ee25b4669a3) matched to existing product 'Water'
UPDATE products SET
  foodics_id = '9be25b05-795e-4bc8-af41-0ee25b4669a3',
  sku = COALESCE(sku, 'sku-036')
WHERE id = '0847ec3b-58ed-4aff-bcdf-bb19a4bd2073';

-- Foodics product 'كرات تشيلي تشيز' (9c009a98-80eb-493e-bec7-5e1d2da035cd) matched to existing product 'Chili Cheese Balls 5pc'
UPDATE products SET
  foodics_id = '9c009a98-80eb-493e-bec7-5e1d2da035cd',
  sku = COALESCE(sku, 'sk-0037')
WHERE id = 'ba15f9a0-bf19-4d29-970a-c6d756c6d71a';

-- Foodics product 'Sweet Heat Sandwich' (9c0832ce-104e-4109-a2bb-dd73379bdc5d) matched to existing product 'Sweet Heat Sandwich'
UPDATE products SET
  foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d',
  sku = COALESCE(sku, 'sk-0040')
WHERE id = '1f9a0e86-1de2-49f9-87eb-b2af63b446e1';

-- Foodics product 'Sweet Heat meal' (9c083460-9db0-4aab-a4b0-d1faaa238f2d) matched to existing product 'Sweet Heat Meal'
UPDATE products SET
  foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d',
  sku = COALESCE(sku, 'sk-0041')
WHERE id = '138fd3fd-4e6a-40b0-9f75-ab3dc9e76881';

-- Foodics product 'خبزة بطاطا' (9c4f4d23-4475-4740-b142-5bfc4e6fd671) matched to existing product 'Potato Bread'
UPDATE products SET
  foodics_id = '9c4f4d23-4475-4740-b142-5bfc4e6fd671',
  sku = COALESCE(sku, 'sk-0047')
WHERE id = '6c2ed003-dd2b-4944-811b-c73454ad38a4';

-- Foodics product 'عصير' (9cbb9998-702a-42fc-87e1-088a06d371b1) matched to existing product 'Juice'
UPDATE products SET
  foodics_id = '9cbb9998-702a-42fc-87e1-088a06d371b1',
  sku = COALESCE(sku, 'sk-0051')
WHERE id = '8461841b-1468-49da-8367-a7827585b4b5';

-- Foodics product 'كرنشي راب ساندويش' (9d690f1f-29f1-47e6-8b52-d663b4bb776f) matched to existing product 'Crunchy Wrap Sandwich'
UPDATE products SET
  foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f',
  sku = COALESCE(sku, 'sk-0058')
WHERE id = '15c2430e-1b36-4fd7-95e2-c3008db83577';

-- Foodics product 'بروستد 12 قطعة' (9e667caa-2c25-4d7e-96b3-ebd5012f1681) matched to existing product 'Broasted 12pc Box'
UPDATE products SET
  foodics_id = '9e667caa-2c25-4d7e-96b3-ebd5012f1681',
  sku = COALESCE(sku, 'sk-0081')
WHERE id = '8352143f-3b71-47fc-9bc9-b718ccc8bd5a';

-- Foodics product 'بروستد 16 قطعة' (9e667e37-6c24-4592-bb3e-b35a61ba8264) matched to existing product 'Broasted 16pc Box'
UPDATE products SET
  foodics_id = '9e667e37-6c24-4592-bb3e-b35a61ba8264',
  sku = COALESCE(sku, 'sk-0082')
WHERE id = '5ef92092-5136-4260-a7a0-e61aca13203d';

-- Foodics product 'بوكس الجمعات' (a0df959a-3e25-4ad1-8581-c84e83f9a291) matched to existing product 'Gatherings Box'
UPDATE products SET
  foodics_id = 'a0df959a-3e25-4ad1-8581-c84e83f9a291',
  sku = COALESCE(sku, 'sk-0157')
WHERE id = '797e48e2-bfc1-4f1f-b82a-bc8a1bd7a4f4';

-- --- 4b. New menu item products ---
-- '3 كولسلو بدينار' (a1f82420-7bcd-4748-9543-e1e1574ca5dd) category='Snacks'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('3 كولسلو بدينار', '3 كولسلو بدينار', 'sellable', 'pcs', 'Snacks', 0, true, NULL, 1, false, false, 'a1f82420-7bcd-4748-9543-e1e1574ca5dd', 'sk-0178')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- '3 مثومة بدينار' (a1f81cdc-7116-40d9-911a-155e65fc2d54) category='Snacks'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('3 مثومة بدينار', '3 مثومة بدينار', 'sellable', 'pcs', 'Snacks', 0, true, NULL, 1, false, false, 'a1f81cdc-7116-40d9-911a-155e65fc2d54', 'sk-0177')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'خبزة الثوم المحمص (٤ حبات)' (a1f73bbc-34e6-41c1-8820-8ee780c6771c) category='Snacks'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('خبزة الثوم المحمص (٤ حبات)', 'خبزة الثوم المحمص (٤ حبات)', 'sellable', 'pcs', 'Snacks', 0, true, NULL, 1, false, false, 'a1f73bbc-34e6-41c1-8820-8ee780c6771c', 'sk-0175')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'فلافي ملك شيك - نكهة القهوة' (a1df5853-1923-45a1-9fba-7463e71777e7) category='Drinks'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('فلافي ملك شيك - نكهة القهوة', 'فلافي ملك شيك - نكهة القهوة', 'sellable', 'pcs', 'Drinks', 0, true, NULL, 2, false, false, 'a1df5853-1923-45a1-9fba-7463e71777e7', 'sk-0173')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'Fluffy Ice Cream' (a1d525fc-0b90-4ce3-9fdd-444f47b6910a) category='Sweets'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('Fluffy Ice Cream', 'Fluffy Ice Cream', 'sellable', 'pcs', 'Sweets', 0, true, NULL, 0.75, false, false, 'a1d525fc-0b90-4ce3-9fdd-444f47b6910a', 'sk-0172')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بوكس الجمعات - كرسبي' (a10bf546-6fd5-44e7-9f77-cf509619cc45) category='Meals'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بوكس الجمعات - كرسبي', 'بوكس الجمعات - كرسبي', 'sellable', 'pcs', 'Meals', 0, true, NULL, 16.2, false, false, 'a10bf546-6fd5-44e7-9f77-cf509619cc45', 'sk-0165')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'خمس أنواع صوص' (9be25b04-8956-4e46-96c4-bd29d098acd1) category='Sauces'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('خمس أنواع صوص', 'خمس أنواع صوص', 'sellable', 'pcs', 'Sauces', 0, true, NULL, 1.6, false, false, '9be25b04-8956-4e46-96c4-bd29d098acd1', 'sku-011')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بافلو صوص' (9be25b04-9252-4354-af01-c556fa673a5a) category='Sauces'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بافلو صوص', 'بافلو صوص', 'sellable', 'pcs', 'Sauces', 0, true, NULL, 0.55, false, false, '9be25b04-9252-4354-af01-c556fa673a5a', 'sku-012')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'تشيلي صوص' (9be25b04-9be3-4ab2-a35e-7c0ad09b0224) category='Sauces'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('تشيلي صوص', 'تشيلي صوص', 'sellable', 'pcs', 'Sauces', 0, true, NULL, 0.55, false, false, '9be25b04-9be3-4ab2-a35e-7c0ad09b0224', 'sku-013')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'سويت تشيلي صوص' (9be25b04-a5a9-494d-ae3b-b6723b2c1b9d) category='Sauces'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('سويت تشيلي صوص', 'سويت تشيلي صوص', 'sellable', 'pcs', 'Sauces', 0, true, NULL, 0.55, false, false, '9be25b04-a5a9-494d-ae3b-b6723b2c1b9d', 'sku-014')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'هني ماسترد صوص' (9be25b04-ae42-4ef9-b06c-aefaf1848abe) category='Sauces'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('هني ماسترد صوص', 'هني ماسترد صوص', 'sellable', 'pcs', 'Sauces', 0, true, NULL, 0.55, false, false, '9be25b04-ae42-4ef9-b06c-aefaf1848abe', 'sku-015')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'باربيكيو  صوص' (9be25b04-b79e-4019-8420-7c7bc3774306) category='Sauces'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('باربيكيو  صوص', 'باربيكيو  صوص', 'sellable', 'pcs', 'Sauces', 0, true, NULL, 0.55, false, false, '9be25b04-b79e-4019-8420-7c7bc3774306', 'sku-016')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'رانش صوص' (9be25b04-c152-43df-b934-6a036aa5b751) category='Sauces'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('رانش صوص', 'رانش صوص', 'sellable', 'pcs', 'Sauces', 0, true, NULL, 0.55, false, false, '9be25b04-c152-43df-b934-6a036aa5b751', 'sku-017')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'فلافي صوص' (9be25b04-caf3-4572-9102-259a59a37478) category='Sauces'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('فلافي صوص', 'فلافي صوص', 'sellable', 'pcs', 'Sauces', 0, true, NULL, 0.55, false, false, '9be25b04-caf3-4572-9102-259a59a37478', 'sku-018')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'موزريلا ستيكس' (9be25b04-dd2f-4738-a950-49df060e7264) category='Snacks'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('موزريلا ستيكس', 'موزريلا ستيكس', 'sellable', 'pcs', 'Snacks', 0, true, NULL, 1.9, false, false, '9be25b04-dd2f-4738-a950-49df060e7264', 'sku-020')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'حلقات البصل' (9be25b04-e7fa-4961-87c3-fb00b68fba43) category='Snacks'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('حلقات البصل', 'حلقات البصل', 'sellable', 'pcs', 'Snacks', 0, true, NULL, 1.35, false, false, '9be25b04-e7fa-4961-87c3-fb00b68fba43', 'sku-021')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بطاطا ويدجز' (9be25b05-2e69-4a2a-a857-bef1e16e2879) category='Fries'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بطاطا ويدجز', 'بطاطا ويدجز', 'sellable', 'pcs', 'Fries', 0, true, NULL, 1.1, false, false, '9be25b05-2e69-4a2a-a857-bef1e16e2879', 'sku-028')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- '4 قطع ستريبس' (9be25b05-5459-45c8-baa6-ec8e57afbd26) category='Crispy Chicken Strips'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('4 قطع ستريبس', '4 قطع ستريبس', 'sellable', 'pcs', 'Crispy Chicken Strips', 0, true, NULL, 4.05, false, false, '9be25b05-5459-45c8-baa6-ec8e57afbd26', 'sku-032')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- '8 قطع ستريبس' (9be25b05-5d57-4027-9071-d19ad8d8ee85) category='Crispy Chicken Strips'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('8 قطع ستريبس', '8 قطع ستريبس', 'sellable', 'pcs', 'Crispy Chicken Strips', 0, true, NULL, 8.1, false, false, '9be25b05-5d57-4027-9071-d19ad8d8ee85', 'sku-033')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- '21 قطعة ستريبس' (9be25b05-66e0-4859-b6c7-cc807d966a2c) category='Crispy Chicken Strips'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('21 قطعة ستريبس', '21 قطعة ستريبس', 'sellable', 'pcs', 'Crispy Chicken Strips', 0, true, NULL, 16.2, false, false, '9be25b05-66e0-4859-b6c7-cc807d966a2c', 'sku-034')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'فلافي صوص' (9c03e8ea-29fc-40c2-8315-4412789e499f) category='Sauces'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('فلافي صوص', 'فلافي صوص', 'sellable', 'pcs', 'Sauces', 0, true, NULL, 0.55, false, false, '9c03e8ea-29fc-40c2-8315-4412789e499f', 'sk-0039')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'ملاحظة عامة للمطبخ' (9c15f8de-44b6-45bc-80eb-b361ead7db94) category='Notes'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('ملاحظة عامة للمطبخ', 'ملاحظة عامة للمطبخ', 'sellable', 'pcs', 'Notes', 0, true, NULL, 0.001, false, false, '9c15f8de-44b6-45bc-80eb-b361ead7db94', 'sk-0042')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'حبة كرسبي' (9c190b45-f68d-46b5-8666-3af01afbaffc) category='Crispy Chicken Strips'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('حبة كرسبي', 'حبة كرسبي', 'sellable', 'pcs', 'Crispy Chicken Strips', 0, true, NULL, 1.1, false, false, '9c190b45-f68d-46b5-8666-3af01afbaffc', 'sk-0044')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'Crispy Plate صحن كرسبي' (9d3c0ca5-fca9-4e26-88ba-04175e06cfad) category='Meals'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('Crispy Plate صحن كرسبي', 'Crispy Plate صحن كرسبي', 'sellable', 'pcs', 'Meals', 0, true, NULL, 4.3, false, false, '9d3c0ca5-fca9-4e26-88ba-04175e06cfad', 'sk-0052')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'صوص جبنه' (9d46d4af-a66e-44a9-8641-dc9dd6aae8b5) category='Sauces'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('صوص جبنه', 'صوص جبنه', 'sellable', 'pcs', 'Sauces', 0, true, NULL, 0.55, false, false, '9d46d4af-a66e-44a9-8641-dc9dd6aae8b5', 'sk-0057')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'وجبة كرنشي راب' (9d690f6c-d16d-4e71-9574-52056e8bcf87) category='Meals'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('وجبة كرنشي راب', 'وجبة كرنشي راب', 'sellable', 'pcs', 'Meals', 0, true, NULL, 4.6, false, false, '9d690f6c-d16d-4e71-9574-52056e8bcf87', 'sk-0059')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بيتزا سوبر سوبريم' (9e66723d-aaa6-414a-a73c-b852eb591e3e) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا سوبر سوبريم', 'بيتزا سوبر سوبريم', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 0, false, false, '9e66723d-aaa6-414a-a73c-b852eb591e3e', 'sk-0065')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بيتزا باباروني' (9e667367-ce56-4513-9c21-0810869c03c3) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا باباروني', 'بيتزا باباروني', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 0, false, false, '9e667367-ce56-4513-9c21-0810869c03c3', 'sk-0069')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بيتزا مارغريتا' (9e6674d6-4422-4de9-b6b8-f00a669d258e) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا مارغريتا', 'بيتزا مارغريتا', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 0, false, false, '9e6674d6-4422-4de9-b6b8-f00a669d258e', 'sk-0073')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بيتزا خضار' (9e66752f-b46b-4938-8aad-7887502b2d70) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا خضار', 'بيتزا خضار', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 0, false, false, '9e66752f-b46b-4938-8aad-7887502b2d70', 'sk-0074')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بيتزا الفريدو' (9e667591-e8a2-479a-ad27-7c51084bbd87) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا الفريدو', 'بيتزا الفريدو', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 0, false, false, '9e667591-e8a2-479a-ad27-7c51084bbd87', 'sk-0075')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'وجبة بروستد 4 قطع' (9e6676e2-e547-4e05-a233-5cc42a3d7476) category='Broasted'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('وجبة بروستد 4 قطع', 'وجبة بروستد 4 قطع', 'sellable', 'pcs', 'Broasted', 0, true, NULL, 3.8, false, false, '9e6676e2-e547-4e05-a233-5cc42a3d7476', 'sk-0076')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'وجبة بروستد 8 قطع' (9e667894-5573-4bc0-aaa4-b4625253590c) category='Broasted'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('وجبة بروستد 8 قطع', 'وجبة بروستد 8 قطع', 'sellable', 'pcs', 'Broasted', 0, true, NULL, 7.5, false, false, '9e667894-5573-4bc0-aaa4-b4625253590c', 'sk-0077')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'كولسو' (9e667f5d-4a4e-47db-99e9-d3b4b3cbebce) category='Snacks'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('كولسو', 'كولسو', 'sellable', 'pcs', 'Snacks', 0, true, NULL, 0.55, false, false, '9e667f5d-4a4e-47db-99e9-d3b4b3cbebce', 'sk-0084')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'مثومة' (9e667f89-23d2-4645-bfda-5a7d59b7d731) category='Snacks'  -- AMBIGUOUS: name collided with another Foodics entity that already claimed the like-named existing product (or existing product's type looked like a different real-world item); created new instead. Please review for possible manual dedupe.
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('مثومة', 'مثومة', 'sellable', 'pcs', 'Snacks', 0, true, NULL, 0.4, false, false, '9e667f89-23d2-4645-bfda-5a7d59b7d731', 'sk-0085')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'خبزة للبروستد' (9e667fb0-cced-4d77-b616-069fcea30b1e) category='Snacks'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('خبزة للبروستد', 'خبزة للبروستد', 'sellable', 'pcs', 'Snacks', 0, true, NULL, 0.15, false, false, '9e667fb0-cced-4d77-b616-069fcea30b1e', 'sk-0086')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'فرينش فرايز' (9e668078-4d84-459a-98a3-c45f0b3f7d3a) category='Fries'  -- AMBIGUOUS: name collided with another Foodics entity that already claimed the like-named existing product (or existing product's type looked like a different real-world item); created new instead. Please review for possible manual dedupe.
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('فرينش فرايز', 'فرينش فرايز', 'sellable', 'pcs', 'Fries', 0, true, NULL, 1.1, false, false, '9e668078-4d84-459a-98a3-c45f0b3f7d3a', 'sk-0087')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بيتزا باربيكيو' (9e6a5159-59cb-48e5-85de-a596d4b0520f) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا باربيكيو', 'بيتزا باربيكيو', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 0, false, false, '9e6a5159-59cb-48e5-85de-a596d4b0520f', 'sk-0088')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بيتزا تشيلي بي' (9ece8c1d-9fce-4671-8ac1-c7158136b49b) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا تشيلي بي', 'بيتزا تشيلي بي', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 0, false, false, '9ece8c1d-9fce-4671-8ac1-c7158136b49b', 'sk-0117')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'فرقيه وجبه' (9f420c8e-1e7a-4438-af82-1d3a884a90b6) category='Meals'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('فرقيه وجبه', 'فرقيه وجبه', 'sellable', 'pcs', 'Meals', 0, true, NULL, 1.35, false, false, '9f420c8e-1e7a-4438-af82-1d3a884a90b6', 'sk-0119')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بيتزا فلافي (الجديدة)' (9fb59cda-cab6-4487-9691-088f078f0b94) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا فلافي (الجديدة)', 'بيتزا فلافي (الجديدة)', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 0, false, false, '9fb59cda-cab6-4487-9691-088f078f0b94', 'sk-0120')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'بيتزا رانش (الجديدة)' (9fb59ecb-29a0-4ac2-a16b-fdb6b2ae32b7) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('بيتزا رانش (الجديدة)', 'بيتزا رانش (الجديدة)', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 0, false, false, '9fb59ecb-29a0-4ac2-a16b-fdb6b2ae32b7', 'sk-0121')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'عرض ال 3 بيتزا - صغير' (9fb631ca-41b9-41be-9c65-fea2fd4b20c1) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('عرض ال 3 بيتزا - صغير', 'عرض ال 3 بيتزا - صغير', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 6.5, false, false, '9fb631ca-41b9-41be-9c65-fea2fd4b20c1', 'sk-0124')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'عرض ال 3 بيتزا - وسط' (9fb6367d-dc62-409a-84a9-85bc7b1781e6) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('عرض ال 3 بيتزا - وسط', 'عرض ال 3 بيتزا - وسط', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 12.95, false, false, '9fb6367d-dc62-409a-84a9-85bc7b1781e6', 'sk-0134')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'عرض ال 3 بيتزا - كبير' (9fb63a29-3b0a-42e2-8799-daa9d350d9cb) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('عرض ال 3 بيتزا - كبير', 'عرض ال 3 بيتزا - كبير', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 16.75, false, false, '9fb63a29-3b0a-42e2-8799-daa9d350d9cb', 'sk-0144')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'اصنع البيتزا الخاصة بي' (a02d1849-be95-464c-be18-5a8b5c4dd270) category='Pizza'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('اصنع البيتزا الخاصة بي', 'اصنع البيتزا الخاصة بي', 'sellable', 'pcs', 'Pizza', 0, true, NULL, 0.55, false, false, 'a02d1849-be95-464c-be18-5a8b5c4dd270', 'sk-0154')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- 'مشروب موظف' (a05d8867-d8b2-46e5-b67c-03b55de9fed8) category='Drinks'
INSERT INTO products (name_en, name_ar, type, unit, category, avg_cost, active, brand, selling_price, is_addon, is_combo, foodics_id, sku)
VALUES ('مشروب موظف', 'مشروب موظف', 'sellable', 'pcs', 'Drinks', 0, true, NULL, 0.25, false, false, 'a05d8867-d8b2-46e5-b67c-03b55de9fed8', 'sk-0156')
ON CONFLICT (foodics_id) DO UPDATE SET
  sku = COALESCE(products.sku, EXCLUDED.sku);

-- =====================================================================
-- SECTION 5: RELATIONSHIPS
-- All relationship inserts resolve both sides by products/addon_categories
-- .foodics_id at insert time, so they work uniformly whether a row was
-- freshly inserted above or an existing row that just got backfilled.
-- =====================================================================

-- --- 5a. addon_category_options (group -> option) ---
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a1f73c14-9878-4fd6-ac1b-f3ee01535ea8' AND p.foodics_id = 'a1f73c46-2447-4ff5-9094-694315d23af3'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9' AND p.foodics_id = '9be26191-cdc3-4e73-9ec3-ff3b2a1672be'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9' AND p.foodics_id = '9be26191-d6c3-4bd4-a3fe-c9929fc8e179'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9' AND p.foodics_id = '9be26191-df30-44dc-9747-1c6bce27abbb'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9' AND p.foodics_id = '9be26191-e7a1-4f30-9a9c-5a72d9b64c5b'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9' AND p.foodics_id = '9be26191-efe0-4d11-b8b4-1a1f5dc1559e'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 5
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9' AND p.foodics_id = '9be26191-f822-464e-8960-412fce9e81d3'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 6
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9' AND p.foodics_id = '9be26192-000e-4ae0-a4bc-9f93a0a116ba'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25b51-2dfc-47f4-b940-89bb7ebfdb71' AND p.foodics_id = '9be26191-c56a-4f66-a605-ac56deebb81a'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25b51-2dfc-47f4-b940-89bb7ebfdb71' AND p.foodics_id = '9c4f4c36-ce23-49a5-9171-2c9ce1753d65'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9be26191-68fc-4b91-9f8c-6a0edfef92fe'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9be26191-7391-461d-9ae1-ccbe2b7604ea'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9be26191-7df9-488f-a38a-daf024599397'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9be26191-86a5-4c24-9faa-2afcc0d0af4a'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9be26191-8e9e-4054-bf7b-bd7ec6423818'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 5
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9be26191-9933-4087-b144-91f95a864324'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 6
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9be26191-a117-4702-9e88-5cda0d556f7f'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 7
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9be26191-a97d-4f06-bf55-5402ee08170b'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 8
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9be26191-b106-4750-8f38-57a9f9d0d5e4'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 9
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9be26191-bd6e-467a-8565-f2d9de750aeb'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 10
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294' AND p.foodics_id = '9d4438d3-22bf-4d0a-9331-c117a5860577'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be2606f-f35c-4ba9-95c8-396037dbebfc' AND p.foodics_id = '9be26192-0781-4a2b-8dfc-b70aa309103f'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be2606f-f35c-4ba9-95c8-396037dbebfc' AND p.foodics_id = '9be26192-0ebf-4edf-a15d-b7ca4f4127f4'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be2606f-f35c-4ba9-95c8-396037dbebfc' AND p.foodics_id = '9be26192-166b-44e7-ac70-687d61cec7ca'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be2606f-f35c-4ba9-95c8-396037dbebfc' AND p.foodics_id = '9cb9af07-448c-44e1-aa1f-42eb3f71759a'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555' AND p.foodics_id = '9be26191-1f8a-4f32-b226-8c3f432d3cca'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555' AND p.foodics_id = '9be26191-3157-45c7-adb6-07e74e2f3e6c'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555' AND p.foodics_id = '9be26191-3930-4aa2-ae98-418c8dc5391a'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555' AND p.foodics_id = '9be26191-40f5-4dec-9492-353c49187962'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555' AND p.foodics_id = '9be26191-4908-461c-9eaa-d3a887e7cdbc'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 5
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555' AND p.foodics_id = '9be26191-51c3-43a4-a5b2-30dbc46e9b0c'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 6
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555' AND p.foodics_id = '9be26191-596e-43c5-a97e-dd2b840e72a0'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 7
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555' AND p.foodics_id = '9be26191-615e-43f1-8fa1-4866cfc869d1'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153' AND p.foodics_id = '9be6d0d7-262c-4837-a018-b7317c92e981'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153' AND p.foodics_id = '9be6d0ec-d68f-40a1-a70a-281e074417d0'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153' AND p.foodics_id = '9be6d210-9652-43ff-852a-8b44cbaa6f24'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153' AND p.foodics_id = '9be6d248-e932-4d78-a238-35626ee79ab3'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153' AND p.foodics_id = '9be6d26f-9442-420c-90ff-43b5e4523849'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9d3c0d18-b434-48db-ba6c-b641004f3c34' AND p.foodics_id = '9d3c0d6e-363c-49a7-bdfc-7982aff41587'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9d3c0d18-b434-48db-ba6c-b641004f3c34' AND p.foodics_id = '9d3c0dc7-298e-4a20-9d12-07d0eacd432c'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9d3c0d18-b434-48db-ba6c-b641004f3c34' AND p.foodics_id = '9db22619-6ad2-45fa-a48b-2fa3e88a04c2'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9d6b13e7-839f-427e-b8cc-2265d9e49fda' AND p.foodics_id = '9d6b1421-80a7-4d75-95bd-692a9fb820c1'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9d6b13e7-839f-427e-b8cc-2265d9e49fda' AND p.foodics_id = '9d6b1450-6978-4cf7-82bf-6dd28ce0d859'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9d6b13e7-839f-427e-b8cc-2265d9e49fda' AND p.foodics_id = '9d6c68f0-aae0-4499-b04f-c7c7c2088ec8'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9d6b13e7-839f-427e-b8cc-2265d9e49fda' AND p.foodics_id = '9d6cad0d-a3f4-4d7b-a3e5-412e34935ae8'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5' AND p.foodics_id = '9e6672cf-f6da-4d60-95c0-8229a8da58e3'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5' AND p.foodics_id = '9e667310-d243-44a0-bdd1-ba69a8a0776e'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5' AND p.foodics_id = '9e667337-cb31-4395-a302-bcdbad7cb551'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5' AND p.foodics_id = '9e6673e0-e082-4fce-97f5-467cd6425eef'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5' AND p.foodics_id = '9e667409-a553-45ed-a5b0-6e21c1c6f969'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 5
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5' AND p.foodics_id = '9e667437-c90f-4e68-84b5-886f45d299c7'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e667a0a-9187-43f7-aa8f-016d77cad146' AND p.foodics_id = '9e667a7d-dbe8-45db-80e2-20983ddc66f4'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e667a0a-9187-43f7-aa8f-016d77cad146' AND p.foodics_id = '9e667aa6-66fb-448c-bff1-a1d02093b933'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e667a0a-9187-43f7-aa8f-016d77cad146' AND p.foodics_id = '9e667ad1-2caf-4274-a58c-8c1d66a121a8'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e667a0a-9187-43f7-aa8f-016d77cad146' AND p.foodics_id = '9e667eb3-7f96-4a9b-a42d-eaa0a3f758df'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e6a53be-ce48-466b-8066-8654ca9eaa5e' AND p.foodics_id = '9e6a53ec-d339-4689-834a-5a168cd167ff'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e6a53be-ce48-466b-8066-8654ca9eaa5e' AND p.foodics_id = '9e6a540f-20e2-4273-a79d-e312719a724e'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e6a53be-ce48-466b-8066-8654ca9eaa5e' AND p.foodics_id = '9e6a5427-507c-4987-8361-2254cc639661'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e6a53be-ce48-466b-8066-8654ca9eaa5e' AND p.foodics_id = '9e6a543d-d0e5-4fc7-addf-7312842ed072'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e6a53be-ce48-466b-8066-8654ca9eaa5e' AND p.foodics_id = '9e6a5459-4aad-4fcc-b9f9-5ba6cdfab9b8'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 5
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e6a53be-ce48-466b-8066-8654ca9eaa5e' AND p.foodics_id = '9ecea5e8-1bfa-47e2-a373-1875ebd09522'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 6
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e6a53be-ce48-466b-8066-8654ca9eaa5e' AND p.foodics_id = '9fb5a8f8-32b0-4e63-88f5-dacf3b549cb0'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588' AND p.foodics_id = '9e6e1dde-2954-47d2-b7da-cbccbb2d0a6c'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588' AND p.foodics_id = '9e6e1df2-5c75-4967-9859-b8edd07be67a'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e700ef7-1945-41f8-a5ce-101a65fef015' AND p.foodics_id = '9e700f06-fac6-443c-abb1-3b8c81c269e2'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e700ef7-1945-41f8-a5ce-101a65fef015' AND p.foodics_id = '9e700f16-b0be-47f4-b64d-aff0255f2e72'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e700ef7-1945-41f8-a5ce-101a65fef015' AND p.foodics_id = '9e700f6f-34ea-4170-b360-47d2d69e6b01'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e708e43-4574-483b-ab93-e4b2d6da1d52' AND p.foodics_id = '9e708e9c-9537-45e9-88c6-4adb50edbfb1'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e708e43-4574-483b-ab93-e4b2d6da1d52' AND p.foodics_id = '9e708f0e-b09f-4833-836f-927ddf8815b9'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e708e43-4574-483b-ab93-e4b2d6da1d52' AND p.foodics_id = '9e708f34-4f95-425e-b027-63e806bf4ef6'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e74941b-d5f6-4920-b649-7e1db55fad04' AND p.foodics_id = '9e749446-bfc5-4d67-b2ef-16da8e5c09c8'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e74941b-d5f6-4920-b649-7e1db55fad04' AND p.foodics_id = '9e749472-77f8-4b2c-98d3-ca3c0ecf1d33'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e74941b-d5f6-4920-b649-7e1db55fad04' AND p.foodics_id = '9e749498-f625-4f2d-9c71-17085b795935'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6' AND p.foodics_id = '9e7cbc63-475b-456e-910e-142e1bd058fc'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6' AND p.foodics_id = '9e7cbc92-5e83-4cd6-80e7-be07cec1bc00'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e90bdc2-f696-4ab0-b63d-2f9786abeaf6' AND p.foodics_id = '9e90bdd9-1dad-4631-b7fd-096a719fe99f'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e90bdc2-f696-4ab0-b63d-2f9786abeaf6' AND p.foodics_id = '9e90bdec-89cb-4669-92de-04c413dce6e5'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e90bdc2-f696-4ab0-b63d-2f9786abeaf6' AND p.foodics_id = '9e90be1c-1011-46e9-8864-b72f9cab8e83'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9e90bdc2-f696-4ab0-b63d-2f9786abeaf6' AND p.foodics_id = '9fb59fdf-9a99-47a5-9bad-04eb87909fb5'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63379-cbe7-4686-b9f0-5c94a052a34d' AND p.foodics_id = '9fb63476-3190-4cc4-b8b0-dcfc1b810aaf'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63379-cbe7-4686-b9f0-5c94a052a34d' AND p.foodics_id = '9fb634a4-1ff0-409e-9028-fa8e668284da'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63379-cbe7-4686-b9f0-5c94a052a34d' AND p.foodics_id = '9fb634ce-ee60-4b6b-b2e3-2e270a1b18ca'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63379-cbe7-4686-b9f0-5c94a052a34d' AND p.foodics_id = '9fb634f2-605b-44de-b242-e92c3737eb52'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63379-cbe7-4686-b9f0-5c94a052a34d' AND p.foodics_id = '9fb6352d-7580-410c-b91b-6e699d76bb3b'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 5
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63379-cbe7-4686-b9f0-5c94a052a34d' AND p.foodics_id = '9fb63583-6615-4f63-9c3c-ba7d2e21eb85'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 6
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63379-cbe7-4686-b9f0-5c94a052a34d' AND p.foodics_id = '9fb635b5-4580-47d5-9183-5cacf04165e8'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 7
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63379-cbe7-4686-b9f0-5c94a052a34d' AND p.foodics_id = '9fb635e2-ca4e-4a59-bded-17bddadeba1c'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 8
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63379-cbe7-4686-b9f0-5c94a052a34d' AND p.foodics_id = '9fb63612-1df7-41c1-be6e-9248dbb4a4fe'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63704-c43f-4e56-9d29-bb3cacf7fb76' AND p.foodics_id = '9fb63758-7544-4986-be6a-03734f330773'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63704-c43f-4e56-9d29-bb3cacf7fb76' AND p.foodics_id = '9fb6377a-9047-442b-a27a-e663e810792e'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63704-c43f-4e56-9d29-bb3cacf7fb76' AND p.foodics_id = '9fb63826-e19b-4c19-b245-e9328d171743'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63704-c43f-4e56-9d29-bb3cacf7fb76' AND p.foodics_id = '9fb6383a-57d2-455f-9e39-9260492d7adb'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63704-c43f-4e56-9d29-bb3cacf7fb76' AND p.foodics_id = '9fb63854-3ab0-4755-bbc6-84770f1e4292'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 5
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63704-c43f-4e56-9d29-bb3cacf7fb76' AND p.foodics_id = '9fb6386f-b517-4e2b-884e-bc06c717d394'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 6
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63704-c43f-4e56-9d29-bb3cacf7fb76' AND p.foodics_id = '9fb6388f-eba9-4bf8-a86e-34f89643dc12'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 7
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63704-c43f-4e56-9d29-bb3cacf7fb76' AND p.foodics_id = '9fb638a1-ddc9-48ca-b3df-09092dff5361'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 8
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63704-c43f-4e56-9d29-bb3cacf7fb76' AND p.foodics_id = '9fb638bf-6b76-434a-bcf4-064372078fc3'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63a48-ed76-48e0-ae11-c84c375cb50d' AND p.foodics_id = '9fb63a71-f7a6-42fa-835f-cfe1ceccf0db'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63a48-ed76-48e0-ae11-c84c375cb50d' AND p.foodics_id = '9fb63a8b-11a9-4dd0-a987-2a5fe8f42fe6'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63a48-ed76-48e0-ae11-c84c375cb50d' AND p.foodics_id = '9fb63aa5-aaad-4a33-8060-a1c9cb144f39'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63a48-ed76-48e0-ae11-c84c375cb50d' AND p.foodics_id = '9fb63abd-cb4a-4088-b8ec-1e466fc58e7b'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63a48-ed76-48e0-ae11-c84c375cb50d' AND p.foodics_id = '9fb63ad6-67c7-4adc-8b55-6314e91b6bb4'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 5
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63a48-ed76-48e0-ae11-c84c375cb50d' AND p.foodics_id = '9fb63aec-8d7a-4b7a-a608-483ef2118d31'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 6
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63a48-ed76-48e0-ae11-c84c375cb50d' AND p.foodics_id = '9fb63b15-b31b-470f-88f2-ce72ff474701'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 7
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63a48-ed76-48e0-ae11-c84c375cb50d' AND p.foodics_id = '9fb63b2b-7055-428a-b94b-dbd125dfba5d'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 8
FROM addon_categories ac, products p
WHERE ac.foodics_id = '9fb63a48-ed76-48e0-ae11-c84c375cb50d' AND p.foodics_id = '9fb63b3c-eb4b-4be8-9373-19f7e7bcf8ca'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a0df96aa-a269-4dcd-b69f-21db1f07a422' AND p.foodics_id = 'a0df9738-b044-47ba-aae1-0104d085e409'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a0df96aa-a269-4dcd-b69f-21db1f07a422' AND p.foodics_id = 'a0df9748-53bc-47aa-88f1-453f7fa0b93a'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a0df96aa-a269-4dcd-b69f-21db1f07a422' AND p.foodics_id = 'a0df9767-3f47-4d97-91c0-ee26909135e3'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a0df96aa-a269-4dcd-b69f-21db1f07a422' AND p.foodics_id = 'a0df9776-dc73-4d2d-9e44-0ab091e16bc6'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a0df96aa-a269-4dcd-b69f-21db1f07a422' AND p.foodics_id = 'a0df978d-6133-4c04-af6b-fbc5e7a161e0'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a0df986d-df29-46ce-ba4a-e21bdaef36ae' AND p.foodics_id = 'a0df9881-226a-41bf-bed1-f55059963778'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a0df986d-df29-46ce-ba4a-e21bdaef36ae' AND p.foodics_id = 'a0dfa625-2cc1-4826-9222-ff630a4a9d7c'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 0
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a10bf5bf-8c1a-4ba0-8028-079a4dbced0f' AND p.foodics_id = 'a10bf5dc-3eff-4133-9c7b-2358eaece9db'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 1
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a10bf5bf-8c1a-4ba0-8028-079a4dbced0f' AND p.foodics_id = 'a10bf639-3b53-4cee-9665-17f1857227fd'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 2
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a10bf5bf-8c1a-4ba0-8028-079a4dbced0f' AND p.foodics_id = 'a10bf650-d960-4dff-8572-ec13f1e82bb5'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 3
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a10bf5bf-8c1a-4ba0-8028-079a4dbced0f' AND p.foodics_id = 'a10bf65f-86d9-4c2e-b1fd-3928eaf58eac'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 4
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a10bf5bf-8c1a-4ba0-8028-079a4dbced0f' AND p.foodics_id = 'a10bf6dc-8115-4d23-b669-12ff68dc03b7'
ON CONFLICT DO NOTHING;
INSERT INTO addon_category_options (addon_category_id, product_id, sort_order)
SELECT ac.id, p.id, 5
FROM addon_categories ac, products p
WHERE ac.foodics_id = 'a10bf5bf-8c1a-4ba0-8028-079a4dbced0f' AND p.foodics_id = 'a10bf6fa-bf08-4366-96e8-f84054a02e6c'
ON CONFLICT DO NOTHING;
-- total addon_category_options rows: 119

-- --- 5b. recipe_lines (from Foodics products' and options' ingredients) ---
-- menu item 'بوكس الجمعات - كرسبي' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = 'a10bf546-6fd5-44e7-9f77-cf509619cc45' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Sandwich' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Sandwich' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Sandwich' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Sandwich' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Sandwich' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Sandwich' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Sandwich' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Sandwich' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Sandwich' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Sandwich' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Sandwich' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'جرجير' (9fdf8262-2a7b-48a5-ae5e-3090533136ba) qty=10
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 10
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fdf8262-2a7b-48a5-ae5e-3090533136ba'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'تيركي' (9fdf82a7-a17d-4330-a700-8d4ae85086a4) qty=20
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 20
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fdf82a7-a17d-4330-a700-8d4ae85086a4'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Sandwich' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'مخلل خيار مقطع' (9fdf8801-a1b8-4808-a8ca-7397e1922e90) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fdf8801-a1b8-4808-a8ca-7397e1922e90'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'روست بيف' (9fdf8836-85c7-4562-8888-e3c77418a505) qty=20
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 20
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fdf8836-85c7-4562-8888-e3c77418a505'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Sandwich' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'مخلل خيار مقطع' (9fdf8801-a1b8-4808-a8ca-7397e1922e90) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fdf8801-a1b8-4808-a8ca-7397e1922e90'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'روست بيف' (9fdf8836-85c7-4562-8888-e3c77418a505) qty=20
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 20
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fdf8836-85c7-4562-8888-e3c77418a505'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=80
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 80
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Sandwich' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Fluffy Burger Meal' <- 'كياس شفاف مطبوعة' (9fecc602-5bd5-4c96-85ea-2b3e22762f94) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND c.foodics_id = '9fecc602-5bd5-4c96-85ea-2b3e22762f94'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Bee Burger Meal' <- 'كياس شفاف مطبوعة' (9fecc602-5bd5-4c96-85ea-2b3e22762f94) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND c.foodics_id = '9fecc602-5bd5-4c96-85ea-2b3e22762f94'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'جرجير' (9fdf8262-2a7b-48a5-ae5e-3090533136ba) qty=10
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 10
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fdf8262-2a7b-48a5-ae5e-3090533136ba'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'تيركي' (9fdf82a7-a17d-4330-a700-8d4ae85086a4) qty=20
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 20
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fdf82a7-a17d-4330-a700-8d4ae85086a4'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Classic Burger Meal' <- 'كياس شفاف مطبوعة' (9fecc602-5bd5-4c96-85ea-2b3e22762f94) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND c.foodics_id = '9fecc602-5bd5-4c96-85ea-2b3e22762f94'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=20
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 20
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'مخلل خيار مقطع' (9fdf8801-a1b8-4808-a8ca-7397e1922e90) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fdf8801-a1b8-4808-a8ca-7397e1922e90'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'روست بيف' (9fdf8836-85c7-4562-8888-e3c77418a505) qty=20
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 20
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fdf8836-85c7-4562-8888-e3c77418a505'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Chili Burger Meal' <- 'كياس شفاف مطبوعة' (9fecc602-5bd5-4c96-85ea-2b3e22762f94) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND c.foodics_id = '9fecc602-5bd5-4c96-85ea-2b3e22762f94'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'مخلل خيار مقطع' (9fdf8801-a1b8-4808-a8ca-7397e1922e90) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fdf8801-a1b8-4808-a8ca-7397e1922e90'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'روست بيف' (9fdf8836-85c7-4562-8888-e3c77418a505) qty=20
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 20
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fdf8836-85c7-4562-8888-e3c77418a505'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=80
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 80
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Giant Burger Meal' <- 'كياس شفاف مطبوعة' (9fecc602-5bd5-4c96-85ea-2b3e22762f94) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND c.foodics_id = '9fecc602-5bd5-4c96-85ea-2b3e22762f94'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'خمس أنواع صوص' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=5
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 5
FROM products p, products c
WHERE p.foodics_id = '9be25b04-8956-4e46-96c4-bd29d098acd1' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'بافلو صوص' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-9252-4354-af01-c556fa673a5a' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'تشيلي صوص' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-9be3-4ab2-a35e-7c0ad09b0224' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'سويت تشيلي صوص' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-a5a9-494d-ae3b-b6723b2c1b9d' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'موزريلا ستيكس' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-dd2f-4738-a950-49df060e7264' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'موزريلا ستيكس' <- 'لامبستون اصابع مزريلا' (9fe29b5a-3993-48fd-bcb7-4c994db6ff21) qty=4
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 4
FROM products p, products c
WHERE p.foodics_id = '9be25b04-dd2f-4738-a950-49df060e7264' AND c.foodics_id = '9fe29b5a-3993-48fd-bcb7-4c994db6ff21'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'حلقات البصل' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b04-e7fa-4961-87c3-fb00b68fba43' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'حلقات البصل' <- 'حلقات بصل' (9fe2b05a-663d-45c8-a0fb-9cf5108bf263) qty=7
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 7
FROM products p, products c
WHERE p.foodics_id = '9be25b04-e7fa-4961-87c3-fb00b68fba43' AND c.foodics_id = '9fe2b05a-663d-45c8-a0fb-9cf5108bf263'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '4 قطع ستريبس' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '4 قطع ستريبس' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '4 قطع ستريبس' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '4 قطع ستريبس' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=320
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 320
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '4 قطع ستريبس' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '4 قطع ستريبس' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '4 قطع ستريبس' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '8 قطع ستريبس' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '8 قطع ستريبس' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '8 قطع ستريبس' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '8 قطع ستريبس' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '8 قطع ستريبس' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=640
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 640
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '8 قطع ستريبس' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=300
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 300
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '8 قطع ستريبس' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '8 قطع ستريبس' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=5
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 5
FROM products p, products c
WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '21 قطعة ستريبس' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=3
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 3
FROM products p, products c
WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '21 قطعة ستريبس' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=4
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 4
FROM products p, products c
WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '21 قطعة ستريبس' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '21 قطعة ستريبس' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=1680
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1680
FROM products p, products c
WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '21 قطعة ستريبس' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=600
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 600
FROM products p, products c
WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '21 قطعة ستريبس' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=3
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 3
FROM products p, products c
WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item '21 قطعة ستريبس' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=10
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 10
FROM products p, products c
WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'مشروب غازي' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be25b05-70c1-4e86-9a01-24d6db9d9687' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرات تشيلي تشيز' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c009a98-80eb-493e-bec7-5e1d2da035cd' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرات تشيلي تشيز' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c009a98-80eb-493e-bec7-5e1d2da035cd' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرات تشيلي تشيز' <- 'ناجتس شيدر حار 1 ك' (9fe29d9b-03d0-4a51-87f0-be00e863d5ad) qty=5
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 5
FROM products p, products c
WHERE p.foodics_id = '9c009a98-80eb-493e-bec7-5e1d2da035cd' AND c.foodics_id = '9fe29d9b-03d0-4a51-87f0-be00e863d5ad'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرات تشيلي تشيز' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c009a98-80eb-493e-bec7-5e1d2da035cd' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'فلافي صوص' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c03e8ea-29fc-40c2-8315-4412789e499f' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=83
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 83
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat Sandwich' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'صدور دجاج جاهزة' (9fddf596-3bbe-4434-a440-dcc8d0c81cae) qty=200
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 200
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fddf596-3bbe-4434-a440-dcc8d0c81cae'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'علب برجر 120' (9fde2bf6-0ad5-456c-9eea-17b3751fb209) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fde2bf6-0ad5-456c-9eea-17b3751fb209'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'خس برجر' (9fdf776e-3aac-48ca-bb92-f5e67b7c758c) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fdf776e-3aac-48ca-bb92-f5e67b7c758c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'بندورة' (9fdf7dfb-a234-4e5f-95ad-6199244018af) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fdf7dfb-a234-4e5f-95ad-6199244018af'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=116
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 116
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'صحن مفتوح 250' (9fe8100a-d3b1-45e9-b13e-c23da7c4460f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fe8100a-d3b1-45e9-b13e-c23da7c4460f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Sweet Heat meal' <- 'كياس شفاف مطبوعة' (9fecc602-5bd5-4c96-85ea-2b3e22762f94) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND c.foodics_id = '9fecc602-5bd5-4c96-85ea-2b3e22762f94'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'حبة كرسبي' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=80
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 80
FROM products p, products c
WHERE p.foodics_id = '9c190b45-f68d-46b5-8666-3af01afbaffc' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'خبزة بطاطا' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c4f4d23-4475-4740-b142-5bfc4e6fd671' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'عصير' <- 'عصير' (9fdf7216-0b0a-4270-bf2b-478dded24a6c) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9cbb9998-702a-42fc-87e1-088a06d371b1' AND c.foodics_id = '9fdf7216-0b0a-4270-bf2b-478dded24a6c'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Crispy Plate صحن كرسبي' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Crispy Plate صحن كرسبي' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Crispy Plate صحن كرسبي' <- 'مخلل خيار مقطع' (9fdf8801-a1b8-4808-a8ca-7397e1922e90) qty=25
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 25
FROM products p, products c
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND c.foodics_id = '9fdf8801-a1b8-4808-a8ca-7397e1922e90'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Crispy Plate صحن كرسبي' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=240
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 240
FROM products p, products c
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Crispy Plate صحن كرسبي' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Crispy Plate صحن كرسبي' <- 'خس ايسبرغ' (9fe0ca59-da4c-4534-a75e-b2a6b001db39) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND c.foodics_id = '9fe0ca59-da4c-4534-a75e-b2a6b001db39'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Crispy Plate صحن كرسبي' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=116
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 116
FROM products p, products c
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Crispy Plate صحن كرسبي' <- 'صحن كرسبي  330 كرتونة' (9fea9c6b-456a-4d41-8f60-34421902e1dd) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND c.foodics_id = '9fea9c6b-456a-4d41-8f60-34421902e1dd'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'Crispy Plate صحن كرسبي' <- 'كياس شفاف مطبوعة' (9fecc602-5bd5-4c96-85ea-2b3e22762f94) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND c.foodics_id = '9fecc602-5bd5-4c96-85ea-2b3e22762f94'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'صوص جبنه' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d46d4af-a66e-44a9-8641-dc9dd6aae8b5' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرنشي راب ساندويش' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرنشي راب ساندويش' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرنشي راب ساندويش' <- 'علب راب  500' (9fde207e-2b71-40e1-98aa-bb901310141a) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND c.foodics_id = '9fde207e-2b71-40e1-98aa-bb901310141a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرنشي راب ساندويش' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرنشي راب ساندويش' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرنشي راب ساندويش' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=160
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 160
FROM products p, products c
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرنشي راب ساندويش' <- 'خبز تورتيلا' (9fe0c99d-6f81-430b-ae85-f416c5c2df84) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND c.foodics_id = '9fe0c99d-6f81-430b-ae85-f416c5c2df84'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرنشي راب ساندويش' <- 'خس ايسبرغ' (9fe0ca59-da4c-4534-a75e-b2a6b001db39) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND c.foodics_id = '9fe0ca59-da4c-4534-a75e-b2a6b001db39'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرنشي راب ساندويش' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كرنشي راب ساندويش' <- 'كياس شفاف مطبوعة' (9fecc602-5bd5-4c96-85ea-2b3e22762f94) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND c.foodics_id = '9fecc602-5bd5-4c96-85ea-2b3e22762f94'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'ورق صواني برجر 2000' (9fde09d0-2875-4bd5-b539-5677ecfacbdc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fde09d0-2875-4bd5-b539-5677ecfacbdc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'ورق تغليف   950' (9fde1774-8273-4bb0-a74c-718b81475982) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fde1774-8273-4bb0-a74c-718b81475982'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'علب راب  500' (9fde207e-2b71-40e1-98aa-bb901310141a) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fde207e-2b71-40e1-98aa-bb901310141a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'كياس سفري 150' (9fde31f5-c067-428c-b8c5-aa0034bed917) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fde31f5-c067-428c-b8c5-aa0034bed917'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=160
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 160
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'خبز تورتيلا' (9fe0c99d-6f81-430b-ae85-f416c5c2df84) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fe0c99d-6f81-430b-ae85-f416c5c2df84'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'خس ايسبرغ' (9fe0ca59-da4c-4534-a75e-b2a6b001db39) qty=15
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 15
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fe0ca59-da4c-4534-a75e-b2a6b001db39'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'وجبة كرنشي راب' <- 'كياس شفاف مطبوعة' (9fecc602-5bd5-4c96-85ea-2b3e22762f94) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND c.foodics_id = '9fecc602-5bd5-4c96-85ea-2b3e22762f94'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'كولسو' <- 'سلطه علبة كولو سلوا' (9fddf68b-9ada-4da5-820c-181074ec3f40) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9e667f5d-4a4e-47db-99e9-d3b4b3cbebce' AND c.foodics_id = '9fddf68b-9ada-4da5-820c-181074ec3f40'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'مثومة' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9e667f89-23d2-4645-bfda-5a7d59b7d731' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'خبزة للبروستد' <- 'خبزة بروستد' (9fe0d372-3fe4-4cd2-9475-370e0bac22bc) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9e667fb0-cced-4d77-b616-069fcea30b1e' AND c.foodics_id = '9fe0d372-3fe4-4cd2-9475-370e0bac22bc'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'فرينش فرايز' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9e668078-4d84-459a-98a3-c45f0b3f7d3a' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'فرينش فرايز' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9e668078-4d84-459a-98a3-c45f0b3f7d3a' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'فرقيه وجبه' <- 'علب بطاطا برجر 750' (9fde22e9-cd29-41b0-994b-6ebc272fb82d) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9f420c8e-1e7a-4438-af82-1d3a884a90b6' AND c.foodics_id = '9fde22e9-cd29-41b0-994b-6ebc272fb82d'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'فرقيه وجبه' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9f420c8e-1e7a-4438-af82-1d3a884a90b6' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'فرقيه وجبه' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9f420c8e-1e7a-4438-af82-1d3a884a90b6' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'فرقيه وجبه' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=2
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 2
FROM products p, products c
WHERE p.foodics_id = '9f420c8e-1e7a-4438-af82-1d3a884a90b6' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- menu item 'مشروب موظف' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = 'a05d8867-d8b2-46e5-b67c-03b55de9fed8' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'بافلو صوص' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be26191-cdc3-4e73-9ec3-ff3b2a1672be' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'تشيلي صوص' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be26191-d6c3-4bd4-a3fe-c9929fc8e179' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'سويت تشيلي صوص' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be26191-df30-44dc-9747-1c6bce27abbb' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'باربيكيو  صوص' <- 'علب صوص مشكل بالحبة جاهزة' (9fe828c6-2352-4b59-8730-076f2faf5821) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be26191-efe0-4d11-b8b4-1a1f5dc1559e' AND c.foodics_id = '9fe828c6-2352-4b59-8730-076f2faf5821'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'رانش صوص' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be26191-f822-464e-8960-412fce9e81d3' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'إضافة قطعة' <- 'كرسببي جاهز' (9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a) qty=80
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 80
FROM products p, products c
WHERE p.foodics_id = '9be26191-c56a-4f66-a605-ac56deebb81a' AND c.foodics_id = '9fdf8ae1-5d31-43ee-bc12-fe50f4fa6c0a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'خبزة بطاطا' <- 'خبز بطاطا  5 انش' (9fdf763b-7de0-4f85-88e2-f947e3adc638) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9c4f4c36-ce23-49a5-9171-2c9ce1753d65' AND c.foodics_id = '9fdf763b-7de0-4f85-88e2-f947e3adc638'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'اكسترا تشيز' <- 'جبنة شيدر اصفر شرائح' (9fdf76cd-292f-4443-8596-bf3418c5401f) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be26191-7391-461d-9ae1-ccbe2b7604ea' AND c.foodics_id = '9fdf76cd-292f-4443-8596-bf3418c5401f'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'زيادة صوص' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=58
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 58
FROM products p, products c
WHERE p.foodics_id = '9be26191-7df9-488f-a38a-daf024599397' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'بطاطا حلوة - تبديل' <- 'بطاطا حلوة' (9fde38ce-cd55-4a93-bc4b-0424fc61e868) qty=120
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 120
FROM products p, products c
WHERE p.foodics_id = '9be26191-86a5-4c24-9faa-2afcc0d0af4a' AND c.foodics_id = '9fde38ce-cd55-4a93-bc4b-0424fc61e868'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'بطاطا زيجي - تبديل' <- 'بطاطا زيجي' (9fe0ecf9-2cbd-412c-b29e-9d112e4df4d5) qty=120
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 120
FROM products p, products c
WHERE p.foodics_id = '9be26191-8e9e-4054-bf7b-bd7ec6423818' AND c.foodics_id = '9fe0ecf9-2cbd-412c-b29e-9d112e4df4d5'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'فرينش فرايز' <- 'فارم بطاطا 7*7 مغطاة بدون قشرة 2.5 كغ' (9fdf9615-1abf-47f0-8b5a-17fb40fa94e8) qty=120
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 120
FROM products p, products c
WHERE p.foodics_id = '9be26191-a117-4702-9e88-5cda0d556f7f' AND c.foodics_id = '9fdf9615-1abf-47f0-8b5a-17fb40fa94e8'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'بطاطا ويدجز - تبديل' <- 'بطاطا ويدجز' (9fe0edc1-ed5b-4323-92be-912a156a0b5a) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9be26191-a97d-4f06-bf55-5402ee08170b' AND c.foodics_id = '9fe0edc1-ed5b-4323-92be-912a156a0b5a'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'كيرلي فرايز - تبديل' <- 'كيرلي فرايز' (9fe0ee1c-af42-4ea1-8bd8-918c429244f2) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9be26191-b106-4750-8f38-57a9f9d0d5e4' AND c.foodics_id = '9fe0ee1c-af42-4ea1-8bd8-918c429244f2'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'بطاطا كرسكت - تبديل' <- 'بطاطا كرسكت' (9fe0ee61-1cb7-4df6-98f7-0da221aedb2e) qty=150
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 150
FROM products p, products c
WHERE p.foodics_id = '9be26191-bd6e-467a-8565-f2d9de750aeb' AND c.foodics_id = '9fe0ee61-1cb7-4df6-98f7-0da221aedb2e'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'جبنة سائلة' <- 'صوص بجمبع الانواع' (9fe7fff8-d72c-431f-aacc-89eb5249f4d9) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9d4438d3-22bf-4d0a-9331-c117a5860577' AND c.foodics_id = '9fe7fff8-d72c-431f-aacc-89eb5249f4d9'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'Cola' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be6d0d7-262c-4837-a018-b7317c92e981' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'Fanta' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be6d0ec-d68f-40a1-a70a-281e074417d0' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'Sprite' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be6d210-9652-43ff-852a-8b44cbaa6f24' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'Cola Zero' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be6d248-e932-4d78-a238-35626ee79ab3' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- add-on 'Diet sprite' <- 'ماتركس بكل الانواع' (9fde33c8-6609-4bf0-aa08-0cd11b814ceb) qty=1
INSERT INTO recipe_lines (parent_product_id, component_product_id, qty_per_unit)
SELECT p.id, c.id, 1
FROM products p, products c
WHERE p.foodics_id = '9be6d26f-9442-420c-90ff-43b5e4523849' AND c.foodics_id = '9fde33c8-6609-4bf0-aa08-0cd11b814ceb'
  AND NOT EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.parent_product_id = p.id AND rl.component_product_id = c.id);
-- total recipe_lines statements: 271

-- --- 5c. product_addon_categories (menu item -> add-on category) ---
-- menu item 'خبزة الثوم المحمص (٤ حبات)' offers add-on category 'خيارات خبز الثوم المحمص'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = 'a1f73bbc-34e6-41c1-8820-8ee780c6771c' AND ac.foodics_id = 'a1f73c14-9878-4fd6-ac1b-f3ee01535ea8'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات - كرسبي' offers add-on category 'Sauces'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = 'a10bf546-6fd5-44e7-9f77-cf509619cc45' AND ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات - كرسبي' offers add-on category 'Drinks'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 2
FROM products p, addon_categories ac
WHERE p.foodics_id = 'a10bf546-6fd5-44e7-9f77-cf509619cc45' AND ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات - كرسبي' offers add-on category 'اضافات بوكس الجمعات - كرسبي'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = 'a10bf546-6fd5-44e7-9f77-cf509619cc45' AND ac.foodics_id = 'a10bf5bf-8c1a-4ba0-8028-079a4dbced0f'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Sandwich' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Sandwich' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Sandwich' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Sandwich' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Sandwich' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Sandwich' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Sandwich' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Sandwich' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Sandwich' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Sandwich' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Sandwich' offers add-on category 'جايانت'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72' AND ac.foodics_id = '9be2606f-f35c-4ba9-95c8-396037dbebfc'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Meal' offers add-on category 'Sauces'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 2
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Meal' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Meal' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Meal' offers add-on category 'Drinks'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 3
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd' AND ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Meal' offers add-on category 'Sauces'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 3
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Meal' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Meal' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Meal' offers add-on category 'Drinks'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 2
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b' AND ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Meal' offers add-on category 'Sauces'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 2
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Meal' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Meal' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Meal' offers add-on category 'Drinks'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 3
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5' AND ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Meal' offers add-on category 'Sauces'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 2
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Meal' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Meal' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Meal' offers add-on category 'Drinks'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 3
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b' AND ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Meal' offers add-on category 'Sauces'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Meal' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 3
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Meal' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 4
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Meal' offers add-on category 'جايانت'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND ac.foodics_id = '9be2606f-f35c-4ba9-95c8-396037dbebfc'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Meal' offers add-on category 'Drinks'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 2
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108' AND ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153'
ON CONFLICT DO NOTHING;
-- menu item 'خمس أنواع صوص' offers add-on category 'Sauces'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b04-8956-4e46-96c4-bd29d098acd1' AND ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9'
ON CONFLICT DO NOTHING;
-- menu item '4 قطع ستريبس' offers add-on category 'Crispy adds'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26' AND ac.foodics_id = '9be25b51-2dfc-47f4-b940-89bb7ebfdb71'
ON CONFLICT DO NOTHING;
-- menu item '4 قطع ستريبس' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item '8 قطع ستريبس' offers add-on category 'Crispy adds'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85' AND ac.foodics_id = '9be25b51-2dfc-47f4-b940-89bb7ebfdb71'
ON CONFLICT DO NOTHING;
-- menu item '8 قطع ستريبس' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item '21 قطعة ستريبس' offers add-on category 'Crispy adds'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c' AND ac.foodics_id = '9be25b51-2dfc-47f4-b940-89bb7ebfdb71'
ON CONFLICT DO NOTHING;
-- menu item '21 قطعة ستريبس' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat Sandwich' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat Sandwich' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat meal' offers add-on category 'Sauces'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat meal' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat meal' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat meal' offers add-on category 'Drinks'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d' AND ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153'
ON CONFLICT DO NOTHING;
-- menu item 'Crispy Plate صحن كرسبي' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'Crispy Plate صحن كرسبي' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'Crispy Plate صحن كرسبي' offers add-on category 'Crispy Plate Options'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad' AND ac.foodics_id = '9d3c0d18-b434-48db-ba6c-b641004f3c34'
ON CONFLICT DO NOTHING;
-- menu item 'كرنشي راب ساندويش' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'كرنشي راب ساندويش' offers add-on category 'إضافات الراب'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f' AND ac.foodics_id = '9d6b13e7-839f-427e-b8cc-2265d9e49fda'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة كرنشي راب' offers add-on category 'Sauces'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة كرنشي راب' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 2
FROM products p, addon_categories ac
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة كرنشي راب' offers add-on category 'بدون'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 3
FROM products p, addon_categories ac
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND ac.foodics_id = '9be25bb5-ba28-4be9-a970-0546f844d555'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة كرنشي راب' offers add-on category 'Drinks'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 4
FROM products p, addon_categories ac
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة كرنشي راب' offers add-on category 'إضافات الراب'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87' AND ac.foodics_id = '9d6b13e7-839f-427e-b8cc-2265d9e49fda'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا سوبر سوبريم' offers add-on category 'الحجم'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e66723d-aaa6-414a-a73c-b852eb591e3e' AND ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا سوبر سوبريم' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e66723d-aaa6-414a-a73c-b852eb591e3e' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا سوبر سوبريم' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e66723d-aaa6-414a-a73c-b852eb591e3e' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باباروني' offers add-on category 'الحجم'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667367-ce56-4513-9c21-0810869c03c3' AND ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باباروني' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667367-ce56-4513-9c21-0810869c03c3' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باباروني' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667367-ce56-4513-9c21-0810869c03c3' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا مارغريتا' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e6674d6-4422-4de9-b6b8-f00a669d258e' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا مارغريتا' offers add-on category 'حجم (المارغريتا)'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e6674d6-4422-4de9-b6b8-f00a669d258e' AND ac.foodics_id = '9e708e43-4574-483b-ab93-e4b2d6da1d52'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا مارغريتا' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e6674d6-4422-4de9-b6b8-f00a669d258e' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا خضار' offers add-on category 'الحجم'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e66752f-b46b-4938-8aad-7887502b2d70' AND ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا خضار' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e66752f-b46b-4938-8aad-7887502b2d70' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا خضار' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e66752f-b46b-4938-8aad-7887502b2d70' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا خضار' offers add-on category 'بيتزا - بدون اضافة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e66752f-b46b-4938-8aad-7887502b2d70' AND ac.foodics_id = '9e90bdc2-f696-4ab0-b63d-2f9786abeaf6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا الفريدو' offers add-on category 'الحجم'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667591-e8a2-479a-ad27-7c51084bbd87' AND ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا الفريدو' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667591-e8a2-479a-ad27-7c51084bbd87' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا الفريدو' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667591-e8a2-479a-ad27-7c51084bbd87' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا الفريدو' offers add-on category 'بيتزا - بدون اضافة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667591-e8a2-479a-ad27-7c51084bbd87' AND ac.foodics_id = '9e90bdc2-f696-4ab0-b63d-2f9786abeaf6'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 4 قطع' offers add-on category 'اضافات بروستد'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e6676e2-e547-4e05-a233-5cc42a3d7476' AND ac.foodics_id = '9e667a0a-9187-43f7-aa8f-016d77cad146'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 4 قطع' offers add-on category 'درجة الحرارة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e6676e2-e547-4e05-a233-5cc42a3d7476' AND ac.foodics_id = '9e700ef7-1945-41f8-a5ce-101a65fef015'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 8 قطع' offers add-on category 'اضافات بروستد'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667894-5573-4bc0-aaa4-b4625253590c' AND ac.foodics_id = '9e667a0a-9187-43f7-aa8f-016d77cad146'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 8 قطع' offers add-on category 'درجة الحرارة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667894-5573-4bc0-aaa4-b4625253590c' AND ac.foodics_id = '9e700ef7-1945-41f8-a5ce-101a65fef015'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 12 قطعة' offers add-on category 'اضافات بروستد'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667caa-2c25-4d7e-96b3-ebd5012f1681' AND ac.foodics_id = '9e667a0a-9187-43f7-aa8f-016d77cad146'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 12 قطعة' offers add-on category 'درجة الحرارة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667caa-2c25-4d7e-96b3-ebd5012f1681' AND ac.foodics_id = '9e700ef7-1945-41f8-a5ce-101a65fef015'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 16 قطعة' offers add-on category 'اضافات بروستد'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667e37-6c24-4592-bb3e-b35a61ba8264' AND ac.foodics_id = '9e667a0a-9187-43f7-aa8f-016d77cad146'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 16 قطعة' offers add-on category 'درجة الحرارة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e667e37-6c24-4592-bb3e-b35a61ba8264' AND ac.foodics_id = '9e700ef7-1945-41f8-a5ce-101a65fef015'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باربيكيو' offers add-on category 'الحجم'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e6a5159-59cb-48e5-85de-a596d4b0520f' AND ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باربيكيو' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e6a5159-59cb-48e5-85de-a596d4b0520f' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باربيكيو' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9e6a5159-59cb-48e5-85de-a596d4b0520f' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا تشيلي بي' offers add-on category 'الحجم'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9ece8c1d-9fce-4671-8ac1-c7158136b49b' AND ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا تشيلي بي' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9ece8c1d-9fce-4671-8ac1-c7158136b49b' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا تشيلي بي' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9ece8c1d-9fce-4671-8ac1-c7158136b49b' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا تشيلي بي' offers add-on category 'بيتزا - بدون اضافة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9ece8c1d-9fce-4671-8ac1-c7158136b49b' AND ac.foodics_id = '9e90bdc2-f696-4ab0-b63d-2f9786abeaf6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا فلافي (الجديدة)' offers add-on category 'الحجم'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb59cda-cab6-4487-9691-088f078f0b94' AND ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا فلافي (الجديدة)' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb59cda-cab6-4487-9691-088f078f0b94' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا فلافي (الجديدة)' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb59cda-cab6-4487-9691-088f078f0b94' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا رانش (الجديدة)' offers add-on category 'الحجم'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb59ecb-29a0-4ac2-a16b-fdb6b2ae32b7' AND ac.foodics_id = '9e667267-6704-4caf-88ba-a118c3b420c5'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا رانش (الجديدة)' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb59ecb-29a0-4ac2-a16b-fdb6b2ae32b7' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا رانش (الجديدة)' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb59ecb-29a0-4ac2-a16b-fdb6b2ae32b7' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا رانش (الجديدة)' offers add-on category 'بيتزا - بدون اضافة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb59ecb-29a0-4ac2-a16b-fdb6b2ae32b7' AND ac.foodics_id = '9e90bdc2-f696-4ab0-b63d-2f9786abeaf6'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - صغير' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb631ca-41b9-41be-9c65-fea2fd4b20c1' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - صغير' offers add-on category 'انواع البيتزا (صغير)'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb631ca-41b9-41be-9c65-fea2fd4b20c1' AND ac.foodics_id = '9fb63379-cbe7-4686-b9f0-5c94a052a34d'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - وسط' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 2
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb6367d-dc62-409a-84a9-85bc7b1781e6' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - وسط' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 3
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb6367d-dc62-409a-84a9-85bc7b1781e6' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - وسط' offers add-on category 'انواع البيتزا (وسط)'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb6367d-dc62-409a-84a9-85bc7b1781e6' AND ac.foodics_id = '9fb63704-c43f-4e56-9d29-bb3cacf7fb76'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - كبير' offers add-on category 'نوع العجينة'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 2
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb63a29-3b0a-42e2-8799-daa9d350d9cb' AND ac.foodics_id = '9e6e1dca-8729-4c2a-b813-2cdc8e1b8588'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - كبير' offers add-on category 'إضافات البيتزا'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 3
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb63a29-3b0a-42e2-8799-daa9d350d9cb' AND ac.foodics_id = '9e7cbba2-d61c-47ab-8c2b-bdf1fc591ac6'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - كبير' offers add-on category 'انواع البيتزا (كبير)'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = '9fb63a29-3b0a-42e2-8799-daa9d350d9cb' AND ac.foodics_id = '9fb63a48-ed76-48e0-ae11-c84c375cb50d'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات' offers add-on category 'Sauces'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 1
FROM products p, addon_categories ac
WHERE p.foodics_id = 'a0df959a-3e25-4ad1-8581-c84e83f9a291' AND ac.foodics_id = '9be25b1c-8440-440f-8364-a7ee4981e7d9'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات' offers add-on category 'اضافات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 3
FROM products p, addon_categories ac
WHERE p.foodics_id = 'a0df959a-3e25-4ad1-8581-c84e83f9a291' AND ac.foodics_id = '9be25ba9-57e5-44cf-9752-b4639fc3a294'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات' offers add-on category 'Drinks'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 2
FROM products p, addon_categories ac
WHERE p.foodics_id = 'a0df959a-3e25-4ad1-8581-c84e83f9a291' AND ac.foodics_id = '9be6d07c-3b78-4eac-aa87-7a8856237153'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات' offers add-on category 'أنواع الساندويشات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 4
FROM products p, addon_categories ac
WHERE p.foodics_id = 'a0df959a-3e25-4ad1-8581-c84e83f9a291' AND ac.foodics_id = 'a0df96aa-a269-4dcd-b69f-21db1f07a422'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات' offers add-on category 'مقبلات'
INSERT INTO product_addon_categories (product_id, addon_category_id, sort_order)
SELECT p.id, ac.id, 0
FROM products p, addon_categories ac
WHERE p.foodics_id = 'a0df959a-3e25-4ad1-8581-c84e83f9a291' AND ac.foodics_id = 'a0df986d-df29-46ce-ba4a-e21bdaef36ae'
ON CONFLICT DO NOTHING;
-- total product_addon_categories rows: 111

-- --- 5d. product_locations (only for non-empty `branches` arrays) ---
-- All 4 currently-active (non-deleted) Foodics branches resolved cleanly
-- via location_aliases (source='foodics'). No unresolved branches.
-- menu item '3 كولسلو بدينار' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = 'a1f82420-7bcd-4748-9543-e1e1574ca5dd'
ON CONFLICT DO NOTHING;
-- menu item '3 كولسلو بدينار' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = 'a1f82420-7bcd-4748-9543-e1e1574ca5dd'
ON CONFLICT DO NOTHING;
-- menu item '3 كولسلو بدينار' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = 'a1f82420-7bcd-4748-9543-e1e1574ca5dd'
ON CONFLICT DO NOTHING;
-- menu item '3 كولسلو بدينار' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = 'a1f82420-7bcd-4748-9543-e1e1574ca5dd'
ON CONFLICT DO NOTHING;
-- menu item '3 مثومة بدينار' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = 'a1f81cdc-7116-40d9-911a-155e65fc2d54'
ON CONFLICT DO NOTHING;
-- menu item '3 مثومة بدينار' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = 'a1f81cdc-7116-40d9-911a-155e65fc2d54'
ON CONFLICT DO NOTHING;
-- menu item '3 مثومة بدينار' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = 'a1f81cdc-7116-40d9-911a-155e65fc2d54'
ON CONFLICT DO NOTHING;
-- menu item '3 مثومة بدينار' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = 'a1f81cdc-7116-40d9-911a-155e65fc2d54'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة الثوم المحمص (٤ حبات)' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = 'a1f73bbc-34e6-41c1-8820-8ee780c6771c'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة الثوم المحمص (٤ حبات)' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = 'a1f73bbc-34e6-41c1-8820-8ee780c6771c'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة الثوم المحمص (٤ حبات)' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = 'a1f73bbc-34e6-41c1-8820-8ee780c6771c'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة الثوم المحمص (٤ حبات)' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = 'a1f73bbc-34e6-41c1-8820-8ee780c6771c'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي ملك شيك - نكهة القهوة' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = 'a1df5853-1923-45a1-9fba-7463e71777e7'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي ملك شيك - نكهة القهوة' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = 'a1df5853-1923-45a1-9fba-7463e71777e7'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي ملك شيك - نكهة القهوة' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = 'a1df5853-1923-45a1-9fba-7463e71777e7'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي ملك شيك - نكهة القهوة' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = 'a1df5853-1923-45a1-9fba-7463e71777e7'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Ice Cream' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = 'a1d525fc-0b90-4ce3-9fdd-444f47b6910a'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Ice Cream' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = 'a1d525fc-0b90-4ce3-9fdd-444f47b6910a'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Ice Cream' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = 'a1d525fc-0b90-4ce3-9fdd-444f47b6910a'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Ice Cream' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = 'a1d525fc-0b90-4ce3-9fdd-444f47b6910a'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات - كرسبي' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = 'a10bf546-6fd5-44e7-9f77-cf509619cc45'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات - كرسبي' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = 'a10bf546-6fd5-44e7-9f77-cf509619cc45'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات - كرسبي' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = 'a10bf546-6fd5-44e7-9f77-cf509619cc45'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات - كرسبي' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = 'a10bf546-6fd5-44e7-9f77-cf509619cc45'
ON CONFLICT DO NOTHING;
-- menu item 'لازانيا' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = 'a032e0d9-f3fd-40a4-8237-db917ff617c8'
ON CONFLICT DO NOTHING;
-- menu item 'لازانيا' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = 'a032e0d9-f3fd-40a4-8237-db917ff617c8'
ON CONFLICT DO NOTHING;
-- menu item 'لازانيا' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = 'a032e0d9-f3fd-40a4-8237-db917ff617c8'
ON CONFLICT DO NOTHING;
-- menu item 'لازانيا' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = 'a032e0d9-f3fd-40a4-8237-db917ff617c8'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Sandwich' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Sandwich' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Sandwich' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Sandwich' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-2de1-41bd-b9a7-8cc3fe56ee6f'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Sandwich' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Sandwich' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Sandwich' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Sandwich' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-377e-4083-85b0-48ee5b38a1d7'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Sandwich' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Sandwich' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Sandwich' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Sandwich' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-415e-4ad6-90d1-34384055986c'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Sandwich' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Sandwich' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Sandwich' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Sandwich' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-4ad2-4605-8dff-f3277e471889'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Sandwich' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Sandwich' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Sandwich' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Sandwich' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-546c-4936-b1bb-90f1e4130e72'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Meal' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Meal' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Meal' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd'
ON CONFLICT DO NOTHING;
-- menu item 'Fluffy Burger Meal' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-5d34-43c9-a8bf-994e0404abfd'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Meal' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Meal' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Meal' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b'
ON CONFLICT DO NOTHING;
-- menu item 'Bee Burger Meal' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-66fb-48b9-bdcc-2706ca34a40b'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Meal' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Meal' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Meal' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5'
ON CONFLICT DO NOTHING;
-- menu item 'Classic Burger Meal' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-6f4f-4226-809d-ceaa6bdac7a5'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Meal' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Meal' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Meal' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b'
ON CONFLICT DO NOTHING;
-- menu item 'Chili Burger Meal' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-77c7-47f2-b8dd-540cdcea4a4b'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Meal' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Meal' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Meal' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108'
ON CONFLICT DO NOTHING;
-- menu item 'Giant Burger Meal' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-7ff6-4f39-9704-5a51037ce108'
ON CONFLICT DO NOTHING;
-- menu item 'خمس أنواع صوص' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-8956-4e46-96c4-bd29d098acd1'
ON CONFLICT DO NOTHING;
-- menu item 'خمس أنواع صوص' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-8956-4e46-96c4-bd29d098acd1'
ON CONFLICT DO NOTHING;
-- menu item 'خمس أنواع صوص' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-8956-4e46-96c4-bd29d098acd1'
ON CONFLICT DO NOTHING;
-- menu item 'خمس أنواع صوص' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-8956-4e46-96c4-bd29d098acd1'
ON CONFLICT DO NOTHING;
-- menu item 'بافلو صوص' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-9252-4354-af01-c556fa673a5a'
ON CONFLICT DO NOTHING;
-- menu item 'بافلو صوص' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-9252-4354-af01-c556fa673a5a'
ON CONFLICT DO NOTHING;
-- menu item 'بافلو صوص' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-9252-4354-af01-c556fa673a5a'
ON CONFLICT DO NOTHING;
-- menu item 'بافلو صوص' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-9252-4354-af01-c556fa673a5a'
ON CONFLICT DO NOTHING;
-- menu item 'تشيلي صوص' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-9be3-4ab2-a35e-7c0ad09b0224'
ON CONFLICT DO NOTHING;
-- menu item 'تشيلي صوص' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-9be3-4ab2-a35e-7c0ad09b0224'
ON CONFLICT DO NOTHING;
-- menu item 'تشيلي صوص' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-9be3-4ab2-a35e-7c0ad09b0224'
ON CONFLICT DO NOTHING;
-- menu item 'تشيلي صوص' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-9be3-4ab2-a35e-7c0ad09b0224'
ON CONFLICT DO NOTHING;
-- menu item 'سويت تشيلي صوص' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-a5a9-494d-ae3b-b6723b2c1b9d'
ON CONFLICT DO NOTHING;
-- menu item 'سويت تشيلي صوص' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-a5a9-494d-ae3b-b6723b2c1b9d'
ON CONFLICT DO NOTHING;
-- menu item 'سويت تشيلي صوص' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-a5a9-494d-ae3b-b6723b2c1b9d'
ON CONFLICT DO NOTHING;
-- menu item 'سويت تشيلي صوص' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-a5a9-494d-ae3b-b6723b2c1b9d'
ON CONFLICT DO NOTHING;
-- menu item 'هني ماسترد صوص' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-ae42-4ef9-b06c-aefaf1848abe'
ON CONFLICT DO NOTHING;
-- menu item 'هني ماسترد صوص' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-ae42-4ef9-b06c-aefaf1848abe'
ON CONFLICT DO NOTHING;
-- menu item 'هني ماسترد صوص' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-ae42-4ef9-b06c-aefaf1848abe'
ON CONFLICT DO NOTHING;
-- menu item 'هني ماسترد صوص' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-ae42-4ef9-b06c-aefaf1848abe'
ON CONFLICT DO NOTHING;
-- menu item 'باربيكيو  صوص' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-b79e-4019-8420-7c7bc3774306'
ON CONFLICT DO NOTHING;
-- menu item 'باربيكيو  صوص' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-b79e-4019-8420-7c7bc3774306'
ON CONFLICT DO NOTHING;
-- menu item 'باربيكيو  صوص' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-b79e-4019-8420-7c7bc3774306'
ON CONFLICT DO NOTHING;
-- menu item 'باربيكيو  صوص' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-b79e-4019-8420-7c7bc3774306'
ON CONFLICT DO NOTHING;
-- menu item 'رانش صوص' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-c152-43df-b934-6a036aa5b751'
ON CONFLICT DO NOTHING;
-- menu item 'رانش صوص' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-c152-43df-b934-6a036aa5b751'
ON CONFLICT DO NOTHING;
-- menu item 'رانش صوص' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-c152-43df-b934-6a036aa5b751'
ON CONFLICT DO NOTHING;
-- menu item 'رانش صوص' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-c152-43df-b934-6a036aa5b751'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي صوص' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-caf3-4572-9102-259a59a37478'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي صوص' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-caf3-4572-9102-259a59a37478'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي صوص' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-caf3-4572-9102-259a59a37478'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي صوص' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-caf3-4572-9102-259a59a37478'
ON CONFLICT DO NOTHING;
-- menu item 'موزريلا ستيكس' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-dd2f-4738-a950-49df060e7264'
ON CONFLICT DO NOTHING;
-- menu item 'موزريلا ستيكس' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-dd2f-4738-a950-49df060e7264'
ON CONFLICT DO NOTHING;
-- menu item 'موزريلا ستيكس' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-dd2f-4738-a950-49df060e7264'
ON CONFLICT DO NOTHING;
-- menu item 'موزريلا ستيكس' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-dd2f-4738-a950-49df060e7264'
ON CONFLICT DO NOTHING;
-- menu item 'حلقات البصل' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b04-e7fa-4961-87c3-fb00b68fba43'
ON CONFLICT DO NOTHING;
-- menu item 'حلقات البصل' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b04-e7fa-4961-87c3-fb00b68fba43'
ON CONFLICT DO NOTHING;
-- menu item 'حلقات البصل' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b04-e7fa-4961-87c3-fb00b68fba43'
ON CONFLICT DO NOTHING;
-- menu item 'حلقات البصل' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b04-e7fa-4961-87c3-fb00b68fba43'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا حلوة' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b05-001d-4cda-b9e4-54e8a65f2b96'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا حلوة' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b05-001d-4cda-b9e4-54e8a65f2b96'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا حلوة' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b05-001d-4cda-b9e4-54e8a65f2b96'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا حلوة' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b05-001d-4cda-b9e4-54e8a65f2b96'
ON CONFLICT DO NOTHING;
-- menu item 'فرينش فرايز' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b05-25c9-43e6-99d2-29cbf33100b7'
ON CONFLICT DO NOTHING;
-- menu item 'فرينش فرايز' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b05-25c9-43e6-99d2-29cbf33100b7'
ON CONFLICT DO NOTHING;
-- menu item 'فرينش فرايز' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b05-25c9-43e6-99d2-29cbf33100b7'
ON CONFLICT DO NOTHING;
-- menu item 'فرينش فرايز' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b05-25c9-43e6-99d2-29cbf33100b7'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا ويدجز' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b05-2e69-4a2a-a857-bef1e16e2879'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا ويدجز' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b05-2e69-4a2a-a857-bef1e16e2879'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا ويدجز' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b05-2e69-4a2a-a857-bef1e16e2879'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا ويدجز' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b05-2e69-4a2a-a857-bef1e16e2879'
ON CONFLICT DO NOTHING;
-- menu item 'كيرلي فرايز' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b05-37fe-4551-9b90-aff8cb277d9b'
ON CONFLICT DO NOTHING;
-- menu item 'كيرلي فرايز' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b05-37fe-4551-9b90-aff8cb277d9b'
ON CONFLICT DO NOTHING;
-- menu item 'كيرلي فرايز' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b05-37fe-4551-9b90-aff8cb277d9b'
ON CONFLICT DO NOTHING;
-- menu item 'كيرلي فرايز' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b05-37fe-4551-9b90-aff8cb277d9b'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا كرسكت' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b05-4bfa-4856-83f0-3b1125700b06'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا كرسكت' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b05-4bfa-4856-83f0-3b1125700b06'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا كرسكت' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b05-4bfa-4856-83f0-3b1125700b06'
ON CONFLICT DO NOTHING;
-- menu item 'بطاطا كرسكت' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b05-4bfa-4856-83f0-3b1125700b06'
ON CONFLICT DO NOTHING;
-- menu item '4 قطع ستريبس' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26'
ON CONFLICT DO NOTHING;
-- menu item '4 قطع ستريبس' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26'
ON CONFLICT DO NOTHING;
-- menu item '4 قطع ستريبس' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26'
ON CONFLICT DO NOTHING;
-- menu item '4 قطع ستريبس' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b05-5459-45c8-baa6-ec8e57afbd26'
ON CONFLICT DO NOTHING;
-- menu item '8 قطع ستريبس' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85'
ON CONFLICT DO NOTHING;
-- menu item '8 قطع ستريبس' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85'
ON CONFLICT DO NOTHING;
-- menu item '8 قطع ستريبس' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85'
ON CONFLICT DO NOTHING;
-- menu item '8 قطع ستريبس' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b05-5d57-4027-9071-d19ad8d8ee85'
ON CONFLICT DO NOTHING;
-- menu item '21 قطعة ستريبس' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c'
ON CONFLICT DO NOTHING;
-- menu item '21 قطعة ستريبس' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c'
ON CONFLICT DO NOTHING;
-- menu item '21 قطعة ستريبس' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c'
ON CONFLICT DO NOTHING;
-- menu item '21 قطعة ستريبس' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b05-66e0-4859-b6c7-cc807d966a2c'
ON CONFLICT DO NOTHING;
-- menu item 'مشروب غازي' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b05-70c1-4e86-9a01-24d6db9d9687'
ON CONFLICT DO NOTHING;
-- menu item 'مشروب غازي' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b05-70c1-4e86-9a01-24d6db9d9687'
ON CONFLICT DO NOTHING;
-- menu item 'مشروب غازي' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b05-70c1-4e86-9a01-24d6db9d9687'
ON CONFLICT DO NOTHING;
-- menu item 'مشروب غازي' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b05-70c1-4e86-9a01-24d6db9d9687'
ON CONFLICT DO NOTHING;
-- menu item 'ماء' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9be25b05-795e-4bc8-af41-0ee25b4669a3'
ON CONFLICT DO NOTHING;
-- menu item 'ماء' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9be25b05-795e-4bc8-af41-0ee25b4669a3'
ON CONFLICT DO NOTHING;
-- menu item 'ماء' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9be25b05-795e-4bc8-af41-0ee25b4669a3'
ON CONFLICT DO NOTHING;
-- menu item 'ماء' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9be25b05-795e-4bc8-af41-0ee25b4669a3'
ON CONFLICT DO NOTHING;
-- menu item 'كرات تشيلي تشيز' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9c009a98-80eb-493e-bec7-5e1d2da035cd'
ON CONFLICT DO NOTHING;
-- menu item 'كرات تشيلي تشيز' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9c009a98-80eb-493e-bec7-5e1d2da035cd'
ON CONFLICT DO NOTHING;
-- menu item 'كرات تشيلي تشيز' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9c009a98-80eb-493e-bec7-5e1d2da035cd'
ON CONFLICT DO NOTHING;
-- menu item 'كرات تشيلي تشيز' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9c009a98-80eb-493e-bec7-5e1d2da035cd'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي صوص' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9c03e8ea-29fc-40c2-8315-4412789e499f'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي صوص' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9c03e8ea-29fc-40c2-8315-4412789e499f'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي صوص' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9c03e8ea-29fc-40c2-8315-4412789e499f'
ON CONFLICT DO NOTHING;
-- menu item 'فلافي صوص' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9c03e8ea-29fc-40c2-8315-4412789e499f'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat Sandwich' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat Sandwich' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat Sandwich' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat Sandwich' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9c0832ce-104e-4109-a2bb-dd73379bdc5d'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat meal' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat meal' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat meal' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d'
ON CONFLICT DO NOTHING;
-- menu item 'Sweet Heat meal' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9c083460-9db0-4aab-a4b0-d1faaa238f2d'
ON CONFLICT DO NOTHING;
-- menu item 'ملاحظة عامة للمطبخ' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9c15f8de-44b6-45bc-80eb-b361ead7db94'
ON CONFLICT DO NOTHING;
-- menu item 'ملاحظة عامة للمطبخ' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9c15f8de-44b6-45bc-80eb-b361ead7db94'
ON CONFLICT DO NOTHING;
-- menu item 'ملاحظة عامة للمطبخ' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9c15f8de-44b6-45bc-80eb-b361ead7db94'
ON CONFLICT DO NOTHING;
-- menu item 'ملاحظة عامة للمطبخ' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9c15f8de-44b6-45bc-80eb-b361ead7db94'
ON CONFLICT DO NOTHING;
-- menu item 'حبة كرسبي' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9c190b45-f68d-46b5-8666-3af01afbaffc'
ON CONFLICT DO NOTHING;
-- menu item 'حبة كرسبي' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9c190b45-f68d-46b5-8666-3af01afbaffc'
ON CONFLICT DO NOTHING;
-- menu item 'حبة كرسبي' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9c190b45-f68d-46b5-8666-3af01afbaffc'
ON CONFLICT DO NOTHING;
-- menu item 'حبة كرسبي' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9c190b45-f68d-46b5-8666-3af01afbaffc'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة بطاطا' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9c4f4d23-4475-4740-b142-5bfc4e6fd671'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة بطاطا' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9c4f4d23-4475-4740-b142-5bfc4e6fd671'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة بطاطا' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9c4f4d23-4475-4740-b142-5bfc4e6fd671'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة بطاطا' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9c4f4d23-4475-4740-b142-5bfc4e6fd671'
ON CONFLICT DO NOTHING;
-- menu item 'عصير' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9cbb9998-702a-42fc-87e1-088a06d371b1'
ON CONFLICT DO NOTHING;
-- menu item 'عصير' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9cbb9998-702a-42fc-87e1-088a06d371b1'
ON CONFLICT DO NOTHING;
-- menu item 'عصير' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9cbb9998-702a-42fc-87e1-088a06d371b1'
ON CONFLICT DO NOTHING;
-- menu item 'عصير' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9cbb9998-702a-42fc-87e1-088a06d371b1'
ON CONFLICT DO NOTHING;
-- menu item 'Crispy Plate صحن كرسبي' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad'
ON CONFLICT DO NOTHING;
-- menu item 'Crispy Plate صحن كرسبي' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad'
ON CONFLICT DO NOTHING;
-- menu item 'Crispy Plate صحن كرسبي' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad'
ON CONFLICT DO NOTHING;
-- menu item 'Crispy Plate صحن كرسبي' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9d3c0ca5-fca9-4e26-88ba-04175e06cfad'
ON CONFLICT DO NOTHING;
-- menu item 'صوص جبنه' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9d46d4af-a66e-44a9-8641-dc9dd6aae8b5'
ON CONFLICT DO NOTHING;
-- menu item 'صوص جبنه' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9d46d4af-a66e-44a9-8641-dc9dd6aae8b5'
ON CONFLICT DO NOTHING;
-- menu item 'صوص جبنه' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9d46d4af-a66e-44a9-8641-dc9dd6aae8b5'
ON CONFLICT DO NOTHING;
-- menu item 'صوص جبنه' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9d46d4af-a66e-44a9-8641-dc9dd6aae8b5'
ON CONFLICT DO NOTHING;
-- menu item 'كرنشي راب ساندويش' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f'
ON CONFLICT DO NOTHING;
-- menu item 'كرنشي راب ساندويش' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f'
ON CONFLICT DO NOTHING;
-- menu item 'كرنشي راب ساندويش' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f'
ON CONFLICT DO NOTHING;
-- menu item 'كرنشي راب ساندويش' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9d690f1f-29f1-47e6-8b52-d663b4bb776f'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة كرنشي راب' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة كرنشي راب' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة كرنشي راب' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة كرنشي راب' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9d690f6c-d16d-4e71-9574-52056e8bcf87'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا سوبر سوبريم' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e66723d-aaa6-414a-a73c-b852eb591e3e'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا سوبر سوبريم' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e66723d-aaa6-414a-a73c-b852eb591e3e'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا سوبر سوبريم' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e66723d-aaa6-414a-a73c-b852eb591e3e'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا سوبر سوبريم' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e66723d-aaa6-414a-a73c-b852eb591e3e'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باباروني' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e667367-ce56-4513-9c21-0810869c03c3'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باباروني' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e667367-ce56-4513-9c21-0810869c03c3'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باباروني' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e667367-ce56-4513-9c21-0810869c03c3'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باباروني' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e667367-ce56-4513-9c21-0810869c03c3'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا مارغريتا' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e6674d6-4422-4de9-b6b8-f00a669d258e'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا مارغريتا' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e6674d6-4422-4de9-b6b8-f00a669d258e'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا مارغريتا' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e6674d6-4422-4de9-b6b8-f00a669d258e'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا مارغريتا' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e6674d6-4422-4de9-b6b8-f00a669d258e'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا خضار' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e66752f-b46b-4938-8aad-7887502b2d70'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا خضار' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e66752f-b46b-4938-8aad-7887502b2d70'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا خضار' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e66752f-b46b-4938-8aad-7887502b2d70'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا خضار' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e66752f-b46b-4938-8aad-7887502b2d70'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا الفريدو' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e667591-e8a2-479a-ad27-7c51084bbd87'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا الفريدو' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e667591-e8a2-479a-ad27-7c51084bbd87'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا الفريدو' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e667591-e8a2-479a-ad27-7c51084bbd87'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا الفريدو' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e667591-e8a2-479a-ad27-7c51084bbd87'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 4 قطع' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e6676e2-e547-4e05-a233-5cc42a3d7476'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 4 قطع' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e6676e2-e547-4e05-a233-5cc42a3d7476'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 4 قطع' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e6676e2-e547-4e05-a233-5cc42a3d7476'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 4 قطع' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e6676e2-e547-4e05-a233-5cc42a3d7476'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 8 قطع' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e667894-5573-4bc0-aaa4-b4625253590c'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 8 قطع' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e667894-5573-4bc0-aaa4-b4625253590c'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 8 قطع' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e667894-5573-4bc0-aaa4-b4625253590c'
ON CONFLICT DO NOTHING;
-- menu item 'وجبة بروستد 8 قطع' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e667894-5573-4bc0-aaa4-b4625253590c'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 12 قطعة' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e667caa-2c25-4d7e-96b3-ebd5012f1681'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 12 قطعة' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e667caa-2c25-4d7e-96b3-ebd5012f1681'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 12 قطعة' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e667caa-2c25-4d7e-96b3-ebd5012f1681'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 12 قطعة' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e667caa-2c25-4d7e-96b3-ebd5012f1681'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 16 قطعة' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e667e37-6c24-4592-bb3e-b35a61ba8264'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 16 قطعة' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e667e37-6c24-4592-bb3e-b35a61ba8264'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 16 قطعة' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e667e37-6c24-4592-bb3e-b35a61ba8264'
ON CONFLICT DO NOTHING;
-- menu item 'بروستد 16 قطعة' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e667e37-6c24-4592-bb3e-b35a61ba8264'
ON CONFLICT DO NOTHING;
-- menu item 'كولسو' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e667f5d-4a4e-47db-99e9-d3b4b3cbebce'
ON CONFLICT DO NOTHING;
-- menu item 'كولسو' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e667f5d-4a4e-47db-99e9-d3b4b3cbebce'
ON CONFLICT DO NOTHING;
-- menu item 'كولسو' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e667f5d-4a4e-47db-99e9-d3b4b3cbebce'
ON CONFLICT DO NOTHING;
-- menu item 'كولسو' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e667f5d-4a4e-47db-99e9-d3b4b3cbebce'
ON CONFLICT DO NOTHING;
-- menu item 'مثومة' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e667f89-23d2-4645-bfda-5a7d59b7d731'
ON CONFLICT DO NOTHING;
-- menu item 'مثومة' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e667f89-23d2-4645-bfda-5a7d59b7d731'
ON CONFLICT DO NOTHING;
-- menu item 'مثومة' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e667f89-23d2-4645-bfda-5a7d59b7d731'
ON CONFLICT DO NOTHING;
-- menu item 'مثومة' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e667f89-23d2-4645-bfda-5a7d59b7d731'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة للبروستد' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e667fb0-cced-4d77-b616-069fcea30b1e'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة للبروستد' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e667fb0-cced-4d77-b616-069fcea30b1e'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة للبروستد' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e667fb0-cced-4d77-b616-069fcea30b1e'
ON CONFLICT DO NOTHING;
-- menu item 'خبزة للبروستد' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e667fb0-cced-4d77-b616-069fcea30b1e'
ON CONFLICT DO NOTHING;
-- menu item 'فرينش فرايز' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e668078-4d84-459a-98a3-c45f0b3f7d3a'
ON CONFLICT DO NOTHING;
-- menu item 'فرينش فرايز' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e668078-4d84-459a-98a3-c45f0b3f7d3a'
ON CONFLICT DO NOTHING;
-- menu item 'فرينش فرايز' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e668078-4d84-459a-98a3-c45f0b3f7d3a'
ON CONFLICT DO NOTHING;
-- menu item 'فرينش فرايز' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e668078-4d84-459a-98a3-c45f0b3f7d3a'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باربيكيو' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9e6a5159-59cb-48e5-85de-a596d4b0520f'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باربيكيو' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9e6a5159-59cb-48e5-85de-a596d4b0520f'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باربيكيو' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9e6a5159-59cb-48e5-85de-a596d4b0520f'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا باربيكيو' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9e6a5159-59cb-48e5-85de-a596d4b0520f'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا تشيلي بي' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9ece8c1d-9fce-4671-8ac1-c7158136b49b'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا تشيلي بي' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9ece8c1d-9fce-4671-8ac1-c7158136b49b'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا تشيلي بي' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9ece8c1d-9fce-4671-8ac1-c7158136b49b'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا تشيلي بي' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9ece8c1d-9fce-4671-8ac1-c7158136b49b'
ON CONFLICT DO NOTHING;
-- menu item 'فرقيه وجبه' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9f420c8e-1e7a-4438-af82-1d3a884a90b6'
ON CONFLICT DO NOTHING;
-- menu item 'فرقيه وجبه' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9f420c8e-1e7a-4438-af82-1d3a884a90b6'
ON CONFLICT DO NOTHING;
-- menu item 'فرقيه وجبه' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9f420c8e-1e7a-4438-af82-1d3a884a90b6'
ON CONFLICT DO NOTHING;
-- menu item 'فرقيه وجبه' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9f420c8e-1e7a-4438-af82-1d3a884a90b6'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا فلافي (الجديدة)' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9fb59cda-cab6-4487-9691-088f078f0b94'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا فلافي (الجديدة)' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9fb59cda-cab6-4487-9691-088f078f0b94'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا فلافي (الجديدة)' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9fb59cda-cab6-4487-9691-088f078f0b94'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا فلافي (الجديدة)' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9fb59cda-cab6-4487-9691-088f078f0b94'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا رانش (الجديدة)' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9fb59ecb-29a0-4ac2-a16b-fdb6b2ae32b7'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا رانش (الجديدة)' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9fb59ecb-29a0-4ac2-a16b-fdb6b2ae32b7'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا رانش (الجديدة)' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9fb59ecb-29a0-4ac2-a16b-fdb6b2ae32b7'
ON CONFLICT DO NOTHING;
-- menu item 'بيتزا رانش (الجديدة)' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9fb59ecb-29a0-4ac2-a16b-fdb6b2ae32b7'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - صغير' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9fb631ca-41b9-41be-9c65-fea2fd4b20c1'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - صغير' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9fb631ca-41b9-41be-9c65-fea2fd4b20c1'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - صغير' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9fb631ca-41b9-41be-9c65-fea2fd4b20c1'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - صغير' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9fb631ca-41b9-41be-9c65-fea2fd4b20c1'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - وسط' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9fb6367d-dc62-409a-84a9-85bc7b1781e6'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - وسط' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9fb6367d-dc62-409a-84a9-85bc7b1781e6'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - وسط' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9fb6367d-dc62-409a-84a9-85bc7b1781e6'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - وسط' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9fb6367d-dc62-409a-84a9-85bc7b1781e6'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - كبير' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = '9fb63a29-3b0a-42e2-8799-daa9d350d9cb'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - كبير' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = '9fb63a29-3b0a-42e2-8799-daa9d350d9cb'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - كبير' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = '9fb63a29-3b0a-42e2-8799-daa9d350d9cb'
ON CONFLICT DO NOTHING;
-- menu item 'عرض ال 3 بيتزا - كبير' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = '9fb63a29-3b0a-42e2-8799-daa9d350d9cb'
ON CONFLICT DO NOTHING;
-- menu item 'اصنع البيتزا الخاصة بي' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = 'a02d1849-be95-464c-be18-5a8b5c4dd270'
ON CONFLICT DO NOTHING;
-- menu item 'اصنع البيتزا الخاصة بي' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = 'a02d1849-be95-464c-be18-5a8b5c4dd270'
ON CONFLICT DO NOTHING;
-- menu item 'اصنع البيتزا الخاصة بي' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = 'a02d1849-be95-464c-be18-5a8b5c4dd270'
ON CONFLICT DO NOTHING;
-- menu item 'اصنع البيتزا الخاصة بي' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = 'a02d1849-be95-464c-be18-5a8b5c4dd270'
ON CONFLICT DO NOTHING;
-- menu item 'مشروب موظف' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = 'a05d8867-d8b2-46e5-b67c-03b55de9fed8'
ON CONFLICT DO NOTHING;
-- menu item 'مشروب موظف' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = 'a05d8867-d8b2-46e5-b67c-03b55de9fed8'
ON CONFLICT DO NOTHING;
-- menu item 'مشروب موظف' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = 'a05d8867-d8b2-46e5-b67c-03b55de9fed8'
ON CONFLICT DO NOTHING;
-- menu item 'مشروب موظف' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = 'a05d8867-d8b2-46e5-b67c-03b55de9fed8'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات' restricted to branch 'Fluffy Burger Zarqa- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '3f52fa09-c820-46dd-a11d-5f70e8be69c9'
FROM products p WHERE p.foodics_id = 'a0df959a-3e25-4ad1-8581-c84e83f9a291'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات' restricted to branch 'Fluffy Burger Rabyeh- New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '2551caee-190c-4e5d-a026-44c5905ca65d'
FROM products p WHERE p.foodics_id = 'a0df959a-3e25-4ad1-8581-c84e83f9a291'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات' restricted to branch 'Fluffy Fry and Pie - New'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, 'b3e0fc5a-ba5b-482c-8dc7-6aba45067e0d'
FROM products p WHERE p.foodics_id = 'a0df959a-3e25-4ad1-8581-c84e83f9a291'
ON CONFLICT DO NOTHING;
-- menu item 'بوكس الجمعات' restricted to branch 'Fluffy Burger Jubaiha'
INSERT INTO product_locations (product_id, location_id)
SELECT p.id, '8ac620c9-6206-4cdc-b79a-a0b1a0be5cf1'
FROM products p WHERE p.foodics_id = 'a0df959a-3e25-4ad1-8581-c84e83f9a291'
ON CONFLICT DO NOTHING;
-- total product_locations rows: 292

COMMIT;