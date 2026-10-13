extends GutTest
## AS3: the named pivot empties the GLB models carry (AS1 cab_eye, AS2
## trailer_ref) must be findable by name and must respect the parent chain,
## so the camera rig can read the real anchors instead of the pinned
## placeholder vectors (DEVIATIONS D31, D47).

const TRACTOR_GLB: String = "res://models/tractor.glb"
const TRAILER_GLB: String = "res://models/trailer.glb"
const CAB_EYE_ANCHOR: Vector3 = Vector3(0.0, 2.10, -4.20)
const TRAILER_REF_ANCHOR: Vector3 = Vector3(0.0, 1.60, 6.00)
const ANCHOR_TOL: Vector3 = Vector3(0.001, 0.001, 0.001)

var _holders: Array[Node] = []


func _parent_model(path: String, holder: Node3D) -> Node:
	var model: Node = load(path).instantiate()
	holder.add_child(model)
	return model


func _make_holder(holder_name: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = holder_name
	add_child(holder)
	_holders.append(holder)
	return holder


func after_each() -> void:
	## The instantiated GLBs are freed with their holders; awaiting physics
	## frames matches the teardown pattern in test_cameras.gd.
	for holder in _holders:
		if is_instance_valid(holder):
			holder.queue_free()
	_holders.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_tractor_glb_cab_eye_sits_at_the_pinned_anchor() -> void:
	var holder: Node3D = _make_holder("TractorHolder")
	_parent_model(TRACTOR_GLB, holder)
	var pivot: Node3D = ModelPivots.find_pivot(holder, "cab_eye")
	assert_true(pivot != null, "tractor GLB carries a cab_eye empty")
	assert_eq(pivot.name, "cab_eye", "found node is the cab_eye empty")
	assert_almost_eq(
		pivot.global_position, CAB_EYE_ANCHOR, ANCHOR_TOL, "AS1 anchor (0, 2.10, -4.20)"
	)


func test_trailer_glb_trailer_ref_sits_at_the_pinned_anchor() -> void:
	var holder: Node3D = _make_holder("TrailerHolder")
	_parent_model(TRAILER_GLB, holder)
	var pivot: Node3D = ModelPivots.find_pivot(holder, "trailer_ref")
	assert_true(pivot != null, "trailer GLB carries a trailer_ref empty")
	assert_eq(pivot.name, "trailer_ref", "found node is the trailer_ref empty")
	assert_almost_eq(
		pivot.global_position, TRAILER_REF_ANCHOR, ANCHOR_TOL, "AS2 anchor (0, 1.60, 6.00)"
	)


func test_missing_pivot_reports_the_inf_sentinel() -> void:
	var holder: Node3D = _make_holder("MissingHolder")
	_parent_model(TRACTOR_GLB, holder)
	# Searched against a real tree so the walk demonstrably ran and found
	# nothing, not against an empty node.
	var pos: Vector3 = ModelPivots.pivot_global_position(holder, "does_not_exist")
	assert_eq(pos, Vector3.INF, "not-found sentinel is Vector3.INF")


func test_find_pivot_respects_the_parent_chain() -> void:
	var holder: Node3D = _make_holder("TransformedHolder")
	_parent_model(TRACTOR_GLB, holder)
	var t := Transform3D(Basis.from_euler(Vector3(0.0, 1.0, 0.0)), Vector3(10.0, 0.5, -20.0))
	holder.global_transform = t
	var pos: Vector3 = ModelPivots.pivot_global_position(holder, "cab_eye")
	# The walk must return the anchor in global space: the holder transform
	# applied to the pinned local vector, not the local coordinates.
	assert_almost_eq(
		pos, t * CAB_EYE_ANCHOR, ANCHOR_TOL, "holder transform applied to the local anchor"
	)
	assert_gt(pos.distance_to(CAB_EYE_ANCHOR), 1.0, "global position moved with the holder")
