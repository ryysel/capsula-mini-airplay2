"""Build a gzip installer for each firmware from the verified package manifest."""
import argparse
import gzip
import hashlib
import tarfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
version = (root / "VERSION").read_text().strip()
results = []
for model in ("capsula-2019", "mini-stock", "mini-a113x"):
    package = root / "packages" / model
    paths = [root / f for f in ("install.sh", "uninstall.sh", "LICENSE", "VERSION", "README.md", "docs/AUDIT_CANDIDATE.md")]
    paths.extend(sorted((root / "licenses").glob("*")))
    paths.append(package / "SHA256SUMS")
    for entry in (package / "SHA256SUMS").read_text().splitlines():
        digest, name = entry.split("  ", 1)
        path = package / name
        if not path.resolve().is_relative_to(package) or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Invalid input: {path}")
        paths.append(path)
    output = args.output / f"capsula-airplay-{model}-{version}.tar.gz"
    tmp = output.with_suffix(".tmp")
    with tmp.open("wb") as stream, gzip.GzipFile(filename="", fileobj=stream, mode="wb", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w|") as tar:
            for path in sorted(paths):
                info = tar.gettarinfo(str(path), f"capsula-airplay-{model}/{path.relative_to(root)}")
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ""
                with path.open("rb") as data:
                    tar.addfile(info, data)
    tmp.replace(output)
    results.append(f"{hashlib.sha256(output.read_bytes()).hexdigest()}  {output.name}")
    print(f"{output.name}: {output.stat().st_size:,} bytes")
(args.output / "SHA256SUMS.models").write_text("\n".join(results) + "\n")
