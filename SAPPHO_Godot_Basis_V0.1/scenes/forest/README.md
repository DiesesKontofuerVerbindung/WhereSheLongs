# Forest ownership

This directory is owned by the Forest programmer.

Use `res://shared/player/player.tscn` instead of creating a separate Player.

Forest-specific systems stay here unless a shared reuse case is explicitly approved:

- parkour/running sequence;
- scripted surreal waterfall jump/transition (**not** a standalone waterfall-descent minigame);
- stepping/jumping across stones;
- drowning/oxygen value and narrative Game Over;
- firefly navigation;
- heart-light visual interaction;
- dream-world collapse;
- forest-specific camera effects or shaders.

Scene-local tests belong under `scenes/forest/tests/**` and are Forest-owned. Root `tests/**` remains protected shared infrastructure.
