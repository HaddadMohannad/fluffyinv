-- Menu/add-on management: add-ons are products (their own price, optional
-- recipe, optional branch restriction) grouped into add-on categories
-- (Foodics "modifier groups"), which are in turn attached to menu items.
-- Branch applicability for any product (menu item or add-on) is opt-in via
-- product_locations: no rows = available at every branch (matches Foodics'
-- own "empty branches list = unrestricted" convention), rows = restricted
-- to just those branches. recipe_unit/storage_to_recipe_factor let a
-- recipe_lines.qty_per_unit be expressed in a finer unit than the
-- component's storage unit (e.g. 100 grams of a product stored in kg);
-- divide by the factor to get the storage-unit qty to deduct.

ALTER TABLE products
  ADD COLUMN is_addon boolean NOT NULL DEFAULT false,
  ADD COLUMN foodics_id text UNIQUE,
  ADD COLUMN sku text,
  ADD COLUMN recipe_unit text,
  ADD COLUMN storage_to_recipe_factor numeric NOT NULL DEFAULT 1;

CREATE TABLE addon_categories (
  id uuid primary key default gen_random_uuid(),
  name_en text not null,
  name_ar text not null,
  foodics_id text unique,
  is_ready boolean not null default true,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

CREATE TABLE product_addon_categories (
  product_id uuid not null references products(id) on delete cascade,
  addon_category_id uuid not null references addon_categories(id) on delete cascade,
  sort_order integer not null default 0,
  primary key (product_id, addon_category_id)
);

CREATE TABLE addon_category_options (
  addon_category_id uuid not null references addon_categories(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  sort_order integer not null default 0,
  primary key (addon_category_id, product_id)
);

CREATE TABLE product_locations (
  product_id uuid not null references products(id) on delete cascade,
  location_id uuid not null references locations(id) on delete cascade,
  primary key (product_id, location_id)
);

CREATE INDEX product_addon_categories_category_idx ON product_addon_categories(addon_category_id);
CREATE INDEX addon_category_options_category_idx ON addon_category_options(addon_category_id);
CREATE INDEX product_locations_location_idx ON product_locations(location_id);

ALTER TABLE addon_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_addon_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE addon_category_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY ref_read_addon_categories ON addon_categories FOR SELECT USING (true);
CREATE POLICY admin_all_addon_categories ON addon_categories FOR ALL USING (my_role() = 'admin') WITH CHECK (my_role() = 'admin');

CREATE POLICY ref_read_product_addon_categories ON product_addon_categories FOR SELECT USING (true);
CREATE POLICY admin_all_product_addon_categories ON product_addon_categories FOR ALL USING (my_role() = 'admin') WITH CHECK (my_role() = 'admin');

CREATE POLICY ref_read_addon_category_options ON addon_category_options FOR SELECT USING (true);
CREATE POLICY admin_all_addon_category_options ON addon_category_options FOR ALL USING (my_role() = 'admin') WITH CHECK (my_role() = 'admin');

CREATE POLICY ref_read_product_locations ON product_locations FOR SELECT USING (true);
CREATE POLICY admin_all_product_locations ON product_locations FOR ALL USING (my_role() = 'admin') WITH CHECK (my_role() = 'admin');
