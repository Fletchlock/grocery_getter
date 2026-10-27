extends Node


signal reputation_changed(new_rating: float)


const DEFAULT_REPUTATION: float = 2.5
const MIN_REPUTATION: float = 0.0
const MAX_REPUTATION: float = 5.0
const EXPERIENCE_WEIGHT: float = 0.05


var store_reputation: float = DEFAULT_REPUTATION
var total_reviews: int = 0


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

	reputation_changed.emit(store_reputation)
	_sync_reputation.rpc(store_reputation, total_reviews)

# debug ==========================
func debug_test_reputation() -> void:
	if not multiplayer.is_server():
		return

	var test_experience: ShopperExperience = ShopperExperience.new()

	test_experience.increase(0.5, "Found all items")
	test_experience.increase(0.5, "Friendly service")

	submit_experience(test_experience)
