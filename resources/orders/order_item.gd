class_name OrderItem
extends Resource


@export var product: ProductData
@export var quantity: int = 1

var quantity_fulfilled: int = 0


func is_complete() -> bool:
	return quantity_fulfilled >= quantity
	
