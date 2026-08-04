-- FLU-13: seed high-confidence raw-name -> product mappings derived from
-- inspecting a real July Talabat export (2,500 orders) against the live
-- products catalog. Each mapping here is a deterministic naming/spelling
-- difference (e.g. "B. Burger" = "Bee Burger", pizza size/spice variants
-- that aren't separate SKUs) verified against the real file -- 94.6% of
-- parsed line-item quantity matches with this seed applied. Genuinely
-- ambiguous items (e.g. "Chili Balls" vs "Chili Cheese Balls", "Shelby
-- Pizza" which has no catalog product at all) are deliberately left
-- unmapped for an admin to resolve via the product-alias UI.
insert into product_aliases (raw_name, product_id)
select v.raw_name, p.id
from (values
  ('Sweet Heat Burger Meal', 'Sweet Heat Meal'),
  ('Sweet Heat Burger Sandwich', 'Sweet Heat Sandwich'),
  ('B. Burger Meal', 'Bee Burger Meal'),
  ('B. Burger Sandwich', 'Bee Burger Sandwich'),
  ('4 pcs Crispy', 'Crispy Strips 4pc'),
  ('8 pcs Crispy', 'Crispy Strips 8pc'),
  ('8 Pieces Crispy', 'Crispy Strips 8pc'),
  ('Mozzarella Sticks', 'Mozzarella Sticks 4pc'),
  ('Matrix Cola', 'Soft Drink'),
  ('Matrix Zero Cola', 'Soft Drink'),
  ('Matrix Cola Zero', 'Soft Drink'),
  ('Matrix Up', 'Soft Drink'),
  ('Matrix Up Zero', 'Soft Drink'),
  ('Matrix Orange', 'Soft Drink'),
  ('4 Piece Chicken Box', 'Broasted 4pc Box'),
  ('8 Piece Chicken Box', 'Broasted 8pc Box'),
  ('12 Piece Chicken Box', 'Broasted 12pc Box'),
  ('16 Piece Chicken Box', 'Broasted 16pc Box'),
  ('Crunchy Wrap - Ranch Sandwich', 'Crunchy Wrap Sandwich'),
  ('Crunchy Wrap - Ranch Meal', 'Crunchy Wrap Meal'),
  ('Crunchy Wrap - Sweet Heat Sandwich', 'Crunchy Wrap Sandwich'),
  ('Crunchy Wrap - Sweet Heat Meal', 'Crunchy Wrap Meal'),
  ('Crunchy Wrap - Chili Sandwich', 'Crunchy Wrap Sandwich'),
  ('Crunchy Wrap - Chili Meal', 'Crunchy Wrap Meal'),
  ('Fluffy Cubes (Sweet Heat)', 'Fluffy Cubes'),
  ('Fluffy Cubes (Ranch)', 'Fluffy Cubes'),
  ('Garlic sauce', 'Garlic Dip'),
  ('Coleslaw Salad', 'Coleslaw'),
  ('Ranch', 'Ranch Sauce'),
  ('Honey Mustard', 'Honey Mustard Sauce'),
  ('Small size pizza combo', '3-Pizza Offer S'),
  ('Medium size pizza combo', '3-Pizza Offer M'),
  ('Large Pizza Combo', '3-Pizza Offer L'),
  ('Chili Cheese Balls', 'Chili Cheese Balls 5pc'),
  ('Bread roll', 'Broasted Bread'),
  ('Onion Rings', 'Onion Rings 6pc'),
  ('Wedges fries', 'Potato Wedges'),
  ('Sweet potato', 'Sweet Potato Fries'),
  ('Ranch Pizza Small', 'Spicy Ranch Pizza S'),
  ('Ranch Pizza Medium', 'Spicy Ranch Pizza M'),
  ('Ranch Pizza Large', 'Spicy Ranch Pizza L'),
  ('BBQ Pizza Medium', 'Barbecue Pizza M'),
  ('BBQ Pizza Small', 'Barbecue Pizza S'),
  ('Chili Bee Pizza Small', 'Chilli Bee Pizza S'),
  ('Chili Bee Pizza Medium', 'Chilli Bee Pizza M'),
  ('Chili Bee Pizza Large', 'Chilli Bee Pizza L'),
  ('5 Sauces', 'Sauce Pack 5pc'),
  ('رانش', 'Ranch Sauce'),
  ('كرسبي 4 قطع', 'Crispy Strips 4pc'),
  ('بوكس الدجاج 12 قطعة', 'Broasted 12pc Box'),
  ('بوكس الدجاج 4 قطع حار', 'Broasted 4pc Box'),
  ('موزوريلا ستكس', 'Mozzarella Sticks 4pc'),
  ('كرات التشيلي تشيز', 'Chili Cheese Balls 5pc'),
  ('بيتزا مارغريتا وسط', 'Margherita Pizza M'),
  ('بيتزا تشيليبي وسط', 'Chilli Bee Pizza M'),
  ('باربيكيو بيتزا وسط', 'Barbecue Pizza M'),
  ('كلاسك برجر وجبة', 'Classic Burger Meal'),
  ('كرنشي راب - تشيلي ساندويش', 'Crunchy Wrap Sandwich')
) as v(raw_name, product_name)
join products p on p.name_en = v.product_name
on conflict (raw_name) do nothing;
