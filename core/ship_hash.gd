class_name ShipHash
extends RefCounted

## Hashes derived from ship data — API_CONTRACT section 2.
##
## Two jobs, both determinism gates:
## [br]- [method shape_seed] is what makes identical params give an identical shape forever.
## [br]- [method doc_hash] is save integrity: the same document always prints the same hex.
##
## Both are thin shells over [ShipCanonical]. All of the difficulty lives there; this file
## only decides what goes into the byte string and in what order. Changing either payout
## layout is a ruleset bump.

## Field separator for the seed payload. 0x1F (ASCII unit separator) is chosen because
## [method ShipCanonical.canonical_json] escapes every code point below 0x20 as an escape sequence,
## so the separator can never appear raw inside the serialized params and no pair of
## (family, manufacturer, params) can be re-parsed into a different pair.
const SEP: String = "\u001f"


## Derives the micro-detail seed for one shape — SPEC section 4.
##
## There is no nonce and no rollable seed: the params fully determine the shape, so this
## is a pure function of what the player set plus which generator ruleset is in force.
## [param ruleset] is normally [constant ShipDoc.RULESET_VERSION]; passing the document's
## own recorded ruleset is what lets an old ship keep resolving to its old geometry.
##
## The returned int is a signed reading of a 64-bit hash and is frequently negative.
## That is fine — everything downstream feeds it back into [ShipCanonical].
static func shape_seed(
	family_id: String, manufacturer_id: String, params: Dictionary, ruleset: String
) -> int:
	var payload: String = (
		family_id
		+ SEP
		+ manufacturer_id
		+ SEP
		+ ShipCanonical.canonical_json(params)
		+ SEP
		+ ruleset
	)
	return ShipCanonical.fnv1a_64(payload)


## Hex digest of the whole document, for save integrity and for the determinism tests.
##
## Hashes exactly what [method ShipDoc.to_dict] would write to disk — including the
## id counters in `settings.next_id`, because two documents that differ only in which
## ids have been handed out are different saves even when they look identical on screen.
## A null document hashes as the empty payload rather than crashing.
static func doc_hash(doc: ShipDoc) -> String:
	if doc == null:
		return ShipCanonical.hex64(ShipCanonical.fnv1a_64(""))
	return ShipCanonical.hex64(ShipCanonical.fnv1a_64(ShipCanonical.canonical_json(doc.to_dict())))
