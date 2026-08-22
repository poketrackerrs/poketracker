GAME BOX DIELINES (optional, for authentic 3D boxes)
====================================================

Drop a full box "dieline" (the flattened box net showing front, spine, back,
and flaps) here, named by the game ID with a .png extension, e.g.:

  red.png, blue.png, yellow.png, gold.png, ...

When a dieline is present for a game, the 3D box crops its FRONT, SPINE, and
TOP panels straight from the image and maps them onto the box faces — giving
the real metallic spine (e.g. the "GAME BOY" logo) and accurate box depth.

Games with NO dieline here just use the normal front cover + generated spine.

PANEL LAYOUT
------------
The crop regions are defined as fractions of the image in
lib/widgets/game_box_art.dart (see kGbDieline). They are tuned for the common
Game Boy-era fan dieline layout (front panel on the right, vertical spine to
its left, back panel on the left, flaps in the middle).

If your dieline uses a different layout, the panels will crop in the wrong
place — tell me and I'll adjust the fractions (or add a second layout preset).
