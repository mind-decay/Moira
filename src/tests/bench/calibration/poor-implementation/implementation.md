# Implementation: Search

## Changes

### src/products/page.tsx
- Added input field at top of page
- Added onChange handler that filters products array using indexOf
- Filter runs on every keystroke against full product list
- Results replace the product list in state

## Issues
- Filtering mutates the original product list — once filtered, removed products are lost until page refresh
- No debouncing on search input — fires API-like filter on every keystroke
- Search is case-sensitive (searching "shoes" won't find "Shoes")
- No "no results" message when filter returns empty array — page just shows blank
- Variable named `x` used for the search term instead of descriptive name
- Console.log statements left in production code
- No TypeScript types used despite project being TypeScript
