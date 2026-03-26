//! Fixed string-literal patterns compiled once for [`LazyLock`] statics.

use regex::Regex;

/// Compiles a pattern that is fixed in source. A bad pattern is a programmer error.
#[must_use]
pub fn compile(pattern: &'static str) -> Regex {
	#[allow(clippy::expect_used)]
	Regex::new(pattern).expect("invalid static regex pattern")
}
