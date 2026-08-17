-- Foodics products include internal POS utility entries alongside real
-- menu items (this one is a "general kitchen note" line, category
-- 'Notes', priced at 0.001 -- not a real sellable item). Removes the
-- one that came through the 20260813184055 import.
DELETE FROM products WHERE id = '7563e8cb-a425-4a6b-8843-8dd9214f2c36';
