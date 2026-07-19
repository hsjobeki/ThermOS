// Layer-shell software renderer: embed glyphs at build time (no runtime fontconfig).
fn main() {
    let config = slint_build::CompilerConfiguration::new()
        .embed_resources(slint_build::EmbedResourcesKind::EmbedForSoftwareRenderer);
    slint_build::compile_with_config("ui/top.slint", config).unwrap();
}
