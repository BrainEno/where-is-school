class_name GameUI
extends CanvasLayer
## Typed access to the presentation nodes that travel with the session.
##
## Keeping the UI in one persistent CanvasLayer means dialogue, backlog, fades and
## the imagination frame survive location changes without re-wiring.

@onready var hud: GameHud = %HUD
@onready var fade: FadeLayer = %FadeLayer
@onready var overlay: ImaginationOverlay = %ImaginationOverlay
@onready var end_card: EndCard = %EndCard
@onready var dialogue_panel: DialoguePanel = %DialoguePanel
@onready var backlog: BacklogPanel = %BacklogPanel
