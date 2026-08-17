-- The two lettuce products created by the 20260813184055 Foodics import
-- ("خس ايسبرغ" and "خس برجر") had no English translation available at
-- import time, so name_en was just a copy of the Arabic label. Confirmed
-- with the business owner: "خس برجر" is Lollo Bionda lettuce specifically
-- (distinct from the iceberg variety), not a generic "burger lettuce" --
-- naming it properly here so it's unambiguous in the Menu/Add-ons pages.

UPDATE products SET name_en = 'Lollo Bionda Lettuce', name_ar = 'خس لولو بندا' WHERE id = '23e0dcf1-05de-4d8d-a81a-2826b348182e';
UPDATE products SET name_en = 'Iceberg Lettuce', name_ar = 'خس آيسبرغ' WHERE id = 'ec91b6e1-0287-4330-be1f-cd797ca2e085';
