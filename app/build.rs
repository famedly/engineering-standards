//! Build script — emits git and build metadata via vergen for `env!()` access.

fn main() -> Result<(), Box<dyn std::error::Error>> {
    vergen::EmitBuilder::builder()
        .all_build()
        .all_git()
        .emit()?;
    Ok(())
}
