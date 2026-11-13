"""Generate the narration through the user's local Voice Builder, using r1."""
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BASE = "http://voice-builder.devportal.localhost"
REFERENCE = "canonical:09d08b35-dd8e-43b4-9563-d1a80675d18b:r001"
segments = json.loads((ROOT / "script.json").read_text())
settings = json.loads((ROOT / "voice-settings.json").read_text())
(ROOT / 'work').mkdir(exist_ok=True)
(ROOT / 'audio').mkdir(exist_ok=True)
for i, segment in enumerate(segments):
    audio = ROOT / f"audio/{i:02}.wav"
    meta = ROOT / f"audio/{i:02}.json"
    if audio.exists() and audio.stat().st_size > 10000:
        continue
    payload = ROOT / f"work/request-{i:02}.json"
    payload.write_text(json.dumps({
        "reference_id": REFERENCE, "text": segment["text"],
        "caption": None, "seed": 12345, "settings": settings,
    }, ensure_ascii=False))
    print(f"Generating r1 narration {i+1}/{len(segments)}", flush=True)
    started = time.time()
    subprocess.run(["curl", "-fsS", "--max-time", "600", "-X", "POST",
                    "-H", "Content-Type: application/json", "--data-binary", f"@{payload}",
                    f"{BASE}/api/playground/synthesize", "-o", str(meta)], check=True)
    generation = json.loads(meta.read_text())
    assert generation["reference"]["id"] == REFERENCE, generation["reference"]
    subprocess.run(["curl", "-fsS", "--max-time", "60", BASE + generation["audio_url"],
                    "-o", str(audio)], check=True)
    print(f"Saved {audio.name}: {generation.get('duration_seconds')} sec ({time.time()-started:.1f}s)", flush=True)
