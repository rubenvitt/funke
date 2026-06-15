# funke-relay: statisches Go-Binary, keine Dependencies.
# Build-Stage laeuft nativ auf der Runner-Arch (BUILDPLATFORM) und
# cross-kompiliert fuer die Ziel-Arch -> kein QEMU-Overhead beim Compile.
FROM --platform=$BUILDPLATFORM golang:1.23-alpine AS build
WORKDIR /src
ARG TARGETOS TARGETARCH
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /funke-relay .

# Minimal-Runtime (distroless, läuft als root für geteilten Vault-Volume-Zugriff).
FROM gcr.io/distroless/static-debian12
COPY --from=build /funke-relay /funke-relay
EXPOSE 8787
ENTRYPOINT ["/funke-relay"]
