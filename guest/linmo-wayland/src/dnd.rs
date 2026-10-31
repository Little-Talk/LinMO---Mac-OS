
use smithay::input::pointer::{ButtonEvent, GrabStartData, MotionEvent};
use smithay::backend::input::ButtonState;
use smithay::reexports::calloop::timer::{TimeoutAction, Timer};
use smithay::reexports::wayland_server::protocol::wl_data_device_manager::DndAction;
use smithay::reexports::wayland_server::Resource;
use smithay::utils::{Point, SERIAL_COUNTER};
use smithay::wayland::selection::data_device::{start_dnd, with_source_metadata, SourceMetadata};
use std::io::Write;
use std::os::fd::{AsFd, OwnedFd};
use std::path::PathBuf;
use std::time::Duration;

use crate::protocol::{MSG_DRAG_DATA, MSG_DRAG_NONE};
use crate::state::State;

const URI_LIST: &str = "text/uri-list";
const BTN_LEFT: u32 = 0x110;
const STEP: Duration = Duration::from_millis(120);

struct Drop {
    id: u32,
    x: f64,
    y: f64,
    paths: Vec<PathBuf>,
}

fn unpack(payload: &[u8]) -> Option<Drop> {
    let json_len = u32::from_le_bytes(payload.get(0..4)?.try_into().ok()?) as usize;
    let meta: serde_json::Value = serde_json::from_slice(payload.get(4..4 + json_len)?).ok()?;
    let folder = PathBuf::from(std::env::var("HOME").ok()?).join("Downloads").join("LinMO");
    std::fs::create_dir_all(&folder).ok()?;
    let mut offset = 4 + json_len;
    let mut paths = Vec::new();
    for item in meta["files"].as_array()? {
        let size = item["size"].as_u64()? as usize;
        let data = payload.get(offset..offset + size)?;
        offset += size;
        let name = std::path::Path::new(item["name"].as_str().unwrap_or(""))
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .filter(|n| !n.is_empty())
            .unwrap_or_else(|| "file".into());
        let path = unique_path(&folder, &name);
        if std::fs::write(&path, data).is_ok() {
            paths.push(path);
        }
    }
    Some(Drop {
        id: meta["id"].as_u64().unwrap_or(0) as u32,
        x: meta["x"].as_f64().unwrap_or(0.0),
        y: meta["y"].as_f64().unwrap_or(0.0),
        paths,
    })
}

fn unique_path(folder: &std::path::Path, name: &str) -> PathBuf {
    let mut path = folder.join(name);
    let stem = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    let ext = path.extension().map(|e| format!(".{}", e.to_string_lossy())).unwrap_or_default();
    let mut n = 2;
    while path.exists() {
        path = folder.join(format!("{stem} {n}{ext}"));
        n += 1;
    }
    path
}

fn file_uri(path: &std::path::Path) -> String {
    let mut uri = String::from("file://");
    for byte in path.to_string_lossy().bytes() {
        if byte.is_ascii_alphanumeric() || b"/-_.~".contains(&byte) {
            uri.push(byte as char);
        } else {
            uri.push_str(&format!("%{byte:02X}"));
        }
    }
    uri
}

pub fn receive(state: &mut State, payload: &[u8]) {
    let Some(drop) = unpack(payload) else { return };
    if drop.paths.is_empty() || state.window(drop.id).is_none() {
        return;
    }
    let uris: String = drop.paths.iter().map(|p| file_uri(p) + "\r\n").collect();
    state.drop_uris = Some(uris);
    crate::protocol::focus(state, drop.id);

    crate::protocol::pointer_to(state, drop.id, drop.x, drop.y);
    let pointer = state.seat.get_pointer().unwrap();
    let start = GrabStartData { focus: None, button: BTN_LEFT, location: pointer.current_location() };
    let (dh, seat) = (state.dh.clone(), state.seat.clone());
    let metadata = SourceMetadata { mime_types: vec![URI_LIST.into()], dnd_action: DndAction::Copy };
    start_dnd(&dh, &seat, state, SERIAL_COUNTER.next_serial(), Some(start), None, metadata);
    crate::protocol::pointer_to(state, drop.id, drop.x, drop.y);

    let (id, x, y) = (drop.id, drop.x, drop.y);
    let mut step = 0;
    let _ = state.loop_handle.insert_source(Timer::from_duration(STEP), move |_, _, state| {
        step += 1;
        if step == 1 {
            crate::protocol::pointer_to(state, id, x + 1.0, y);
            return TimeoutAction::ToDuration(STEP);
        }
        let pointer = state.seat.get_pointer().unwrap();
        let time = state.now_ms();
        pointer.button(
            state,
            &ButtonEvent { button: BTN_LEFT, state: ButtonState::Released, serial: SERIAL_COUNTER.next_serial(), time },
        );
        pointer.frame(state);
        TimeoutAction::Drop
    });
}

pub fn send(state: &mut State, mime_type: &str, fd: OwnedFd) {
    if mime_type != URI_LIST {
        return;
    }
    if let Some(uris) = state.drop_uris.clone() {
        std::thread::spawn(move || {
            let _ = std::fs::File::from(fd).write_all(uris.as_bytes());
        });
    }
}


const DRAG_OUT_LIMIT: usize = 1 << 30;

pub fn drag_out(state: &mut State) {
    let source = state.client_drag.clone().filter(|s| s.is_alive());
    let has_uris = source.as_ref().is_some_and(|s| {
        with_source_metadata(s, |m| m.mime_types.iter().any(|t| t == URI_LIST)).unwrap_or(false)
    });
    let (Some(source), true) = (source, has_uris) else {
        return reply_none(state);
    };
    let Some((read_end, write_end)) = crate::clipboard::pipe() else { return reply_none(state) };
    source.send(URI_LIST.into(), write_end.as_fd());
    drop(write_end);
    crate::clipboard::read_pipe(state, read_end, 1 << 20, |state, list| {
        cancel_client_drag(state);
        let paths: Vec<PathBuf> = String::from_utf8_lossy(&list)
            .lines()
            .filter_map(|line| line.trim().strip_prefix("file://"))
            .map(|path| PathBuf::from(percent_decode(path.trim_start_matches(|c| c != '/'))))
            .filter(|path| path.is_file())
            .collect();
        match pack_files(&paths) {
            Some(payload) => {
                if let Some(link) = state.link.as_mut() {
                    link.send(MSG_DRAG_DATA, &payload);
                }
            }
            None => reply_none(state),
        }
    });
}

fn reply_none(state: &mut State) {
    if let Some(link) = state.link.as_mut() {
        link.send_json(MSG_DRAG_NONE, &serde_json::json!({}));
    }
}

fn cancel_client_drag(state: &mut State) {
    let pointer = state.seat.get_pointer().unwrap();
    let time = state.now_ms();
    let away = pointer.current_location() + Point::from((-100_000.0, -100_000.0));
    pointer.motion(state, None, &MotionEvent { location: away, serial: SERIAL_COUNTER.next_serial(), time });
    pointer.frame(state);
    pointer.unset_grab(state, SERIAL_COUNTER.next_serial(), time);
    state.client_drag = None;
}

fn pack_files(paths: &[PathBuf]) -> Option<Vec<u8>> {
    let mut entries = Vec::new();
    let mut contents = Vec::new();
    for path in paths {
        let Ok(data) = std::fs::read(path) else { continue };
        if contents.len() + data.len() > DRAG_OUT_LIMIT {
            break;
        }
        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        entries.push(serde_json::json!({ "name": name, "size": data.len() }));
        contents.extend_from_slice(&data);
    }
    if entries.is_empty() {
        return None;
    }
    let meta = serde_json::to_vec(&serde_json::json!({ "files": entries })).ok()?;
    let mut payload = Vec::with_capacity(4 + meta.len() + contents.len());
    payload.extend_from_slice(&(meta.len() as u32).to_le_bytes());
    payload.extend_from_slice(&meta);
    payload.extend_from_slice(&contents);
    Some(payload)
}

fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(byte) = u8::from_str_radix(&text[i + 1..i + 3], 16) {
                out.push(byte);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}
