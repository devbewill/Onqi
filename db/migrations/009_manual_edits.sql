-- Modifiche manuali alle schede: i campi modificati a mano restano bloccati e
-- gli import non li sovrascrivono più.

-- Campi modificati a mano (nomi di colonna) e dettagli extra inseriti a mano
-- (cucina, accessibilità...; in assenza valgono i tag OSM).
ALTER TABLE places
  ADD COLUMN locked_fields text[] NOT NULL DEFAULT '{}',
  ADD COLUMN attributes    jsonb  NOT NULL DEFAULT '{}';

ALTER TABLE places DROP CONSTRAINT places_non_public_reason_check;
ALTER TABLE places ADD CONSTRAINT places_non_public_reason_check
  CHECK (non_public_reason IN ('categoria', 'sede_legale', 'manuale'));

-- Storico delle modifiche manuali.
CREATE TABLE place_edits (
  id         bigserial PRIMARY KEY,
  place_id   uuid NOT NULL REFERENCES places(id) ON DELETE CASCADE,
  field      text NOT NULL,
  old_value  jsonb,
  new_value  jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX place_edits_place_idx ON place_edits (place_id, created_at DESC);

-- Gli UPDATE fuori da una modifica manuale (import, onqi_refresh_public) non
-- toccano i campi bloccati. La modifica manuale si dichiara nella transazione con
--   SET LOCAL onqi.manual_edit = 'on'
CREATE FUNCTION onqi_protect_locked() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(current_setting('onqi.manual_edit', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  IF 'name'        = ANY (OLD.locked_fields) THEN NEW.name        := OLD.name;        END IF;
  IF 'category_id' = ANY (OLD.locked_fields) THEN NEW.category_id := OLD.category_id; END IF;
  IF 'address'     = ANY (OLD.locked_fields) THEN NEW.address     := OLD.address;     END IF;
  IF 'postcode'    = ANY (OLD.locked_fields) THEN NEW.postcode    := OLD.postcode;    END IF;
  IF 'phone'       = ANY (OLD.locked_fields) THEN NEW.phone       := OLD.phone;       END IF;
  IF 'website'     = ANY (OLD.locked_fields) THEN NEW.website     := OLD.website;     END IF;
  IF 'email'       = ANY (OLD.locked_fields) THEN NEW.email       := OLD.email;       END IF;
  IF 'socials'     = ANY (OLD.locked_fields) THEN NEW.socials     := OLD.socials;     END IF;
  IF 'vat_number'  = ANY (OLD.locked_fields) THEN NEW.vat_number  := OLD.vat_number;  END IF;
  IF 'status'      = ANY (OLD.locked_fields) THEN NEW.status      := OLD.status;      END IF;
  IF 'is_public'   = ANY (OLD.locked_fields) THEN
    NEW.is_public := OLD.is_public;
    NEW.non_public_reason := OLD.non_public_reason;
  END IF;
  NEW.locked_fields := OLD.locked_fields;
  NEW.attributes := OLD.attributes;
  RETURN NEW;
END;
$$;

CREATE TRIGGER places_protect_locked
BEFORE UPDATE ON places
FOR EACH ROW EXECUTE FUNCTION onqi_protect_locked();
