# capsula-art

Album-art colours on the ring of the VK Capsula Mini while an AirPlay session
is live.

The stock `capsule-tweaker` stays the ring owner. The daemon only overlays a
cover: it reads the newest file in shairport-sync's cover cache, picks two or
three distinct chromatic clusters, and writes a 12-pixel frame with
`ringled`. A new cover must be stable for 200 ms before it is adopted, colours
cross-fade in 300 ms, and the stock indication wins back as soon as the session
ends. Volume changes pause the overlay for two seconds so the stock level
indication stays readable, and assistant states (`listening`, `thinking`,
`speaking`) pause it too.

Artwork always comes from the sender. Nothing is fetched from the network and
no image is generated locally.

## Build

Requires Go 1.23 or newer; the result is a static binary, so CGO is off:

```sh
cd src/capsula-art
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o ../../bin/capsula-art .
```

`go mod vendor` is not committed; the build fetches `golang.org/x/image`
(TIFF covers, which Apple sends as `cover-*.tif`).

## Test

```sh
go test ./...                                  # palette and gradient
./capsula-art --palette cover.jpg              # palette of one image
./capsula-art --paint 004E8C,F2B026,3E8C4C     # one static frame, for wiring
```
