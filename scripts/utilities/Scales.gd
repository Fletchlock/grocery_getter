class_name Scales

const LYDIAN := [
	1.0,       # tonic
	9.0 / 8.0, # major second
	5.0 / 4.0, # major third
	45.0 / 32.0, # augmented fourth
	3.0 / 2.0, # perfect fifth
	5.0 / 3.0, # major sixth
	15.0 / 8.0 # major seventh
]
const IONIAN := [ #Major Scale
	1.0,       # tonic
	9.0 / 8.0, # major second
	5.0 / 4.0, # major third
	4.0 / 3.0, # perfect fourth
	3.0 / 2.0, # perfect fifth
	5.0 / 3.0, # major sixth
	15.0 / 8.0 # major seventh
]
const MIXOLYDIAN := [
	1.0,       # tonic
	9.0 / 8.0, # major second
	5.0 / 4.0, # major third
	4.0 / 3.0, # perfect fourth
	3.0 / 2.0, # perfect fifth
	5.0 / 3.0, # major sixth
	9.0 / 5.0 # minor seventh
]
const DORIAN := [
	1.0,       # tonic
	9.0 / 8.0, # major second
	6.0 / 5.0, # minor third
	4.0 / 3.0, # perfect fourth
	3.0 / 2.0, # perfect fifth
	5.0 / 3.0, # major sixth
	9.0 / 5.0 # minor seventh
]
const AEOLIAN := [ #Natural Minor Scale
	1.0,       # tonic
	9.0 / 8.0, # major second
	6.0 / 5.0, # minor third
	4.0 / 3.0, # perfect fourth
	3.0 / 2.0, # perfect fifth
	8.0 / 5.0, # minor sixth
	9.0 / 5.0 # minor seventh
]
const PHRYGIAN := [
	1.0,       # tonic
	16.0 / 15.0, # minor second
	6.0 / 5.0, # minor third
	4.0 / 3.0, # perfect fourth
	3.0 / 2.0, # perfect fifth
	8.0 / 5.0, # minor sixth
	9.0 / 5.0 # minor seventh
]
const LOCRIAN := [
	1.0,       # tonic
	16.0 / 15.0, # minor second
	6.0 / 5.0, # minor third
	4.0 / 3.0, # perfect fourth
	45.0 / 32.0, # tritone
	8.0 / 5.0, # minor sixth
	9.0 / 5.0 # minor seventh
]

const SCALE_OPTIONS := [
	{"id": 0, "name": "Lydian", "ratios": LYDIAN},
	{"id": 1, "name": "Ionian", "ratios": IONIAN},
	{"id": 2, "name": "Mixolydian", "ratios": MIXOLYDIAN},
	{"id": 3, "name": "Dorian", "ratios": DORIAN},
	{"id": 4, "name": "Aeolian", "ratios": AEOLIAN},
	{"id": 5, "name": "Phrygian", "ratios": PHRYGIAN},
	{"id": 6, "name": "Locrian", "ratios": LOCRIAN},
]

static var selected_scale_id := 1
static var selected_scale = IONIAN
