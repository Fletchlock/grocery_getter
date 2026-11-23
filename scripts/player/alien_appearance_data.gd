
extends Resource
class_name AlienAppearanceData

# Body
@export_range(0.0, 1.0, 0.01) var body_weight: float = 0.5
@export var skin_color: Color = Color("#40bf59")
@export var pattern_color: Color = Color("#0d401a")
@export var pattern_index: int = 0

# Face
@export var pupil_color: Color = Color("#240c38")
@export var lips_use_skin_color: bool = true
@export var lip_color: Color = Color("#c95b86")
@export var eyelashes_enabled: bool = false

# Equipment styles
@export var head_style: int = 0
@export var top_style: int = 0
@export var bottom_style: int = 0
@export var feet_style: int = 0

# Equipment colors
@export var top_color: int = 7
@export var bottom_color: int = 3
@export var feet_color: int = 0
@export var sole_color: int = 7
