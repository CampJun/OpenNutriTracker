# Bundled USDA Staple Foods replace network food sources

Food search in this fork finds only Staple Foods bundled with the app plus the user's own foods and recipes. Open Food Facts and the Supabase multi-source backend are switched off. The goal is a small, curated, offline set of accurate foods to weigh, not broad coverage: OFF and the backend mostly added prepared, branded, and non-US foods. Staple Foods come from USDA Foundation Foods, with SR Legacy filling the gaps. We chose USDA over Danish Frida and French CIQUAL because the user shops in the US, and US cuts, varieties, and fortification matter more than a small edge in lab quality.

The OFF and Supabase code stays in the tree, disabled where it is wired up, not deleted. This fork still merges upstream releases, and deleting code spread across about 30 frequently changed upstream files would turn every sync into conflicts. Deleting it is a later cleanup once we stop syncing.

## Considered Options

- Keep Supabase and put Staple Foods alongside it: rejected. It keeps the backend dependency and the clutter.
- Delete the OFF and Supabase code outright: deferred until upstream syncing stops.
