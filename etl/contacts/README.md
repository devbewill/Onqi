# Hand-researched contacts applier

`etl/apply-contacts.sh` applies a manually researched CSV of social pages / websites
to existing `places`, marks the touched columns as locked so future imports do not
overwrite them, and reports the outcome.

## Input CSV

Header must be exactly:

```csv
name,address,instagram,facebook,website
```

- `name` – place name (fuzzy, accent/case-insensitive match).
- `address` – street + house number, as stored in `places.address`
  (e.g. `Via Leone Tolstoi, 45`). The script parses the house number with the
  same `onqi_address_parts` helper used elsewhere.
- `instagram` / `facebook` – handles or URLs. They are normalised to
  `https://www.instagram.com/<handle>` and `https://www.facebook.com/<page>`.
- `website` – only written when the row provides one **and** `places.website`
  is currently empty.

Empty cells are ignored.

## Usage

```bash
etl/apply-contacts.sh data/hand_contacts.csv
```

The script runs inside a single transaction with `SET LOCAL onqi.manual_edit = 'on'`,
so the `places_protect_locked` trigger allows the update and the touched columns
(`website`, `socials`) are appended to `places.locked_fields`.

## Output summary

A `NOTICE` at the end reports:

- `updated` – row matched and at least one column was written.
- `already-set` – row matched but every value was already present.
- `ambiguous` – more than one place matched the same house number + name.
- `not-found` – no candidate matched.

Running the same CSV twice is safe: the second run reports the rows as
`already-set` (or `ambiguous` / `not-found` again).
