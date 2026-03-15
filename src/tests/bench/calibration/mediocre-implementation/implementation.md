# Implementation: Export to CSV

## Changes Made

### src/reports/controller.ts
- Added `exportToCsv()` method directly in the controller
- Iterates over report data rows, joins fields with commas
- Creates header row from object keys
- Uses `window.document.createElement('a')` to trigger download

### src/reports/page.tsx
- Added "Export CSV" button that calls controller.exportToCsv()

## Known Issues
- CSV does not escape commas within field values (will break CSV format)
- Large reports may cause browser to hang (no streaming/chunking)
- Date fields exported in raw ISO format without localization
- No loading indicator during export
