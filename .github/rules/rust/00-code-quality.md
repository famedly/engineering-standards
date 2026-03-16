# Rust Code Quality Standards

## Lints & Formatting

We use strict clippy lints and rustfmt rules. For the up-to-date configuration, see the [rust-project-template](https://github.com/famedly/rust-project-template/). Lints are defined in `Cargo.toml`, formatting in `rustfmt.toml`.

## Code Organization

- Always have a `lib.rs`
- Follow the [separation of concerns for binary projects](https://doc.rust-lang.org/book/ch12-03-improving-error-handling-and-modularity.html#separation-of-concerns-for-binary-projects) from The Rust Book

## Error Handling

**No panicking** – `unwrap` and `expect` are forbidden (also enforced by lints).

- **Tests**: `unwrap` is forbidden, but `expect` with a clear panic message is allowed
- **Explicit exceptions**: single-line `#[allow(clippy::unwrap_used)]` only where it is **guaranteed** not to panic
- **Libraries**: use [`thiserror`](https://docs.rs/thiserror/latest/thiserror/) for error type definitions
- **Services**: prefer `thiserror` for custom error types. `anyhow` may be used sparingly when a custom type would be too much boilerplate. When using anyhow, the actual error MUST be passed and context MUST be attached with `.context()`

## Async

- NEVER hold a synchronous lock (e.g. `std::sync::Mutex`) across an `.await` point – use `tokio::sync::Mutex` instead
- NEVER call blocking I/O or `std::thread::sleep` inside an async context – use `tokio::task::spawn_blocking` for unavoidable blocking work
- Sync-blocking in single-threaded async runtimes pauses execution of the entire program
- Every usage of a blocking lock in async code MUST have an inline comment explaining why it is safe

## Webservers

Services exposing a webserver MUST use [Axum](https://docs.rs/axum/latest/axum/) unless there is a documented reason not to.

The following [`tower-http`](https://docs.rs/tower-http/latest/tower_http/) middlewares MUST always be used:

- `CatchPanic`
- `SetSensitiveHeadersLayer` – for `Authorization` and other sensitive headers that MUST NOT be logged
- `SetRequestId`
- `PropagateRequestId`
