# Must satisfy the go directive in go.mod. The official Go images set
# GOTOOLCHAIN=local, so a builder older than the directive fails the build
# instead of fetching a newer toolchain. cd-infra-worker-aws.yml passes the
# version read out of go.mod; the default is here for a bare docker build.
ARG GO_VERSION=1.25

FROM golang:${GO_VERSION} AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Static binary, so the runtime image needs no libc.
RUN CGO_ENABLED=0 go build -trimpath -o /out/worker ./cmd/worker

# No shell and no package manager: the worker only needs CA certificates to
# reach the AWS APIs, which distroless/static carries.
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/worker /worker

ENTRYPOINT ["/worker"]
