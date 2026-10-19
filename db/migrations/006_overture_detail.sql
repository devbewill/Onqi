-- Categorie Overture dettagliate (taxonomy.primary): quando presenti vincono
-- sulla basic_category, che raggruppa ad esempio pasticcerie e gelaterie in
-- "casual_eatery".
INSERT INTO category_mappings (source, source_category, category_id)
SELECT 'overture_detail', v.src, c.id
FROM (VALUES
  ('bakery', 'panetteria_pasticceria'), ('custom_cakes_shop', 'panetteria_pasticceria'),
  ('cupcake_shop', 'panetteria_pasticceria'), ('dessert_shop', 'panetteria_pasticceria'),
  ('chocolatier', 'panetteria_pasticceria'), ('patisserie_cake_shop', 'panetteria_pasticceria'),
  ('pastry_shop', 'panetteria_pasticceria'), ('candy_store', 'panetteria_pasticceria'),
  ('ice_cream_shop', 'gelateria'), ('gelato_shop', 'gelateria'), ('frozen_yoghurt_shop', 'gelateria'),
  ('tobacco_shop', 'tabacchi_edicola'), ('smoke_and_vape_store', 'tabacchi_edicola'),
  ('vape_store', 'tabacchi_edicola'), ('newspaper_and_magazines_store', 'tabacchi_edicola'),
  ('newsstand', 'tabacchi_edicola'),
  ('liquor_store', 'enoteca'), ('beer_wine_spirits_store', 'enoteca'), ('wine_shop', 'enoteca'),
  ('shoe_repair', 'sartoria_riparazioni'), ('tailor', 'sartoria_riparazioni'),
  ('sewing_and_alterations', 'sartoria_riparazioni'), ('watch_repair_service', 'sartoria_riparazioni'),
  ('jewelry_store', 'gioielleria'), ('watch_store', 'gioielleria'),
  ('eyewear_and_optician', 'ottica'), ('optometrist', 'ottica'), ('hearing_aids', 'ottica'),
  ('bar', 'bar'), ('wine_bar', 'bar'), ('cocktail_bar', 'bar'), ('pub', 'bar'),
  ('coffee_shop', 'caffetteria'), ('cafe', 'caffetteria')
) AS v(src, slug)
JOIN categories c ON c.slug = v.slug;
