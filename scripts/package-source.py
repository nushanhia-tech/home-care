from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root=Path(__file__).resolve().parent.parent
with ZipFile(root/'dist/source.zip','w',ZIP_DEFLATED) as archive:
    for item in root.rglob('*'):
        relative=item.relative_to(root)
        if any(part in {'node_modules','dist','.git','.wrangler'} for part in relative.parts):continue
        if item.is_file() and item.name not in {'.env','.env.local'}:
            archive.write(item,relative)
