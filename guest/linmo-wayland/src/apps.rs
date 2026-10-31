
use base64::Engine;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

struct Entry {
    id: String,
    name: String,
    generic: String,
    categories: Vec<String>,
    icon: String,
}

fn application_dirs() -> Vec<PathBuf> {
    let mut dirs = vec![
        PathBuf::from("/usr/share/applications"),
        PathBuf::from("/usr/local/share/applications"),
        PathBuf::from("/var/lib/snapd/desktop/applications"),
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
    ];
    if let Ok(home) = std::env::var("HOME") {
        dirs.push(Path::new(&home).join(".local/share/applications"));
    }
    dirs
}

fn read_fields(path: &Path) -> Option<BTreeMap<String, String>> {
    let text = std::fs::read_to_string(path).ok()?;
    let mut in_entry = false;
    let mut fields: BTreeMap<String, String> = BTreeMap::new();
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry || line.starts_with('#') {
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            fields.entry(key.trim().to_string()).or_insert_with(|| value.trim().to_string());
        }
    }
    Some(fields)
}

fn parse(path: &Path, lang: &str) -> Option<Entry> {
    let fields = read_fields(path)?;
    let get = |k: &str| fields.get(k).cloned().unwrap_or_default();
    if get("Type") != "Application"
        || get("NoDisplay").eq_ignore_ascii_case("true")
        || get("Hidden").eq_ignore_ascii_case("true")
        || get("Exec").is_empty()
    {
        return None;
    }
    let id = path.file_stem()?.to_string_lossy().to_string();
    let short_lang = lang.split('_').next().unwrap_or("");
    let name = fields
        .get(&format!("Name[{lang}]"))
        .or_else(|| fields.get(&format!("Name[{short_lang}]")))
        .or_else(|| fields.get("Name"))
        .cloned()
        .unwrap_or_else(|| id.clone());
    Some(Entry {
        id,
        name,
        generic: get("GenericName"),
        categories: get("Categories").split(';').filter(|c| !c.is_empty()).map(String::from).collect(),
        icon: get("Icon"),
    })
}

fn find_icon(name: &str) -> Option<PathBuf> {
    find_icon_with(name, &["png", "svg"])
}

fn find_icon_with(name: &str, extensions: &[&str]) -> Option<PathBuf> {
    if name.is_empty() {
        return None;
    }
    let path = Path::new(name);
    if path.is_absolute() {
        let known = path.extension().and_then(|e| e.to_str()).is_some_and(|e| extensions.contains(&e));
        return (known && path.is_file()).then(|| path.to_path_buf());
    }
    let mut bases = vec![PathBuf::from("/usr/share/icons"), PathBuf::from("/usr/local/share/icons")];
    if let Ok(home) = std::env::var("HOME") {
        bases.push(Path::new(&home).join(".local/share/icons"));
    }
    let themes = ["hicolor", "Adwaita", "elementary-xfce", "elementary", "Papirus", "Yaru", "breeze", "gnome"];
    let sizes = ["64x64", "48x48", "128x128", "96x96", "256x256", "scalable"];
    for base in &bases {
        for theme in themes {
            for size in sizes {
                for ext in extensions {
                    let candidate = base.join(theme).join(size).join("apps").join(format!("{name}.{ext}"));
                    if candidate.is_file() {
                        return Some(candidate);
                    }
                }
            }
        }
    }
    extensions
        .iter()
        .map(|ext| PathBuf::from(format!("/usr/share/pixmaps/{name}.{ext}")))
        .find(|p| p.is_file())
}

pub fn icon_for_app_id(app_id: &str) -> Option<PathBuf> {
    if app_id.is_empty() || app_id.contains('/') {
        return None;
    }
    let wanted = format!("{}.desktop", app_id.to_lowercase());
    let mut by_class = None;
    for dir in application_dirs() {
        let Ok(read) = std::fs::read_dir(&dir) else { continue };
        for item in read.flatten() {
            let path = item.path();
            let name = item.file_name().to_string_lossy().to_lowercase();
            if !name.ends_with(".desktop") {
                continue;
            }
            let exact = name == wanted;
            let Some(fields) = read_fields(&path) else { continue };
            let icon = fields.get("Icon").cloned().unwrap_or_default();
            if exact {
                if let Some(found) = find_icon(&icon) {
                    return Some(found);
                }
            } else if by_class.is_none()
                && fields.get("StartupWMClass").is_some_and(|c| c.eq_ignore_ascii_case(app_id))
            {
                by_class = find_icon(&icon);
            }
        }
    }
    by_class.or_else(|| find_icon(app_id))
}

pub fn list() -> Value {
    let lang = std::env::var("LANG").unwrap_or_default();
    let lang = lang.split('.').next().unwrap_or("").to_string();
    let mut apps: BTreeMap<String, Value> = BTreeMap::new();
    for dir in application_dirs() {
        let Ok(read) = std::fs::read_dir(&dir) else { continue };
        for item in read.flatten() {
            let path = item.path();
            if path.extension().and_then(|e| e.to_str()) != Some("desktop") {
                continue;
            }
            let Some(entry) = parse(&path, &lang) else { continue };
            let mut app = json!({
                "id": entry.id,
                "name": entry.name,
                "generic": entry.generic,
                "categories": entry.categories,
            });
            if let Some(icon) = find_icon(&entry.icon) {
                if std::fs::metadata(&icon).map(|m| m.len() <= 256 * 1024).unwrap_or(false) {
                    let svg = crate::icons::is_svg(&icon);
                    let converted = if svg { crate::icons::svg_to_png(&icon, 128) } else { None };
                    let bytes = converted.clone().or_else(|| std::fs::read(&icon).ok());
                    if let Some(bytes) = bytes {
                        app["icon"] = json!(base64::engine::general_purpose::STANDARD.encode(bytes));
                        app["iconFormat"] = json!(if svg && converted.is_none() { "svg" } else { "png" });
                    }
                }
            }
            apps.insert(entry.id.clone(), app);
        }
    }
    let mut list: Vec<Value> = apps.into_values().collect();
    list.sort_by_key(|a| a["name"].as_str().unwrap_or("").to_lowercase());
    json!({ "apps": list })
}

pub fn launch(app_id: &str, wayland_display: &str, x_display: Option<u32>) {
    if app_id.is_empty() || app_id.contains('/') {
        return;
    }
    let mut command = Command::new("gtk-launch");
    command
        .arg(app_id)
        .env("WAYLAND_DISPLAY", wayland_display)
        .env("XDG_SESSION_TYPE", "wayland")
        .env("GDK_BACKEND", "wayland,x11")
        .env("QT_QPA_PLATFORM", "wayland;xcb")
        .env("MOZ_ENABLE_WAYLAND", "1")
        .env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
        .env("SDL_VIDEODRIVER", "wayland")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if let Some(display) = x_display {
        command.env("DISPLAY", format!(":{display}"));
    }
    unsafe {
        use std::os::unix::process::CommandExt;
        command.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    if let Err(error) = command.spawn() {
        tracing::warn!("launch {app_id} failed: {error}");
    }
}
