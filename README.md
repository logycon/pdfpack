# pdfpack

macOS app for bundling PDFs, images, text, and Word documents into a single PDF with a table of contents.

## Features
- Drag in multiple files, reorder them, and add titles/descriptions.
- Generates a combined PDF with a clickable table of contents.
- Saves and loads ".pack" files (JSON) to preserve your list and metadata.

## Requirements
- macOS 12+
- Swift 5.9 (Xcode 15+)

## Build and run
```sh
swift build
swift run pdfpack
```

## Using the app
1. Click "Add Files" and choose PDFs, images, text files, or Word docs.
2. Set titles and descriptions for each entry.
3. Reorder items with "Move Up/Down".
4. Click "Generate PDF" to preview, then save.

## Pack files
Pack files are JSON with a ".pack" extension and store absolute file paths.

Example:
```json
{
  "items": [
    {
      "path": "/Users/me/Documents/Report.pdf",
      "title": "Report",
      "description": "Q4 overview"
    }
  ]
}
```

## Supported inputs
- PDF
- Images: png, jpg, tiff, and other image types supported by macOS
- Text: txt
- Word: doc, docx

## Notes
- Missing files in a pack are skipped when loading.
- The generated PDF uses a fixed page size (US Letter).
