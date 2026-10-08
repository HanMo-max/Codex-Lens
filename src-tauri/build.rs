use std::{env, fs, path::PathBuf, process::Command};

fn build_macos_swift_bridges() {
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }

    let target = env::var("TARGET").expect("TARGET must be set by Cargo");
    let swift_target = match target.as_str() {
        "aarch64-apple-darwin" => "arm64-apple-macos14.0",
        "x86_64-apple-darwin" => "x86_64-apple-macos14.0",
        other => panic!("unsupported macOS target for Swift bridges: {other}"),
    };
    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR must be set by Cargo"));
    let reload_object = out_dir.join("widget_reload.o");
    let snapshot_object = out_dir.join("shared_snapshot.o");
    let status_popover_object = out_dir.join("status_popover.o");
    let module_cache = out_dir.join("swift-module-cache");
    fs::create_dir_all(&module_cache).expect("failed to create Swift module cache");

    for (source, object) in [
        ("src/widget_reload.swift", &reload_object),
        ("src/shared_snapshot.swift", &snapshot_object),
        ("src/status_popover.swift", &status_popover_object),
    ] {
        let status = Command::new("xcrun")
            .arg("swiftc")
            .arg("-module-cache-path")
            .arg(&module_cache)
            .arg("-parse-as-library")
            .arg("-O")
            .arg("-emit-object")
            .arg("-target")
            .arg(swift_target)
            .arg(source)
            .arg("-o")
            .arg(object)
            .status()
            .expect("failed to start swiftc for macOS bridge");
        assert!(status.success(), "failed to compile macOS bridge source");
    }

    println!("cargo:rustc-link-arg={}", reload_object.display());
    println!("cargo:rustc-link-arg={}", snapshot_object.display());
    println!("cargo:rustc-link-arg={}", status_popover_object.display());
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=WidgetKit");
    println!("cargo:rerun-if-changed=src/widget_reload.swift");
    println!("cargo:rerun-if-changed=src/shared_snapshot.swift");
    println!("cargo:rerun-if-changed=src/status_popover.swift");
}

fn main() {
    build_macos_swift_bridges();
    tauri_build::build();
}
