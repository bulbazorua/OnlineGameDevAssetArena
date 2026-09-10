class_name CharacterExports
extends RefCounted

const CharacterAnimationSet = preload("res://characters/character_animation_set.gd")

# Import-time value. No health, playback cursor, live world or AI memory here.
var module_key := ""
var contract_id := ""
var contract_version := ""
var export_api_version := ""
var gameplay_definition: Dictionary = {}
var ai: Dictionary = {}
var art: CharacterAnimationSet
