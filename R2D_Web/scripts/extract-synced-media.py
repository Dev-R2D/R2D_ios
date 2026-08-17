from __future__ import annotations

import json
import sys
from fractions import Fraction
from pathlib import Path

import av
from PIL import Image


def upright(frame: av.VideoFrame) -> Image.Image:
    return frame.to_image().rotate(-90, expand=True)


def extract_frame(video_path: Path, seconds: float, output_path: Path) -> None:
    with av.open(str(video_path)) as container:
        stream = container.streams.video[0]
        container.seek(int(max(0, seconds - 1) / float(stream.time_base)), stream=stream, backward=True)
        for frame in container.decode(stream):
            if float(frame.time or 0) >= seconds:
                image = upright(frame)
                image.thumbnail((720, 1280), Image.Resampling.LANCZOS)
                output_path.parent.mkdir(parents=True, exist_ok=True)
                image.save(output_path, quality=88, optimize=True)
                return
    raise RuntimeError(f"No frame at {seconds:.3f}s")


def extract_clip(video_path: Path, start: float, duration: float, output_path: Path) -> None:
    fps = 24
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with av.open(str(video_path)) as source, av.open(str(output_path), mode="w", options={"movflags": "+faststart"}) as target:
        source_stream = source.streams.video[0]
        target_stream = target.add_stream("libx264", rate=fps, options={"crf": "28", "preset": "veryfast"})
        target_stream.width = 360
        target_stream.height = 640
        target_stream.pix_fmt = "yuv420p"
        target_stream.time_base = Fraction(1, fps)
        source.seek(int(max(0, start - 1) / float(source_stream.time_base)), stream=source_stream, backward=True)
        next_sample = start
        frame_number = 0
        for frame in source.decode(source_stream):
            timestamp = float(frame.time or 0)
            if timestamp < next_sample:
                continue
            if timestamp >= start + duration:
                break
            image = upright(frame).resize((360, 640), Image.Resampling.LANCZOS)
            output_frame = av.VideoFrame.from_image(image)
            output_frame.pts = frame_number
            output_frame.time_base = Fraction(1, fps)
            for packet in target_stream.encode(output_frame):
                target.mux(packet)
            frame_number += 1
            next_sample = start + frame_number / fps
        for packet in target_stream.encode():
            target.mux(packet)


def main() -> None:
    video_path = Path(sys.argv[1])
    project_dir = Path(sys.argv[2])
    data = json.loads((project_dir / "app" / "data" / "latest-capture.json").read_text(encoding="utf-8"))
    public_dir = project_dir / "public" / "latest-capture"
    event_dir = public_dir / "events"

    for event in data["events"]:
        event_id = int(event["id"])
        event_time = float(event["time"])
        extract_frame(video_path, event_time, event_dir / f"event-{event_id:02d}.jpg")
        extract_clip(video_path, max(0, event_time - 3), 6, event_dir / f"event-{event_id:02d}.mp4")

    preview_start = max(0, float(data["events"][0]["time"]) - 5)
    extract_frame(video_path, float(data["events"][0]["time"]), public_dir / "preview-synced.jpg")
    extract_clip(video_path, preview_start, 12, public_dir / "representative-preview.mp4")


if __name__ == "__main__":
    main()
