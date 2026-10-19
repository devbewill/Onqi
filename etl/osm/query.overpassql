[out:json][timeout:180];
(
  nwr["shop"]["name"]({{bbox}});
  nwr["amenity"~"^(bar|pub|cafe|restaurant|fast_food|ice_cream|biergarten|food_court|pharmacy|nightclub|cinema|theatre|arts_centre|marketplace|car_rental|bicycle_rental|internet_cafe|casino|bank|post_office|community_centre|social_centre|social_facility|library|fuel|veterinary|place_of_worship|clinic|dentist|doctors)$"]["name"]({{bbox}});
  nwr["office"]["name"]({{bbox}});
  nwr["healthcare"]["name"]({{bbox}});
  nwr["craft"]["name"]({{bbox}});
  nwr["leisure"~"^(fitness_centre|sports_centre|swimming_pool|dance|escape_game|amusement_arcade)$"]["name"]({{bbox}});
  nwr["tourism"~"^(hotel|guest_house|hostel|museum|gallery)$"]["name"]({{bbox}});
);
out center tags;
