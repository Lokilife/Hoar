from pathlib import Path
from typing import TypedDict

current_dir = Path.cwd()
target_dir = current_dir / "initrd"

target_dir.mkdir(parents=True, exist_ok=True)

class MyFile(TypedDict):
    name: str
    size: int
    data: bytes

files: list[MyFile] = []

for item in target_dir.iterdir():
    if item.is_file():
        print(f"File: {item.name}; Size: {item.stat().st_size} bytes;")
        data = item.read_bytes()
        files.append({"name": item.name, "size": item.stat().st_size, "data": data})

target_file = current_dir / "initrd.bin"
res = bytearray()

res.extend(len(files).to_bytes(4, "little"))

for file in files:
    res.extend(len(file["name"]).to_bytes(4, "little"))
    res.extend(bytearray(file["name"], encoding="utf-8"))
    res.extend(file["size"].to_bytes(4, "little"))
    res.extend(file["data"])

target_file.write_bytes(res)
