# Item storage drawing and input order

The inventory parent has z50. The original storage child also had relative z50,
so its effective drawing order was z100, above the quest helper's z60. Godot GUI
input uses tree order instead: moving the helper to the front let its invisible
close button receive real clicks while storage still covered its pixels.
An initial click-only PASS therefore did **not** establish correct rendering.

Storage now retains explicit z50 but disables relative z. Inventory labels have
relative z1 (effective z51), so the warehouse shade and content margin also use
z1: their effective z51 draws after the earlier bag subtree. All storage content
remains below helper z60. Parent move-to-front behavior and input policies are
unchanged. Background opacity is a separate preceding fix.

`item_storage_panel_layers_test.gd` uses actual hover targets and press/release
mouse events at 1280x720 and 390x844. It covers:

- Inventory entry -> warehouse tab -> helper, with visible helper close receiving
  input; closing restores warehouse tab/return input.
- Reverse navigation through the actual visible route: close helper, open bag,
  click warehouse entry, switch tab, return to the underlying bag. It never clicks
  an obscured bag entry or claims a hidden control is a valid navigation path.
- With `--visual-review`, rendered blank warehouse pixels covering the old bag
  description must remain dark; helper panel pixels must be above storage.
  These checks detect both defects that click-only tests missed.

Final eight offscreen PNGs are in `/private/tmp/ui-panel-storage-shots/`, one each
of `opaque-warehouse`, `helper-over-warehouse`, `warehouse-after-helper`, and
`returned-bag` for each size. They were individually inspected. The intermediate
z50-only label leak diagnosis is preserved at
`/private/tmp/ui-panel-storage-regression/390x844-z50-label-leak.png`.
Headless runs verify input only; no inventory transaction or large-capacity test
is duplicated here. Source opacity change plus these three z settings affect
presentation only, with no save, session, RPC, parent or helper controller change.
