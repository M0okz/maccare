"""Locate App Intents constants from the compiler's output map."""
import json
from pathlib import Path


def constant_files(root: Path, configuration: str, architecture: str) -> list[Path]:
    intermediates = root / 'app/.build/out/Intermediates.noindex'
    source = (root / 'app/Sources/MacCare/BatteryAppIntents.swift').resolve()
    maps = []
    for path in intermediates.glob(f'**/{configuration}/**/Objects-normal/{architecture}/MacCare-OutputFileMap.json'):
        output = json.loads(path.read_text())
        if any(key and Path(key).resolve() == source for key in output):
            maps.append((path, output))
    if len(maps) != 1:
        available = sorted(str(p.relative_to(intermediates)) for p in intermediates.glob('**/*OutputFileMap.json'))
        raise ValueError(f'Expected one MacCare {configuration}/{architecture} output map; found {len(maps)}. Available: {available[:12]}')
    path, output = maps[0]
    values = sorted({Path(item['const-values']) for item in output.values() if 'const-values' in item})
    if not values or any(not value.is_file() for value in values):
        raise ValueError(f'App Intents constants missing from compiler output map: {path}')
    return values
