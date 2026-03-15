# Review Findings: Export to CSV

## Summary
Basic functionality works for simple cases but has several quality issues.

## Findings

### Blocking Issues
- **B1**: CSV fields containing commas will corrupt the output. Must wrap fields in quotes or escape commas.
- **B2**: No handling for null/undefined values in data rows.

### Non-Blocking Issues
- **N1**: Export logic mixed into controller; should be a separate utility
- **N2**: No test coverage for CSV generation
- **N3**: Button lacks accessibility attributes (aria-label)
- **N4**: No error handling if report data is empty
