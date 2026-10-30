# Vavrio icon

The developer selected [VavrioIcon-minimal-dark.png](VavrioIcon-minimal-dark.png) on 2026-10-30 as Vavrio's current logo: a warm off-white architectural mark on a near-black background. After the developer reported an inset Dock appearance, the source was revised to an opaque 1254 × 1254 square: the dark background reaches every edge and the larger symbol occupies roughly 64% of the canvas. The artwork has no pre-rounded tile or transparent outer margin. It was created using the built-in image-generation tool; the initial design, inversion, and edge-to-edge correction prompts are retained in [the provenance notes](VavrioIcon-minimal-dark-prompt.md).

At the developer's request, the earlier V, gradient portal, and light minimal pictures and their separate draft notes were removed from the project. This directory retains one logo image and its documentation.

Scripts/package-app.sh uses the selected PNG to generate standard/Retina representations and VavrioFull.icns with the existing sips/iconutil tools. Generated iconsets and signed application bundles stay under ignored .build output. Resizing preserves the source PNG. The retained master is raster; there is no vector master.
