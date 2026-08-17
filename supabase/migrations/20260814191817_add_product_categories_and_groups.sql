-- Normalizes the free-text products.category into a real table (mirrors
-- Foodics' own "Categories" concept, and fixes existing case-duplicates
-- from mixing pre-existing curated data with the Foodics import, e.g.
-- 'Pizza'/'pizza', 'Sauces'/'sauces'). Also adds product_groups, a
-- separate many-to-many tagging concept the business uses independently
-- of category and of add-on categories, for reporting/filtering/POS
-- display purposes.

CREATE TABLE product_categories (
  id uuid primary key default gen_random_uuid(),
  name_en text not null,
  name_ar text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

INSERT INTO product_categories (name_en, name_ar, sort_order) VALUES
  ('Boxes','بوكسات',0),
  ('Broasted','بروستد',1),
  ('Burgers','برجر',2),
  ('Crispy Chicken Strips','سترپس دجاج كرسبي',3),
  ('Drinks','مشروبات',4),
  ('Fries','بطاطا',5),
  ('Meals','وجبات',6),
  ('Offers','عروض',7),
  ('Pasta','باستا',8),
  ('Pizza','بيتزا',9),
  ('Sauces','صوصات',10),
  ('Sides','أطباق جانبية',11),
  ('Snacks','سناكس',12),
  ('Strips','سترپس',13),
  ('Sweets','حلويات',14),
  ('Wraps','راب',15);

ALTER TABLE products ADD COLUMN category_id uuid REFERENCES product_categories(id);

UPDATE products p SET category_id = pc.id
FROM product_categories pc
WHERE lower(trim(p.category)) = lower(pc.name_en);

ALTER TABLE products DROP COLUMN category;

CREATE TABLE product_groups (
  id uuid primary key default gen_random_uuid(),
  name_en text not null,
  name_ar text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

CREATE TABLE product_group_members (
  product_id uuid not null references products(id) on delete cascade,
  group_id uuid not null references product_groups(id) on delete cascade,
  primary key (product_id, group_id)
);
CREATE INDEX product_group_members_group_idx ON product_group_members(group_id);

ALTER TABLE product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_group_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY ref_read_product_categories ON product_categories FOR SELECT USING (true);
CREATE POLICY admin_all_product_categories ON product_categories FOR ALL USING (my_role()='admin') WITH CHECK (my_role()='admin');
CREATE POLICY ref_read_product_groups ON product_groups FOR SELECT USING (true);
CREATE POLICY admin_all_product_groups ON product_groups FOR ALL USING (my_role()='admin') WITH CHECK (my_role()='admin');
CREATE POLICY ref_read_product_group_members ON product_group_members FOR SELECT USING (true);
CREATE POLICY admin_all_product_group_members ON product_group_members FOR ALL USING (my_role()='admin') WITH CHECK (my_role()='admin');
