# App Icon Sources

These files are original project artwork created for the 1.7.3 icon review.

- `candidate-a-book-check.svg`: selected book-and-check direction.
- `candidate-b-notebook-bookmark.svg`: archived notebook-and-bookmark direction.

Palette:

- Paper: `#F7F5EC`
- Sheet: `#FFFDF5`
- Ink: `#243E34`
- Sage: `#DFE8D8`
- Dark sage: `#8DAF91`

Generate Android legacy, adaptive, round, and monochrome resources from the
maintained raster source with:

```text
python study_assistant-1.1.0/local_app/tool/generate_app_icons.py --candidate a --install
```

The SVG files are the editable design sources. The raster generator mirrors
their geometry at all Android densities. No third-party icon asset is
included.
