extends RefCounted
## The character's radio library (profile `music`): favourite tracks and the
## player's own playlists. It belongs to the profile so every device playing
## the character shares it; what a device is playing stays on that device
## (see radio.gd). The backend changes it through GameSession's music
## methods, one small operation at a time, so two devices editing at once do
## not overwrite each other.

const MAX_PLAYLISTS := 50
const MAX_TRACKS := 200
const MAX_NAME := 20

static func empty() -> Dictionary:
	return {"favorites":[],"playlists":[]}

static func valid_track(track: Variant) -> bool:
	return track is String and track.length() <= 32 and RegEx.create_from_string("^sabgm_[a-z0-9]+$").search(track) != null

static func clean_name(name: Variant) -> String:
	return str(name).strip_edges().left(MAX_NAME) if name is String else ""

## A stored library with anything malformed dropped (older saves have none).
static func sanitize(value: Variant) -> Dictionary:
	var result := empty()
	if not value is Dictionary:return result
	for track in value.get("favorites",[]) if value.get("favorites") is Array else []:
		if valid_track(track) and not result.favorites.has(track) and result.favorites.size() < MAX_TRACKS:result.favorites.append(track)
	for playlist in value.get("playlists",[]) if value.get("playlists") is Array else []:
		if not playlist is Dictionary or result.playlists.size() >= MAX_PLAYLISTS:continue
		var name := clean_name(playlist.get("name"))
		if name.is_empty() or find(result,name) >= 0:continue
		var tracks: Array = []
		for track in playlist.get("tracks",[]) if playlist.get("tracks") is Array else []:
			if valid_track(track) and tracks.size() < MAX_TRACKS:tracks.append(track)
		result.playlists.append({"name":name,"tracks":tracks})
	return result

static func find(library: Dictionary, name: String) -> int:
	var playlists: Array = library.get("playlists",[])
	for i in range(playlists.size()):
		if str(playlists[i].get("name",""))==name:return i
	return -1
