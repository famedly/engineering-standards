//! Language/ecosystem scope detection for repositories.

mod detector;

pub use detector::{Scope, detect_scopes, detect_scopes_for_repo, scopes_to_strings};
