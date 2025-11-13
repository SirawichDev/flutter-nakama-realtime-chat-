FROM heroiclabs/nakama-pluginbuilder:3.24.0 AS builder

WORKDIR /workspace/go

COPY data/modules/go/ ./

RUN go mod download && \
    go build -trimpath -buildmode=plugin -o /workspace/image_upload.so .

FROM heroiclabs/nakama:3.24.0

COPY --from=builder /workspace/image_upload.so /nakama/data/modules/image_upload.so
COPY data/modules/go/ /nakama/data/modules/go/
COPY local.yml /nakama/local.yml
