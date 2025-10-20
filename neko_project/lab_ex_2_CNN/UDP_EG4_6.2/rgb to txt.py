from PIL import Image

EXPECTED_WIDTH = 80
EXPECTED_HEIGHT = 100


def rgb_to_txt(image_path, output_txt_path, expected_w=EXPECTED_WIDTH, expected_h=EXPECTED_HEIGHT):
    img = Image.open(image_path).convert("RGB")
    width, height = img.size

    assert width == expected_w and height == expected_h, f"图像尺寸必须为 {expected_w}x{expected_h}"

    pixels = list(img.getdata())

    with open(output_txt_path, "w", encoding="utf-8") as f:
        for idx, (r, g, b) in enumerate(pixels):
            address = f"{idx:04x}"  # 4位十六进制地址（0x0000 ~ 0x1f3f）
            rgb_hex = f"{r:02x}{g:02x}{b:02x}"  # 每个通道2位，共6位
            line = f"f1{address}{rgb_hex}"
            f.write(line + "\n")

    print(f"转换完成，共写入 {len(pixels)} 行，保存为：{output_txt_path}")


if __name__ == "__main__":
    rgb_to_txt("logo.png", "output_logo.txt")
