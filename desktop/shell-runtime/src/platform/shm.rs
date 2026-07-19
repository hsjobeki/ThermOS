use slint::platform::software_renderer::{PremultipliedRgbaColor, TargetPixel};

/// wl_shm `Xrgb8888` is a little-endian 32-bit word `0x00RRGGBB`, i.e. bytes
/// `[B, G, R, X]`. We store the word in a `#[repr(transparent)]` u32; native
/// (x86_64/aarch64 = LE) writes land as `[B, G, R, 0]`, which is what the
/// compositor reads back as `Xrgb8888`. The blend math mirrors
/// `i_slint_renderer_software`'s `Rgb8Pixel` impl (opaque surface: alpha ignored
/// on read). No GL/EGL is needed; the software renderer writes straight into shm.
#[repr(transparent)]
#[derive(Copy, Clone)]
pub(crate) struct ShmPixel(u32);

impl ShmPixel {
    #[inline]
    fn pack(r: u8, g: u8, b: u8) -> Self {
        ShmPixel((r as u32) << 16 | (g as u32) << 8 | b as u32)
    }
}

impl TargetPixel for ShmPixel {
    fn blend(&mut self, color: PremultipliedRgbaColor) {
        let a = (u8::MAX - color.alpha) as u16;
        let r = ((self.0 >> 16) as u8 as u16 * a / 255) as u8 + color.red;
        let g = ((self.0 >> 8) as u8 as u16 * a / 255) as u8 + color.green;
        let b = (self.0 as u8 as u16 * a / 255) as u8 + color.blue;
        *self = ShmPixel::pack(r, g, b);
    }
    fn from_rgb(r: u8, g: u8, b: u8) -> Self {
        ShmPixel::pack(r, g, b)
    }
}
