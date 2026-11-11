# Floating bottom navigation

Build 7 adapts the supplied moving-notch reference to the existing dark green,
gold, and cream theme. The active icon sits inside a gold circle; its notch and
circle share one animated position so their movement stays aligned. Menu labels
remain visible, including the active label. The bar supports three or four menu
items, safe-area insets, RTL positioning, focus, tooltips, and selected semantics.

Navigation moves over 380 ms with easeInOutCubic; incoming pages fade and slide
a short distance over 280 ms. System reduced-motion preference disables both
animations. Dashboard shortcuts and schedule notification taps use the same tab
selection method. Tapping an already-selected tab does not replay the animation.

Pages remain lazily initialized inside the original keyed IndexedStack. Switching
tabs does not dispose their state, clear searches, or refetch schedules. Inactive
page tickers remain paused. The transition animates the surrounding render
objects rather than rebuilding page contents every frame. There are no new
packages, API routes, or database changes.

Validation: 68 Flutter tests pass and analysis is clean. Navigation tests cover
320 px screens with 180% text, three/four items, indicator movement between frames,
selected accessibility semantics, reduced motion, tab permission visibility, and
retaining timetable search/data when returning to a previously opened tab.

## Build 9: generated Stitch refinement

The authenticated Stitch design is in project `17552918936715416614`, screen
`418312dca4c84dcda6d0fc4dd961b048` (Jadwal Mengajar - Bottom Tab Refinement).
Reference exports: [screenshot](design/stitch-navigation.png) and
[interactive HTML](design/stitch-navigation.html). The reference contains sample
schedule content; only its navigation design is applied to the app.

The bar uses tangent curved shoulders with a 6 px clearance around the gold
indicator. A shared 380 ms controller moves both cradle and indicator. Long
jumps crossfade only the previous and requested icons; intermediate icons stay
stationary. Rapid taps retarget from the current position without snapping.
The existing lazy page state, permission visibility, safe areas, semantics, and
reduced-motion behavior are preserved. No dependencies or database changes.

Validation: 72 Flutter tests pass, including long jumps and interrupted motion;
static analysis is clean. Android build 9 uses the existing application ID and
signing certificate, so installation can update the app without clearing data.
