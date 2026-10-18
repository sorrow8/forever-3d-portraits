# 1.0.2

- Dead, released, offline and tapped units show the game's own tinted picture instead of a full-colour model.
- A unit that comes back after its frame was hidden (target cleared, then targeted again) gets its model loaded again, so a new look or shape shows.
- A model that finishes loading after the unit came back into sight is shown, not left blank.
- With the Edit Mode party background on, party portraits stay above it.
- Where the game hides a unit's identity from addons, portraits no longer risk a Lua error.
- The character window's tabs keep their icons instead of getting a model.
- The NPC windows help and the README list every window that gets a model.

# 1.0.1

- 3D under the ring only on unit frames; windows keep the model above their portrait.
- A model is loaded again only for a new unit, not on every portrait update.
- The portrait size is kept inside 70-85% in the window too.
- The game's Options page follows the language picked in the window.

# 1.0.0

- First version: living 3D portraits for unit frames, party frames and NPC windows.
