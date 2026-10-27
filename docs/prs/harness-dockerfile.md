# Dockerfile: rustock-cli on Ubuntu 22.04, linux/amd64 and linux/arm64

Branch `harness/dockerfile` in `clients/rustock`, on `lerner/main` (43dc5e5). One commit.

## What and why

The lab runs rustock in Docker on a Mac (arm64) and as a plain binary on the Boton boxes
(amd64, Ubuntu 22.04, glibc 2.35). The build stage is `ubuntu:22.04`, so the binary links
against that glibc; rustup installs the toolchain `rust-toolchain.toml` pins (1.93.1), so the
image builds with the same rustc as a developer. The runtime image is `ubuntu:22.04` with
`/usr/local/bin/rustock-cli` and no entrypoint. `.dockerignore` keeps `target/` and `.git/` out
of the context. The lab keeps a copy as `docker/rustock.Dockerfile`.

## How to test

```bash
docker build -t rustock .
docker buildx build --platform linux/amd64,linux/arm64 -t rustock .
docker run --rm rustock rustock-cli --version
```
