extends Node

const ID = "qtpi.Waterfall" 
onready var Lure = get_node("/root/SulayreLure")

func _ready():#
	
	Lure.add_map(ID,"waterfall", "mod://Scenes/Map/waterfall_map.tscn", "Waterfall")
