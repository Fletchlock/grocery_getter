@tool
extends EditorScript

# 1. Update these to match your project folders!
const TARGET_FOLDER = "res://resources/products/"
const DATABASE_JSON_PATH = "res://data/json/produce_database.json"

const DIRECTIONS = ["U", "D", "L", "R"]

func _run() -> void:
	print("\n--- Starting All-In-One Produce Sync ---")
	
	# =========================================================================
	# STEP 1: Load Existing JSON Database (Ensures code constancy)
	# =========================================================================
	var database: Dictionary = {}
	if FileAccess.file_exists(DATABASE_JSON_PATH):
		var existing_text = FileAccess.get_file_as_string(DATABASE_JSON_PATH)
		var parsed = JSON.parse_string(existing_text)
		if parsed and typeof(parsed) == TYPE_DICTIONARY:
			database = parsed
			print("Loaded ", database.size(), " existing codes from database.")

	# Map out used codes so our generator never creates a duplicate
	var used_codes: Dictionary = {}
	for product_name in database:
		used_codes[database[product_name]] = true

	# =========================================================================
	# STEP 2: Scan Directory & Generate Missing Codes
	# =========================================================================
	if not DirAccess.dir_exists_absolute(TARGET_FOLDER):
		printerr("Directory does not exist: ", TARGET_FOLDER)
		return
		
	var dir = DirAccess.open(TARGET_FOLDER)
	if not dir: return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	var json_updated: bool = false
	var resources_updated_count: int = 0
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var file_path = TARGET_FOLDER + file_name
			var product_res = load(file_path) as ProductData
			
			# FILTER: Only look at products explicitly set as "produce"
			if product_res and product_res.product_category == "produce":
				var lookup_key = product_res.display_name if product_res.display_name != "" else file_name.get_basename()
				
				# Generate a new unique code if it doesn't exist in the JSON registry yet
				if not database.has(lookup_key):
					var code: String = ""
					var valid_code_found: bool = false
					
					while not valid_code_found:
						code = ""
						for i in range(4):
							code += DIRECTIONS[randi() % DIRECTIONS.size()]
						
						# Constraint: Max 3 repeats (Excludes UUUU, DDDD, LLLL, RRRR)
						if code != "UUUU" and code != "DDDD" and code != "LLLL" and code != "RRRR":
							# Constraint: Absolutely unique across the entire sheet
							if not used_codes.has(code):
								valid_code_found = true
								used_codes[code] = true
								
					database[lookup_key] = code
					json_updated = true
					print("✨ Generated NEW code for '", lookup_key, "': ", code)
				
				# =========================================================================
				# STEP 3: Sync & Inject back into the .tres file properties
				# =========================================================================
				var target_code = database[lookup_key]
				if product_res.product_code != target_code:
					product_res.product_code = target_code
					ResourceSaver.save(product_res, file_path)
					print("💾 Saved code '", target_code, "' into file: ", file_name)
					resources_updated_count += 1
					
		file_name = dir.get_next()

	# =========================================================================
	# STEP 4: Write back to JSON file if new codes were made
	# =========================================================================
	if json_updated:
		var file = FileAccess.open(DATABASE_JSON_PATH, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(database, "\t"))
			file.close()
			print("✅ JSON Database updated on disk.")
			
	print("--- Sync Complete! Files modified: ", resources_updated_count, " ---\n")
