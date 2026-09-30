#!/usr/bin/env python3
"""Extract a few members of a remote ZIP without downloading all of it.

    fetch_zip_members.py URL DEST PATTERN... [--size-only]

Reads the archive's central directory and the matching members with HTTP range
requests, so the web export templates (four web_*.zip files, about 40 MB) come
out of Godot's 1.25 GB export template archive without fetching the rest.
PATTERN is an fnmatch pattern on the member name; each match is written to
DEST under its base name. --size-only prints the matching members' total size
and writes nothing. Exits 3 when the server ignores range requests; the caller
then downloads the whole archive instead.
"""
import fnmatch
import io
import os
import sys
import urllib.request
import zipfile


class RangeFile(io.RawIOBase):
    """A read-only, seekable view of a remote file through HTTP range requests."""

    def __init__(self, url):
        self.position = 0
        request = urllib.request.Request(url, headers={"Range": "bytes=0-0"})
        with urllib.request.urlopen(request, timeout=60) as response:
            if response.status != 206:
                raise RangeUnsupported(url)
            # Follow GitHub's redirect once instead of on every read.
            self.url = response.geturl()
            self.size = int(response.headers["Content-Range"].rsplit("/", 1)[1])

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=io.SEEK_SET):
        base = {io.SEEK_SET: 0, io.SEEK_CUR: self.position, io.SEEK_END: self.size}[whence]
        self.position = base + offset
        return self.position

    def readinto(self, buffer):
        end = min(self.position + len(buffer), self.size)
        if end <= self.position:
            return 0
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={self.position}-{end - 1}"})
        for attempt in range(5):
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    data = response.read()
                break
            except OSError:
                if attempt == 4:
                    raise
        buffer[:len(data)] = data
        self.position += len(data)
        return len(data)


class RangeUnsupported(Exception):
    pass


def main():
    arguments = [argument for argument in sys.argv[1:] if argument != "--size-only"]
    size_only = len(arguments) != len(sys.argv) - 1
    if len(arguments) < 3:
        sys.exit(__doc__)
    url, destination, patterns = arguments[0], arguments[1], arguments[2:]
    try:
        remote = io.BufferedReader(RangeFile(url), buffer_size=4 << 20)
    except RangeUnsupported:
        print(f"{url} does not support range requests", file=sys.stderr)
        sys.exit(3)
    with zipfile.ZipFile(remote) as archive:
        members = [info for info in archive.infolist()
                   if not info.is_dir() and any(fnmatch.fnmatch(info.filename, pattern) for pattern in patterns)]
        if not members:
            sys.exit(f"No member of {url} matches {' '.join(patterns)}")
        if size_only:
            print(sum(info.compress_size for info in members))
            return
        os.makedirs(destination, exist_ok=True)
        for info in members:
            target = os.path.join(destination, os.path.basename(info.filename))
            with archive.open(info) as source, open(target + ".part", "wb") as output:
                while chunk := source.read(1 << 20):
                    output.write(chunk)
            os.replace(target + ".part", target)
            print(f"{os.path.basename(info.filename)} ({info.file_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
