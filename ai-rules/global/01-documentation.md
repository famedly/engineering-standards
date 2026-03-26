# Documentation Rules

These rules define the minimum documentation standard for all languages. Language-specific rules (e.g. `dart/`, `rust/`) may specify the exact comment syntax and tooling – they extend these rules, not replace them.

## Mandatory Requirements

### Functions and Methods
- Every public function/method MUST have a documentation comment
- The comment MUST include: purpose, parameters (with types), return value, and possible exceptions/errors
- Single-line functions with self-explanatory names are exempt

### Classes and Types
- Every public class, struct, or type MUST have a documentation comment describing its purpose
- Complex attributes MUST be documented inline

### Examples

Dart (`///` dartdoc):

```dart
/// Calculates the final price after applying a percentage discount.
///
/// Throws a [RangeError] if [percent] is outside 0–100.
double calculateDiscount(double price, double percent) {
```

Rust (`///` doc comment):

```rust
/// Calculates the final price after applying a percentage discount.
///
/// # Errors
///
/// Returns [`DiscountError::InvalidPercent`] if `percent` is outside 0–100.
fn calculate_discount(price: f64, percent: f64) -> Result<f64, DiscountError> {
```

## Prohibited

- Commented-out code without an explanation of why it is still present
- TODO comments without a linked issue/ticket (required format: `TODO(#123): Description`)
- Misleading or outdated comments that do not match the code
