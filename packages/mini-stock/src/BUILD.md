# Mini stock renderer

`capsula-ui` is built from `packages/capsula-2019/src/capsula-ui` for BOTH
stock models. On Mini it detects `/dev/topleds`, renders the 12 RGB pixels via
ioctl, and leaves the stock numeric display alone. On 2019 it writes frames
to the single LED broker. The old C ring source is historical, not installed.
Both renderers use the same tested palette and a PCM RMS/peak envelope.
Native numeric volume display is provided by the exact-hash voice-agent guard
patch, not a competing clock writer. One reboot is needed after first install.
