# funke-relay: statisches Go-Binary, keine Dependencies.
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /funke-relay .

# Minimal-Runtime (distroless, läuft als root für geteilten Vault-Volume-Zugriff).
FROM gcr.io/distroless/static-debian12
COPY --from=build /funke-relay /funke-relay
EXPOSE 8787
ENTRYPOINT ["/funke-relay"]
