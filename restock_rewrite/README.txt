GROCERY GETTER — RESTOCK BOX VISUAL REWRITE

This bundle generates COMPLETE replacement scripts from your CURRENT local
GitHub checkout, rather than overwriting the other 2,000+ lines of your
player script with an older copy.

1. Commit or back up your existing working tree.
2. Copy apply_rewrite.py into the ROOT of your grocery_getter repository.
3. Run: python3 apply_rewrite.py
4. Open Godot and allow the new script class RestockBoxVisual to import.
5. Review `git diff` and check the debugger before multiplayer testing.

The generator writes complete versions of:
  scripts/player/low_poly_character_FP.gd
  scripts/player/player_equipment.gd
  scripts/items/product_display.gd
  resources/equipment/restock_box.tres
  scripts/items/restock_box_visual.gd (new)
  scenes/items/restock_box_visual.tscn (new)

World `RestockBox` and its original scene remain unchanged.
Backups of overwritten files are created with suffix .before_rewrite.

TEST: Host pickup, client pickup, original despawn on both machines,
correct labels, restock once only, and repeated deliveries.

Note: Godot was not available in the build environment, so this rewrite
has not been runtime-tested. Do not discard your backups until tested.
