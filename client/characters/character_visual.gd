class_name CharacterVisual
extends Resource

# Presentation belongs to the client; selection and gameplay use the catalog ID.
enum PlaceholderKind { CIRCLE, SQUARE, TRIANGLE, DIAMOND }
@export var character_id: int
@export var placeholder_kind := PlaceholderKind.CIRCLE
