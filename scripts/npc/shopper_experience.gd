class_name ShopperExperience
extends RefCounted


const MIN_RATING: float = 0.0
const MAX_RATING: float = 5.0
const DEFAULT_RATING: float = 2.5

# Experience adjustments
const OUT_OF_STOCK_PENALTY: float = 0.5
const ALL_ITEMS_FOUND_BONUS: float = 0.5
const CHECKOUT_BELL_PENALTY: float = 0.2


var rating: float = DEFAULT_RATING
var events: Array[String] = []
var submitted: bool = false


func _init(starting_rating: float = DEFAULT_RATING) -> void:
	rating = _normalize_rating(starting_rating)


func change_rating(amount: float, reason: String) -> void:
	if submitted:
		return

	var previous_rating: float = rating
	rating = _normalize_rating(rating + amount)

	if is_equal_approx(previous_rating, rating):
		return

	events.append("%s: %+.1f" % [reason, rating - previous_rating])


func increase(amount: float, reason: String) -> void:
	change_rating(absf(amount), reason)


func decrease(amount: float, reason: String) -> void:
	change_rating(-absf(amount), reason)


func _normalize_rating(value: float) -> float:
	return roundf(clampf(value, MIN_RATING, MAX_RATING) * 10.0) / 10.0
