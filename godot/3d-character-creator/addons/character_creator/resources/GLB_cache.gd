# Global cache for loaded GLB models with LRU eviction
# Prevents re-loading models and manages memory with a max limit
# Usage: GLBCache.get_cached(cc_id) / GLBCache.cache(cc_id, scene)
class_name GLBCache

static var MAX_LOADED := 64 # TODO: this should be an export var on 3d_character_creator.gd for more dev control

# Maps cc_id -> {scene: PackedScene, timestamp: int}
# timestamp tracks last access time for LRU eviction
static var _cache: Dictionary = {}

static func get_cached(cc_id: String) -> PackedScene:
	if _cache.has(cc_id):
		_cache[cc_id].timestamp = Time.get_ticks_msec()
		return _cache[cc_id].scene
	return null

static func cache(cc_id: String, scene: PackedScene) -> void:
	# Evict oldest if at limit
	if _cache.size() >= MAX_LOADED:
		var oldest_id := ""
		var oldest_time := INF
		for id: String in _cache:
			if _cache[id].timestamp < oldest_time:
				oldest_time = _cache[id].timestamp
				oldest_id = id
		_cache.erase(oldest_id)

	_cache[cc_id] = {
		"scene": scene,
		"timestamp": Time.get_ticks_msec()
	}

static func clear() -> void:
	_cache.clear()

static func evict_except(used_ids: Dictionary) -> void:
	var to_evict: Array[String] = []
	for cc_id: String in _cache.keys():
		if not used_ids.has(cc_id):
			to_evict.append(cc_id)

	for cc_id in to_evict:
		_cache.erase(cc_id)
