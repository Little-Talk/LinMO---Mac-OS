
use std::path::Path;

const MAX_SIZE: u32 = 128;

pub struct Icon {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

impl Icon {
    pub fn load(app_id: &str) -> Option<Icon> {
        let path = crate::apps::icon_for_app_id(app_id)?;
        let (width, height, rgba) = if is_svg(&path) { rasterize_svg(&path, MAX_SIZE)? } else { decode_png(&path)? };
        let (width, height, rgba) = shrink(width, height, rgba);
        let mut pixels = Vec::with_capacity(rgba.len());
        for pixel in rgba.chunks_exact(4) {
            let alpha = pixel[3] as u32;
            let premultiply = |c: u8| ((c as u32 * alpha + 127) / 255) as u8;
            pixels.extend_from_slice(&[premultiply(pixel[2]), premultiply(pixel[1]), premultiply(pixel[0]), pixel[3]]);
        }
        Some(Icon { width, height, pixels })
    }

    pub fn message(&self, id: u32) -> Vec<u8> {
        let mut payload = Vec::with_capacity(12 + self.pixels.len());
        for value in [id, self.width, self.height] {
            payload.extend_from_slice(&value.to_le_bytes());
        }
        payload.extend_from_slice(&self.pixels);
        payload
    }
}

pub fn is_svg(path: &Path) -> bool {
    path.extension().and_then(|e| e.to_str()).is_some_and(|e| e.eq_ignore_ascii_case("svg"))
}

pub fn rasterize_svg(path: &Path, size: u32) -> Option<(u32, u32, Vec<u8>)> {
    if std::fs::metadata(path).ok()?.len() > 4 * 1024 * 1024 {
        return None;
    }
    let data = std::fs::read(path).ok()?;
    let tree = resvg::usvg::Tree::from_data(&data, &resvg::usvg::Options::default()).ok()?;
    let original = tree.size();
    let zoom = size as f32 / original.width().max(original.height());
    let (width, height) = (
        ((original.width() * zoom).round() as u32).max(1),
        ((original.height() * zoom).round() as u32).max(1),
    );
    let mut pixmap = resvg::tiny_skia::Pixmap::new(width, height)?;
    resvg::render(&tree, resvg::tiny_skia::Transform::from_scale(zoom, zoom), &mut pixmap.as_mut());
    let mut rgba = Vec::with_capacity((width * height * 4) as usize);
    for pixel in pixmap.pixels() {
        let c = pixel.demultiply();
        rgba.extend_from_slice(&[c.red(), c.green(), c.blue(), c.alpha()]);
    }
    Some((width, height, rgba))
}

pub fn svg_to_png(path: &Path, size: u32) -> Option<Vec<u8>> {
    let (width, height, rgba) = rasterize_svg(path, size)?;
    let mut out = Vec::new();
    let mut encoder = png::Encoder::new(&mut out, width, height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    encoder.write_header().ok()?.write_image_data(&rgba).ok()?;
    Some(out)
}

fn decode_png(path: &Path) -> Option<(u32, u32, Vec<u8>)> {
    if std::fs::metadata(path).ok()?.len() > 4 * 1024 * 1024 {
        return None;
    }
    let mut decoder = png::Decoder::new(std::fs::File::open(path).ok()?);
    decoder.set_transformations(png::Transformations::normalize_to_color8());
    let mut reader = decoder.read_info().ok()?;
    let mut buffer = vec![0; reader.output_buffer_size()];
    let frame = reader.next_frame(&mut buffer).ok()?;
    let (width, height) = (frame.width, frame.height);
    if width == 0 || height == 0 || width > 1024 || height > 1024 {
        return None;
    }
    let data = &buffer[..frame.buffer_size()];
    let pixels = (width * height) as usize;
    let mut rgba = Vec::with_capacity(pixels * 4);
    match frame.color_type {
        png::ColorType::Rgba => rgba.extend_from_slice(data),
        png::ColorType::Rgb => data.chunks_exact(3).for_each(|p| rgba.extend_from_slice(&[p[0], p[1], p[2], 255])),
        png::ColorType::GrayscaleAlpha => data.chunks_exact(2).for_each(|p| rgba.extend_from_slice(&[p[0], p[0], p[0], p[1]])),
        png::ColorType::Grayscale => data.iter().for_each(|g| rgba.extend_from_slice(&[*g, *g, *g, 255])),
        png::ColorType::Indexed => return None,
    }
    (rgba.len() == pixels * 4).then_some((width, height, rgba))
}

fn shrink(width: u32, height: u32, rgba: Vec<u8>) -> (u32, u32, Vec<u8>) {
    let longest = width.max(height);
    if longest <= MAX_SIZE {
        return (width, height, rgba);
    }
    let (new_w, new_h) = ((width * MAX_SIZE / longest).max(1), (height * MAX_SIZE / longest).max(1));
    let mut out = Vec::with_capacity((new_w * new_h * 4) as usize);
    for y in 0..new_h {
        let (y0, y1) = (y * height / new_h, ((y + 1) * height / new_h).max(y * height / new_h + 1));
        for x in 0..new_w {
            let (x0, x1) = (x * width / new_w, ((x + 1) * width / new_w).max(x * width / new_w + 1));
            let mut sum = [0u32; 4];
            for sy in y0..y1 {
                for sx in x0..x1 {
                    let i = ((sy * width + sx) * 4) as usize;
                    let alpha = rgba[i + 3] as u32;
                    for c in 0..3 {
                        sum[c] += rgba[i + c] as u32 * alpha;
                    }
                    sum[3] += alpha;
                }
            }
            let count = (x1 - x0) * (y1 - y0);
            let alpha = sum[3];
            let color = |c: usize| sum[c].checked_div(alpha).unwrap_or(0) as u8;
            out.extend_from_slice(&[color(0), color(1), color(2), (alpha / count) as u8]);
        }
    }
    (new_w, new_h, out)
}
