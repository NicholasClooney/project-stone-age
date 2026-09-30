"""Fill missing logical scenery graphics without reusing another archive's IDs."""
FALLBACK_BITMAP_BASE = 1_000_000_000


class FallbackArchive:
    def __init__(self, primary, fallback, logical_ids):
        self.primary=primary
        self.fallback=fallback
        self.entries=dict(primary.entries)
        self.map_ids=dict(primary.map_ids)
        self.fallback_images={}
        self.logical_ids=[]
        for logical in sorted(set(logical_ids)):
            if logical in self.map_ids or logical not in fallback.map_ids:
                continue
            original=fallback.map_ids[logical]
            bitmap=FALLBACK_BITMAP_BASE+original
            if bitmap in primary.entries:raise ValueError('Fallback bitmap namespace collision')
            self.entries[bitmap]=dict(fallback.entries[original],id=bitmap)
            self.map_ids[logical]=bitmap
            self.fallback_images[bitmap]=original
            self.logical_ids.append(logical)

    def image(self, bitmap):
        if bitmap in self.fallback_images:
            return self.fallback.image(self.fallback_images[bitmap])
        return self.primary.image(bitmap)
