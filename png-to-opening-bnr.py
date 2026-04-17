import struct
import os
from PIL import Image

def convert_to_rgb5a3_tiled(image_path):
    """Converts image to GameCube's 4x4 tiled RGB5A3 format."""
    img = Image.open(image_path).convert("RGBA").resize((96, 32))
    pixels = img.load()
    out = bytearray(96 * 32 * 2) # Pre-allocate space for 0x1800 bytes

    # GameCube textures are stored in 4x4 pixel blocks (Tiles)
    for y_tile in range(0, 32, 4):
        for x_tile in range(0, 96, 4):
            # Inside each 4x4 block...
            for y in range(4):
                for x in range(4):
                    r, g, b, a = pixels[x_tile + x, y_tile + y]
                    
                    if a < 224: # ARGB3444 (Semi-transparent)
                        val = ((a // 32) << 12) | ((r // 16) << 8) | ((g // 16) << 4) | (b // 16)
                    else: # RGB555 (Opaque)
                        val = 0x8000 | ((r // 8) << 10) | ((g // 8) << 5) | (b // 8)
                    
                    # Calculate tile-based memory position
                    tile_idx = (y_tile // 4 * (96 // 4)) + (x_tile // 4)
                    pixel_in_tile = (y * 4) + x
                    byte_offset = (tile_idx * 16 + pixel_in_tile) * 2
                    
                    struct.pack_into(">H", out, byte_offset, val)
    return out

def create_gc_banner():
    print("--- GameCube Banner Creator (Interactive) ---")
    
    # 1. User Inputs
    img_file = input("Enter PNG filename (e.g., my_icon.png): ").strip()
    if not os.path.exists(img_file):
        print(f"Error: {img_file} not found!")
        return

    title = input("Enter Game Title (Short): ").strip()
    dev   = input("Enter Developer Name: ").strip()
    desc  = input("Enter Description: ").strip()
    
    region_choice = input("Region? (1 for NTSC-U/J, 2 for PAL): ").strip()
    is_pal = region_choice == "2"
    magic = b"BNR2" if is_pal else b"BNR1"

    # 2. Process Image
    print("Processing image tiling...")
    pixel_data = convert_to_rgb5a3_tiled(img_file)

    # 3. Prepare Metadata
    def pad_str(text, length):
        return text.encode('utf-8')[:length-1].ljust(length, b'\0')

    full_meta = (
        pad_str(title, 32) + 
        pad_str(dev, 32) + 
        pad_str(title, 64) + 
        pad_str(dev, 64) + 
        pad_str(desc, 128)
    )

    # 4. Construct File
    output_path = "opening.bnr"
    with open(output_path, "wb") as f:
        f.write(magic)
        f.write(b"\0" * 28) # Header padding
        f.write(pixel_data) # Tiled Image data
        
        # PAL (BNR2) needs 6 language slots; NTSC (BNR1) needs 1
        slots = 6 if is_pal else 1
        for _ in range(slots):
            f.write(full_meta)

    # 5. Final Size Check/Fix
    expected_size = 0x2100 if is_pal else 0x1960
    current_size = os.path.getsize(output_path)
    
    if current_size < expected_size:
        with open(output_path, "ab") as f:
            f.write(b"\0" * (expected_size - current_size))
            
    print("-" * 40)
    print(f"SUCCESS!")
    print(f"Created: {output_path}")
    print(f"Region: {'PAL' if is_pal else 'NTSC-U/J'}")
    print(f"Final Size: {os.path.getsize(output_path)} bytes")
    print("-" * 40)

if __name__ == "__main__":
    create_gc_banner()