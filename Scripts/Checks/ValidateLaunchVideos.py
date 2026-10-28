#!/usr/bin/env python3
"""Validate the offline launch assets shipped by both application targets."""

import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2] / "Shared/Resources/Launch"
for name, dimensions in (("landscape", (768, 720)), ("portrait", (404, 720))):
    video = root / f"watermelon-launch-{name}.mp4"
    assert video.is_file(), f"Missing bundled launch movie: {video}"
    info = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(video),
    ]))
    streams = info["streams"]
    assert len(streams) == 1 and streams[0]["codec_type"] == "video", "Launch must have no audio track"
    assert streams[0]["codec_name"] == "h264", "Launch must use hardware-compatible H.264"
    assert (streams[0]["width"], streams[0]["height"]) == dimensions
    assert 3.8 <= float(info["format"]["duration"]) <= 4.3, "Unexpected launch duration"
    subprocess.run(["ffmpeg", "-v", "error", "-xerror", "-i", str(video), "-f", "null", "-"], check=True)
    for frame in ("first", "last"):
        poster = root / f"watermelon-launch-{name}-{frame}.png"
        assert poster.is_file(), f"Missing launch poster: {poster}"
        metadata = json.loads(subprocess.check_output([
            "ffprobe", "-v", "error", "-show_streams", "-of", "json", str(poster),
        ]))["streams"][0]
        assert (metadata["width"], metadata["height"]) == dimensions, "Poster must match movie framing"
    print(f"PASS: {name} launch movie decodes, is silent, and matches both posters")
