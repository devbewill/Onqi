-- Si conservano tutte le attività, ma solo gli esercizi aperti al pubblico
-- (negozi, locali, associazioni... dove una persona entra per fare qualcosa)
-- vengono mostrati. Sedi aziendali, studi professionali, enti, luoghi restano
-- nel db con is_public = false.

ALTER TABLE categories ADD COLUMN is_public boolean NOT NULL DEFAULT true;

-- ---------------------------------------------------------------------------
-- Nuove categorie pubbliche
-- ---------------------------------------------------------------------------
INSERT INTO categories (slug, name_it) VALUES ('community', 'Associazioni e servizi');

INSERT INTO categories (slug, name_it, parent_id)
SELECT v.slug, v.name_it, p.id
FROM (VALUES
  ('associazioni',        'Associazioni, onlus e circoli',  'community'),
  ('sindacati_patronati', 'Sindacati, CAF e patronati',     'community'),
  ('banca_posta',         'Banche e uffici postali',        'services'),
  ('distributore',        'Distributori di carburante',     'services'),
  ('biblioteca',          'Biblioteche',                    'culture'),
  ('corsi',               'Scuole private e corsi',         'culture'),
  ('circoli_sportivi',    'Circoli e centri sportivi',      'sport'),
  ('veterinario',         'Veterinari',                     'services')
) AS v(slug, name_it, parent)
JOIN categories p ON p.slug = v.parent;

-- ---------------------------------------------------------------------------
-- Categorie non aperte al pubblico
-- ---------------------------------------------------------------------------
INSERT INTO categories (slug, name_it, is_public) VALUES ('non_public', 'Non aperti al pubblico', false);

INSERT INTO categories (slug, name_it, parent_id, is_public)
SELECT v.slug, v.name_it, p.id, false
FROM (VALUES
  ('ufficio_azienda',         'Uffici e sedi aziendali'),
  ('professionista',          'Studi professionali e servizi alle imprese'),
  ('sanita',                  'Studi medici e strutture sanitarie'),
  ('istruzione',              'Scuole e università'),
  ('pubblica_amministrazione','Enti pubblici'),
  ('culto',                   'Luoghi di culto'),
  ('luogo',                   'Parchi, piazze e luoghi'),
  ('trasporti',               'Trasporti e parcheggi'),
  ('residenziale',            'Residenze e alloggi privati'),
  ('altro',                   'Altro')
) AS v(slug, name_it)
JOIN categories p ON p.slug = 'non_public';

-- ---------------------------------------------------------------------------
-- Overture: tutte le basic_category finora escluse
-- ---------------------------------------------------------------------------
INSERT INTO category_mappings (source, source_category, category_id)
SELECT 'overture', v.src, c.id
FROM (VALUES
  -- pubbliche
  ('social_or_community_service', 'associazioni'), ('civic_organization', 'associazioni'),
  ('youth_organization', 'associazioni'), ('social_club', 'associazioni'),
  ('community_center', 'associazioni'), ('family_service', 'associazioni'),
  ('religious_organization', 'associazioni'), ('food_bank', 'associazioni'),
  ('labor_union', 'sindacati_patronati'),
  ('bank_or_credit_union', 'banca_posta'),
  ('gas_station', 'distributore'), ('fueling_station', 'distributore'),
  ('library', 'biblioteca'),
  ('specialty_school', 'corsi'), ('tutoring_service', 'corsi'), ('educational_service', 'corsi'),
  ('sport_or_recreation_club', 'circoli_sportivi'), ('sports_complex', 'circoli_sportivi'),
  ('sports_and_recreation', 'circoli_sportivi'),
  ('festival_venue', 'spazi_eventi'), ('ticket_office_or_booth', 'spazi_eventi'),
  ('amusement_park', 'sala_giochi'), ('amusement_attraction', 'sala_giochi'),
  ('zoo', 'museo'), ('aquarium', 'museo'), ('planetarium', 'museo'), ('science_attraction', 'museo'),
  ('auto_dealer', 'negozi_specializzati'), ('vehicle_dealer', 'negozi_specializzati'),
  ('adult_entertainment_venue', 'discoteca'),
  -- non pubbliche
  ('corporate_or_business_office', 'ufficio_azienda'), ('manufacturer', 'ufficio_azienda'),
  ('wholesaler', 'ufficio_azienda'), ('supplier_or_distributor', 'ufficio_azienda'),
  ('b2b_service', 'ufficio_azienda'), ('b2b_office_and_professional_service', 'ufficio_azienda'),
  ('b2b_transportation_and_storage_service', 'ufficio_azienda'),
  ('b2b_industrial_and_machine_service', 'ufficio_azienda'),
  ('b2b_energy_and_utility_service', 'ufficio_azienda'),
  ('b2b_science_and_technology_service', 'ufficio_azienda'),
  ('industrial_facility_or_service', 'ufficio_azienda'), ('storage_facility', 'ufficio_azienda'),
  ('radio_station', 'ufficio_azienda'), ('research_institute', 'ufficio_azienda'),
  ('agricultural_service', 'ufficio_azienda'), ('environmental_or_ecological_service', 'ufficio_azienda'),
  ('security_service', 'ufficio_azienda'), ('farm', 'ufficio_azienda'),
  ('public_utility', 'ufficio_azienda'), ('electric_utility_provider', 'ufficio_azienda'),
  ('natural_gas_utility_provider', 'ufficio_azienda'), ('water_utility_provider', 'ufficio_azienda'),
  ('services_and_business', 'ufficio_azienda'),
  ('professional_service', 'professionista'), ('attorney_or_law_firm', 'professionista'),
  ('legal_service', 'professionista'), ('financial_service', 'professionista'),
  ('real_estate_service', 'professionista'), ('design_service', 'professionista'),
  ('media_service', 'professionista'), ('home_service', 'professionista'),
  ('technical_service', 'professionista'), ('building_or_construction_service', 'professionista'),
  ('event_or_party_service', 'professionista'), ('housing_or_property_service', 'professionista'),
  ('psychic_advising', 'professionista'), ('astrological_advising', 'professionista'),
  ('political_organization', 'professionista'),
  ('dental_clinic', 'sanita'), ('specialized_health_care', 'sanita'),
  ('diagnostics_imaging_or_lab_service', 'sanita'), ('behavioral_or_mental_health_clinic', 'sanita'),
  ('outpatient_care_facility', 'sanita'), ('hospital', 'sanita'), ('surgery', 'sanita'),
  ('physical_medicine_and_rehabilitation', 'sanita'), ('complementary_and_alternative_medicine', 'sanita'),
  ('health_care', 'sanita'), ('medical_service', 'sanita'), ('vision_or_eye_care_clinic', 'sanita'),
  ('reproductive_perinatal_and_womens_care', 'sanita'), ('pediatric_clinic', 'sanita'),
  ('primary_care_or_general_clinic', 'sanita'), ('senior_living_facility', 'sanita'),
  ('emergency_or_urgent_care_facility', 'sanita'), ('emergency_department', 'sanita'),
  ('urgent_care_clinic', 'sanita'), ('specialized_medical_facility', 'sanita'),
  ('specialty_hospital', 'sanita'),
  ('education', 'istruzione'), ('place_of_learning', 'istruzione'), ('college_university', 'istruzione'),
  ('preschool', 'istruzione'), ('elementary_school', 'istruzione'), ('middle_school', 'istruzione'),
  ('high_school', 'istruzione'), ('campus_building', 'istruzione'), ('educational_facility', 'istruzione'),
  ('government_office', 'pubblica_amministrazione'), ('community_and_government', 'pubblica_amministrazione'),
  ('government_department', 'pubblica_amministrazione'), ('civic_center', 'pubblica_amministrazione'),
  ('courthouse', 'pubblica_amministrazione'), ('police_station', 'pubblica_amministrazione'),
  ('fire_station', 'pubblica_amministrazione'), ('embassy', 'pubblica_amministrazione'),
  ('jail_or_prison', 'pubblica_amministrazione'),
  ('christian_place_of_worship', 'culto'), ('muslim_place_of_worship', 'culto'),
  ('buddhist_place_of_worship', 'culto'), ('jewish_place_of_worship', 'culto'),
  ('hindu_place_of_worship', 'culto'), ('place_of_worship', 'culto'), ('religious_landmark', 'culto'),
  ('park', 'luogo'), ('public_plaza', 'luogo'), ('historic_site', 'luogo'), ('monument', 'luogo'),
  ('sculpture_statue', 'luogo'), ('public_fountain', 'luogo'), ('street_art', 'luogo'),
  ('dog_park', 'luogo'), ('playground', 'luogo'), ('garden', 'luogo'), ('beach', 'luogo'),
  ('lake', 'luogo'), ('river', 'luogo'), ('canal', 'luogo'), ('bridge', 'luogo'),
  ('mountain', 'luogo'), ('nature_reserve', 'luogo'), ('land_feature', 'luogo'),
  ('geographic_entities', 'luogo'), ('castle', 'luogo'), ('cemetery', 'luogo'),
  ('recreational_trail_or_path', 'luogo'), ('rural_attraction', 'luogo'), ('fairgrounds', 'luogo'),
  ('sport_court', 'luogo'), ('sport_field', 'luogo'), ('stadium_arena', 'luogo'),
  ('skating_rink', 'luogo'), ('skate_park', 'luogo'), ('golf_course', 'luogo'),
  ('marina', 'luogo'), ('campground', 'luogo'), ('public_restroom', 'luogo'), ('military_site', 'luogo'),
  ('atm', 'luogo'), ('ev_charging_station', 'luogo'),
  ('sport_league', 'altro'), ('sport_team', 'altro'),
  ('parking', 'trasporti'), ('parking_garage', 'trasporti'), ('parking_lot', 'trasporti'),
  ('train_station', 'trasporti'), ('public_transit_facility_or_service', 'trasporti'),
  ('travel_and_transportation', 'trasporti'), ('taxi_or_ride_share_service', 'trasporti'),
  ('air_transport_facility_or_service', 'trasporti'), ('airport', 'trasporti'),
  ('rail_facility_or_service', 'trasporti'), ('ferry_service', 'trasporti'),
  ('private_lodging', 'residenziale'), ('condominium', 'residenziale'), ('apartment', 'residenziale')
) AS v(src, slug)
JOIN categories c ON c.slug = v.slug;

-- ---------------------------------------------------------------------------
-- OSM: nuovi tag e fallback per chiave ('office=*'): nulla viene scartato
-- ---------------------------------------------------------------------------
INSERT INTO category_mappings (source, source_category, category_id)
SELECT 'osm', v.src, c.id
FROM (VALUES
  ('amenity=bank', 'banca_posta'), ('amenity=post_office', 'banca_posta'),
  ('amenity=community_centre', 'associazioni'), ('amenity=social_centre', 'associazioni'),
  ('amenity=social_facility', 'associazioni'),
  ('amenity=library', 'biblioteca'), ('amenity=fuel', 'distributore'),
  ('amenity=veterinary', 'veterinario'),
  ('amenity=place_of_worship', 'culto'),
  ('amenity=clinic', 'sanita'), ('amenity=dentist', 'sanita'), ('amenity=doctors', 'sanita'),
  ('office=association', 'associazioni'), ('office=ngo', 'associazioni'),
  ('office=charity', 'associazioni'), ('office=foundation', 'associazioni'),
  ('office=union', 'sindacati_patronati'), ('office=trade_union', 'sindacati_patronati'),
  ('office=lawyer', 'professionista'), ('office=accountant', 'professionista'),
  ('office=notary', 'professionista'), ('office=architect', 'professionista'),
  ('office=estate_agent', 'professionista'), ('office=tax_advisor', 'professionista'),
  ('office=insurance', 'professionista'), ('office=financial', 'professionista'),
  ('office=government', 'pubblica_amministrazione'),
  ('shop=estate_agent', 'professionista'), ('shop=wholesale', 'ufficio_azienda'),
  ('shop=trade', 'ufficio_azienda'), ('shop=vacant', 'altro'),
  ('craft=photographer', 'professionista'), ('craft=caterer', 'professionista'),
  -- fallback per chiave
  ('shop=*', 'negozi_specializzati'), ('office=*', 'ufficio_azienda'), ('craft=*', 'professionista'),
  ('healthcare=*', 'sanita'), ('amenity=*', 'altro'), ('leisure=*', 'luogo'), ('tourism=*', 'altro')
) AS v(src, slug)
JOIN categories c ON c.slug = v.slug;

-- ---------------------------------------------------------------------------
-- Flag sul place
-- ---------------------------------------------------------------------------
ALTER TABLE places
  ADD COLUMN is_public boolean NOT NULL DEFAULT true,
  ADD COLUMN non_public_reason text CHECK (non_public_reason IN ('categoria', 'sede_legale'));
CREATE INDEX places_public_geom_idx ON places USING gist (geom) WHERE is_public;

-- Ricalcola il flag per tutti i place. Non pubblico se:
--  - la categoria non è aperta al pubblico, oppure
--  - viene solo dal registro imprese (BrightQuery), nessuna conferma OSM, e il
--    nome è una ragione sociale: probabile sede legale, non un punto vendita.
-- Un place reclamato da un esercente è sempre pubblico.
CREATE FUNCTION onqi_refresh_public() RETURNS void
LANGUAGE sql AS $$
  WITH v AS (
    SELECT p.id,
           CASE
             WHEN p.claimed_by IS NOT NULL THEN NULL
             WHEN NOT c.is_public THEN 'categoria'
             WHEN p.name ~* '\m(s\.?r\.?l|s\.?n\.?c|s\.?a\.?s|s\.?p\.?a|s\.?c\.?a\.?r\.?l|s\.?c\.?r\.?l)\M'
                  AND NOT EXISTS (SELECT 1 FROM place_sources s WHERE s.place_id = p.id AND s.source <> 'overture')
                  AND NOT EXISTS (SELECT 1 FROM place_sources s, jsonb_array_elements(s.raw->'sources') x
                                   WHERE s.place_id = p.id AND x->>'dataset' NOT IN ('BrightQuery', 'Overture'))
               THEN 'sede_legale'
           END AS reason
    FROM places p JOIN categories c ON c.id = p.category_id
  )
  UPDATE places p
  SET is_public = v.reason IS NULL, non_public_reason = v.reason
  FROM v
  WHERE p.id = v.id AND p.non_public_reason IS DISTINCT FROM v.reason
$$;
