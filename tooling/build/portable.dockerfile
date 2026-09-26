FROM rust:1.98.1-bookworm
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
COPY ml/evaluation/fixtures/sample-run.json ./ml/evaluation/fixtures/sample-run.json
RUN cargo test --locked -p reha-core --features onnx-download && cargo build --locked --release -p reha-cli --features onnx-download
ENTRYPOINT ["/app/target/release/reha"]
