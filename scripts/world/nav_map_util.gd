class_name NavMapUtil
extends RefCounted
## The small navigation questions three controllers used to answer separately.
##
## `PlayerController`, `PointerNavigator` and `CompanionController` each asked the same
## question before asking the navigation map for a route: "does this map hold any geometry
## at all?" It is a cheap question with an awkward shape - a map RID can be invalid (the
## server has not given the world one yet) and a valid map can hold no regions (this room's
## mesh has not been registered) - and the answer decides whether a walk starts, a click is
## refused, or the companion gives up. Three copies meant the rule could be tightened in one
## place and left behind in two (issue #212).
##
## This is deliberately a static utility rather than a base class: none of the three callers
## has anything else in common with the others, and a shared ancestor would be a
## relationship invented to hold four lines of code.
##
## `LocationNavigation.get_map_region_count()` asks the same question of its own map and
## keeps its own version, because it needs the number, not the yes/no, and it is the one
## node that can answer "did *this* room's mesh reach the map?" rather than "any mesh did".


## True when `map` is a valid exploration map holding at least one region.
##
## False is not an error: before the first bake, and for the frame or two after a location
## swap while the server has not updated, the honest answer is "not yet".
static func has_geometry(map: RID) -> bool:
	if not map.is_valid():
		return false
	return NavigationServer3D.map_get_regions(map).size() > 0
