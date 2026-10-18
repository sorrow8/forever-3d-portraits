# 1.0.3

- The model's square never grows past 80% of the circle, where its corners stay under the ring art; a bigger face comes from bringing the camera closer, so no corner sticks out and the dark edge stays thin.
- Unit frame portraits follow the game's own tint: when the game greys, blues (ghost), reddens (low health) or desaturates (offline) the picture, the flat picture shows so you see it; back to 3D when the tint goes.

# 1.0.2

- Fix: a model the game had cached could fire its loaded event while being shown and loop until a "C stack overflow" error.
- Dead, released, offline and tapped units show the game's own picture instead of a full-colour model (the game tints it grey where it does so on its own); a new unit on the same frame is checked afresh.
- A unit that comes back after its frame was hidden (target cleared, then targeted again) gets its model loaded again, so a new look or shape shows.
- A model that finishes loading after the unit came back into sight is shown, not left blank.
- With the Edit Mode party background on, party portraits stay above it: the background moves to the bottom layer.
- Where the game hides a unit's identity, a model is not reloaded on every redraw; a new target, focus, pet or party member is noticed from the game's events and shows the flat picture until its model is there.
- Tapping by someone else is noticed at once.
- Health and state events only check portraits that are on screen.
- Where the game hides a unit's identity from addons, portraits no longer risk a Lua error.
- The side tabs of the character and inspect windows keep their icons instead of getting a model.
- The NPC windows help and the README list every window that gets a model.

# 1.0.1

- 3D under the ring only on unit frames; windows keep the model above their portrait.
- A model is loaded again only for a new unit, not on every portrait update.
- The portrait size is kept inside 70-85% in the window too.
- The game's Options page follows the language picked in the window.

# 1.0.0

- First version: living 3D portraits for unit frames, party frames and NPC windows.
