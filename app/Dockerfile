FROM rust:1.85-bookworm AS builder

WORKDIR /build
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release && rm -rf src

COPY src/ src/
COPY migrations/ migrations/
COPY templates/ templates/
RUN touch src/main.rs && cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/engineering-standards-app /usr/local/bin/app
COPY templates/ /app/templates/
COPY migrations/ /app/migrations/

ENV LISTEN_ADDR=0.0.0.0:3000
EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/app"]
