FROM rust:1.98.1-bookworm
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
COPY tests/fixtures/sample-run.json ./tests/fixtures/sample-run.json
COPY src-tauri/Cargo.toml src-tauri/build.rs src-tauri/tauri.conf.json ./src-tauri/
COPY src-tauri/src ./src-tauri/src
COPY plugins ./plugins
RUN cargo test --locked -p reha-core --features onnx-download && cargo build --locked --release -p reha-core --features onnx-download
ENTRYPOINT ["/app/target/release/reha"]
