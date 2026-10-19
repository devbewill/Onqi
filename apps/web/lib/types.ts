export type Promo = { title: string; kind: string; until: string | null };

export type NearbyPlace = {
  id: string;
  name: string;
  category: string;
  categoryName: string;
  macro: string;
  macroName: string;
  distance: number;
  lat: number;
  lon: number;
  address: string | null;
  phone: string | null;
  website: string | null;
  email: string | null;
  socials: string[] | null;
  vatNumber: string | null;
  openNow: boolean | null;
  hoursToday: string | null;
  sources: string[];
  promos: Promo[];
};
