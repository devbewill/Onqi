-- Caricamento del feed GTFS (già decompresso in data/gtfs/): fermate, linee
-- e associazione fermata-linea. L'associazione viene dai trip: ogni linea che
-- ferma lì conta, indipendentemente dalla giornata di servizio.
DELETE FROM pg.transit_stop_routes;
DELETE FROM pg.transit_routes;
DELETE FROM pg.transit_stops;

INSERT INTO pg.transit_stops (stop_id, stop_code, stop_name, stop_lat, stop_lon,
                              location_type, parent_station)
SELECT stop_id, nullif(stop_code, ''), nullif(stop_name, ''), CAST(stop_lat AS double precision),
       CAST(stop_lon AS double precision), CAST(nullif(location_type, '') AS smallint),
       nullif(parent_station, '')
FROM read_csv(getvariable('dir') || '/stops.txt', all_varchar = true)
WHERE stop_lat <> '' AND stop_lon <> '' AND stop_name <> '';

INSERT INTO pg.transit_routes (route_id, route_short_name, route_long_name, route_type)
SELECT route_id, route_short_name, route_long_name, CAST(route_type AS smallint)
FROM read_csv(getvariable('dir') || '/routes.txt', all_varchar = true);

INSERT INTO pg.transit_stop_routes (stop_id, route_id)
SELECT DISTINCT st.stop_id, t.route_id
FROM read_csv(getvariable('dir') || '/stop_times.txt', all_varchar = true) st
JOIN read_csv(getvariable('dir') || '/trips.txt', all_varchar = true) t
     ON t.trip_id = st.trip_id
JOIN pg.transit_stops s ON s.stop_id = st.stop_id;
