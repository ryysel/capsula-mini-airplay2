# Rebuilding the 2019 artwork tools

The receiver build and its AP2 local-control patch are in `build/build-2019.sh` and `build/capsula-media-control.c` at repository root. The tested receiver is Shairport Sync 5.6.2; NQPTP is 1.2.9. It requires the cross-builder and stock system libraries described in `build/Dockerfile`.

Build the Go companion from this directory:

```sh
cd capsula-ui
go test -race ./...
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -buildvcs=false -trimpath -o ../../bin/capsula-ui .
```

Build the standalone LED broker with an aarch64 Linux cross compiler:

```sh
aarch64-linux-gnu-gcc -O2 -static -o ../bin/capsula-led-media ledctl.c
```

The broker is the only direct LED writer. Its `daemon` mode yields to voice-agent, accepts expiring artwork frames from the companion, and falls back to the clock. It does not require an external capsula-led installation. If an older standalone clock service exists, the package pauses it and restores it when stopped.

`capsula-ui` decodes JPEG/PNG/TIFF, reads only the current artwork cache, and sends play/pause through a root-only local AP2 socket. The stock purr sink is muted only while that socket reports a session. No credentials, firmware dump or stock voice-agent binary are included.
