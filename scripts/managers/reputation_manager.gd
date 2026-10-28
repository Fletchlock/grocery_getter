extends Node


signal reputation_changed(new_rating: float)


const DEFAULT_REPUTATION: float = 2.5
const MIN_REPUTATION: float = 0.0
const MAX_REPUTATION: float = 5.0
const EXPERIENCE_WEIGHT: float = 0.05
const MIN_TRAFFIC_MULTIPLIER: float = 0.5
const MAX_TRAFFIC_MULTIPLIER: float = 1.5

var store_reputation: float = DEFAULT_REPUTATION
var total_reviews: int = 0
var total_order_events: int = 0

func get_traffic_multiplier() -> float:
	return lerpf(
		MIN_TRAFFIC_MULTIPLIER,
		MAX_TRAFFIC_MULTIPLIER,
		clampf(store_reputation / MAX_REPUTATION, 0.0, 1.0)
	)
	

func get_display_rating() -> float:
	return roundf(store_reputation * 10.0) / 10.0


func get_starting_experience() -> float:
	# Word-of-mouth influence will be added later.
	return ShopperExperience.DEFAULT_RATING


func submit_experience(experience: ShopperExperience) -> void:
	if not multiplayer.is_server():
		return

	if experience == null:
		return

	if experience.submitted:
		return

	experience.submitted = true

	var previous_rating: float = store_reputation

	store_reputation = clampf(
		store_reputation + (experience.rating - store_reputation) * EXPERIENCE_WEIGHT,
		MIN_REPUTATION,
		MAX_REPUTATION
	)

	total_reviews += 1

	print(
		"REPUTATION: Shopper rating %.1f | Store %.2f -> %.2f | Reviews %d"
		% [experience.rating, previous_rating, store_reputation, total_reviews]
	)

	reputation_changed.emit(store_reputation)
	_sync_reputation.rpc(store_reputation, total_reviews)


func submit_order_reputation(change: float, reason: String) -> void:
	if not multiplayer.is_server():
		return

	var previous_rating: float = store_reputation

	store_reputation = clampf(
		store_reputation + change * EXPERIENCE_WEIGHT,
		MIN_REPUTATION,
		MAX_REPUTATION
	)

	total_order_events += 1

	print(
		"ORDER REPUTATION: %s | Change %+.1f | Store %.3f -> %.3f | Events %d"
		% [
			reason,
			change,
			previous_rating,
			store_reputation,
			total_order_events
		]
	)

	reputation_changed.emit(store_reputation)
	_sync_reputation.rpc(store_reputation, total_reviews)


@rpc("authority", "call_remote", "reliable")
func _sync_reputation(rating: float, reviews: int) -> void:
	store_reputation = clampf(rating, MIN_REPUTATION, MAX_REPUTATION)
	total_reviews = reviews

	reputation_changed.emit(store_reputation)


func reset_reputation() -> void:
	if not multiplayer.is_server():
		return

	store_reputation = DEFAULT_REPUTATION
	total_reviews = 0
	total_order_events = 0
	
	reputation_changed.emit(store_reputation)
	_sync_reputation.rpc(store_reputation, total_reviews)


func get_save_data() -> Dictionary:
	return {
		"store_reputation": store_reputation,
		"total_reviews": total_reviews,
		"total_order_events": total_order_events
	}


func load_save_data(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	store_reputation = clampf(
		float(data.get("store_reputation", DEFAULT_REPUTATION)),
		MIN_REPUTATION,
		MAX_REPUTATION
	)

	total_reviews = maxi(
		0,
		int(data.get("total_reviews", 0))
	)
	
	total_order_events = maxi(
		0,
		int(data.get("total_order_events", 0))
	)
	
	reputation_changed.emit(store_reputation)
	_sync_reputation.rpc(store_reputation, total_reviews)
