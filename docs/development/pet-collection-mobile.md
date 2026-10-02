# Pet collection on narrow viewports

The old collection window laid out its native pet card at x=0, tools at x=288,
and growth forecast at x=560. Those fixed columns clipped at a 390px viewport.

Below 960px, `pet_collection_mobile.gd` reuses the controls built by the original
pet panel and arranges them inside one bounded vertical scroll container. The
native pet art stays at its original size. Small native buttons have labelled
44px touch counterparts connected to the original controls' signals; category,
helper actions and growth labels retain their existing callbacks and content.
The close button stays above the scroll region. Resize rebuilds the collection;
ordinary refresh uses the existing scroll capture/restore behavior. Desktop
viewports at or above 960px keep the original arrangement.

This is a UI adaptation, not an original-game feature. It does not modify the
backend, Session, save schema, comparison sorting, inventory or quest helper.
The comparison, warehouse, records and other helper panels retain their own
existing layouts.

`pet_collection_mobile_test` covers real viewport clicks, selection, rename,
skills and return, paging, scrolling to the final growth note, refresh state,
44px controls, no horizontal overflow, desktop layout, and a real localhost
WebSocket client's store action with no client backend. `--visual-review`
additionally saves actual rendered 390×844 and 1280×720 images under
`/private/tmp/pet-collection-mobile`; headless runs do not establish pixel
correctness. Rendering must use a muted offscreen window and isolated test
user data. Existing collection/window/modal/comparison suites remain required.
