
use base64::Engine;
use serde_json::{json, Map, Value};
use smithay::reexports::calloop::generic::Generic;
use smithay::reexports::calloop::{Interest, Mode, PostAction};
use smithay::wayland::selection::data_device::{
    clear_data_device_selection, current_data_device_selection_userdata, request_data_device_client_selection,
    set_data_device_selection,
};
use smithay::wayland::selection::{SelectionSource, SelectionTarget};
use std::cell::RefCell;
use std::io::{ErrorKind, Read, Write};
use std::os::fd::{FromRawFd, OwnedFd};
use std::rc::Rc;
use std::sync::Arc;

use crate::protocol::MSG_CLIPBOARD;
use crate::state::State;

pub const TEXT_MIME_TYPES: [&str; 5] = ["text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "STRING", "TEXT"];
pub const IMAGE_MIME_TYPE: &str = "image/png";

const MAX_TEXT: usize = 16 * 1024 * 1024;
const MAX_IMAGE: usize = 32 * 1024 * 1024;

#[derive(PartialEq, Eq)]
pub struct MacClipboard {
    pub text: Option<String>,
    pub png: Option<Vec<u8>>,
}

impl MacClipboard {
    fn mime_types(&self) -> Vec<String> {
        let mut types: Vec<String> = Vec::new();
        if self.text.is_some() {
            types.extend(TEXT_MIME_TYPES.iter().map(|m| m.to_string()));
        }
        if self.png.is_some() {
            types.push(IMAGE_MIME_TYPE.to_string());
        }
        types
    }

    fn data_for(&self, mime_type: &str) -> Option<&[u8]> {
        if TEXT_MIME_TYPES.contains(&mime_type) {
            self.text.as_deref().map(str::as_bytes)
        } else if mime_type == IMAGE_MIME_TYPE {
            self.png.as_deref()
        } else {
            None
        }
    }
}

#[derive(Clone)]
pub enum Owner {
    Mac(Arc<MacClipboard>),
    X11,
}

pub fn set_from_mac(state: &mut State, text: Option<String>, png: Option<Vec<u8>>) {
    if text.is_none() && png.is_none() {
        return;
    }
    let clipboard = Arc::new(MacClipboard { text, png });
    let mime_types = clipboard.mime_types();
    state.clipboard_from_mac = Some(clipboard.clone());
    set_data_device_selection(&state.dh, &state.seat, mime_types.clone(), Owner::Mac(clipboard));
    if let Some(xwm) = state.xwm.as_mut() {
        let _ = xwm.new_selection(SelectionTarget::Clipboard, Some(mime_types));
        flush_x11(xwm);
    }
}

fn flush_x11(xwm: &smithay::xwayland::X11Wm) {
    let _ = xwm.get_randr_primary_output();
}

pub fn offer_to_x11(state: &mut State, mime_types: Vec<String>) {
    if let Some(xwm) = state.xwm.as_mut() {
        let _ = xwm.new_selection(SelectionTarget::Clipboard, Some(mime_types));
        flush_x11(xwm);
    }
}

pub fn send_owned(state: &mut State, owner: &Owner, mime_type: String, fd: OwnedFd) {
    match owner {
        Owner::Mac(clipboard) => write_to_client(clipboard, &mime_type, fd),
        Owner::X11 => {
            let handle = state.loop_handle.clone();
            if let Some(xwm) = state.xwm.as_mut() {
                let _ = xwm.send_selection(SelectionTarget::Clipboard, mime_type, fd, handle);
            }
        }
    }
}

pub fn x11_copied(state: &mut State, mime_types: Vec<String>) {
    set_data_device_selection(&state.dh, &state.seat, mime_types.clone(), Owner::X11);
    fetch_for_mac(state, &mime_types, |state, mime, fd| {
        let handle = state.loop_handle.clone();
        state
            .xwm
            .as_mut()
            .is_some_and(|xwm| xwm.send_selection(SelectionTarget::Clipboard, mime.to_string(), fd, handle).is_ok())
    });
}

pub fn x11_cleared(state: &mut State) {
    if matches!(current_data_device_selection_userdata(&state.seat).as_deref(), Some(Owner::X11)) {
        clear_data_device_selection(&state.dh, &state.seat);
    }
}

pub fn x11_paste(state: &mut State, mime_type: String, fd: OwnedFd) {
    let owner = current_data_device_selection_userdata(&state.seat).map(|o| o.clone());
    match owner {
        Some(Owner::Mac(clipboard)) => write_to_client(&clipboard, &mime_type, fd),
        Some(Owner::X11) => {}
        None => {
            let _ = request_data_device_client_selection(&state.seat, mime_type, fd);
        }
    }
}

fn write_to_client(clipboard: &Arc<MacClipboard>, mime_type: &str, fd: OwnedFd) {
    if clipboard.data_for(mime_type).is_none() {
        return;
    }
    let clipboard = clipboard.clone();
    let mime_type = mime_type.to_string();
    std::thread::spawn(move || {
        let mut file = std::fs::File::from(fd);
        if let Some(data) = clipboard.data_for(&mime_type) {
            let _ = file.write_all(data);
        }
    });
}

pub fn client_selection_changed(state: &mut State, source: SelectionSource) {
    let offered = source.mime_types();
    offer_to_x11(state, offered.clone());
    fetch_for_mac(state, &offered, |state, mime, fd| {
        match request_data_device_client_selection(&state.seat, mime.to_string(), fd) {
            Ok(()) => true,
            Err(error) => {
                tracing::debug!("cannot read selection: {error}");
                false
            }
        }
    });
}

#[derive(Default)]
struct Fetched {
    waiting: usize,
    text: Option<String>,
    png: Option<Vec<u8>>,
}

fn fetch_for_mac(state: &mut State, offered: &[String], mut request: impl FnMut(&mut State, &str, OwnedFd) -> bool) {
    if state.link.is_none() {
        return;
    }
    let text_mime = TEXT_MIME_TYPES.iter().find(|m| offered.iter().any(|o| o == *m)).copied();
    let image_mime = offered.iter().any(|o| o == IMAGE_MIME_TYPE).then_some(IMAGE_MIME_TYPE);
    state.clipboard_serial += 1;
    let serial = state.clipboard_serial;
    let fetched = Rc::new(RefCell::new(Fetched::default()));

    for (mime, is_image) in [(text_mime, false), (image_mime, true)] {
        let Some(mime) = mime else { continue };
        let Some((read_end, write_end)) = pipe() else { continue };
        if !request(state, mime, write_end) {
            continue;
        }
        fetched.borrow_mut().waiting += 1;
        let fetched = fetched.clone();
        let limit = if is_image { MAX_IMAGE } else { MAX_TEXT };
        read_pipe(state, read_end, limit, move |state, received| {
            let mut f = fetched.borrow_mut();
            if is_image {
                f.png = (!received.is_empty()).then_some(received);
            } else {
                f.text = Some(String::from_utf8_lossy(&received).into_owned()).filter(|t| !t.is_empty());
            }
            f.waiting -= 1;
            if f.waiting == 0 && serial == state.clipboard_serial {
                let (text, png) = (f.text.take(), f.png.take());
                drop(f);
                send_to_mac(state, text, png);
            }
        });
    }
}

pub fn read_pipe(state: &mut State, read_end: OwnedFd, limit: usize, done: impl FnOnce(&mut State, Vec<u8>) + 'static) {
    let mut received = Vec::new();
    let mut done = Some(done);
    let result = state.loop_handle.insert_source(
        Generic::new(std::fs::File::from(read_end), Interest::READ, Mode::Level),
        move |_, file, state| {
            let mut buffer = [0u8; 65536];
            loop {
                match unsafe { file.get_mut() }.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(n) => {
                        received.extend_from_slice(&buffer[..n]);
                        if received.len() > limit {
                            received.clear();
                            break;
                        }
                    }
                    Err(e) if e.kind() == ErrorKind::WouldBlock => return Ok(PostAction::Continue),
                    Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                    Err(_) => break,
                }
            }
            if let Some(done) = done.take() {
                done(state, std::mem::take(&mut received));
            }
            Ok(PostAction::Remove)
        },
    );
    if let Err(error) = result {
        tracing::warn!("cannot watch pipe: {error}");
    }
}

fn send_to_mac(state: &mut State, text: Option<String>, png: Option<Vec<u8>>) {
    if text.is_none() && png.is_none() {
        return;
    }
    let echo = MacClipboard { text, png };
    if state.clipboard_from_mac.as_deref() == Some(&echo) {
        return;
    }
    state.clipboard_from_mac = None;
    let mut message = Map::new();
    if let Some(text) = echo.text {
        message.insert("text".into(), json!(text));
    }
    if let Some(png) = echo.png {
        message.insert("image".into(), json!(base64::engine::general_purpose::STANDARD.encode(png)));
    }
    if let Some(link) = state.link.as_mut() {
        link.send_json(MSG_CLIPBOARD, &Value::Object(message));
    }
}

pub fn pipe() -> Option<(OwnedFd, OwnedFd)> {
    let mut fds = [0; 2];
    if unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) } != 0 {
        return None;
    }
    unsafe {
        libc::fcntl(fds[0], libc::F_SETFL, libc::O_NONBLOCK);
        Some((OwnedFd::from_raw_fd(fds[0]), OwnedFd::from_raw_fd(fds[1])))
    }
}
