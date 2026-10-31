
use base64::Engine;
use serde_json::{json, Value};
use smithay::backend::input::{Axis, AxisSource, ButtonState, KeyState};
use smithay::input::keyboard::{FilterResult, Keycode};
use smithay::input::pointer::{AxisFrame, ButtonEvent, MotionEvent};
use smithay::utils::{Logical, Point, SERIAL_COUNTER};

use crate::state::State;
use crate::text::Stroke;
use crate::window::{dismiss_popups_of, resend_all, Role};

pub const VERSION: u32 = 5;

pub const MSG_HELLO: u16 = 0x01;
pub const MSG_WINDOW: u16 = 0x02;
pub const MSG_WINDOW_CLOSED: u16 = 0x03;
pub const MSG_FRAME: u16 = 0x04;
pub const MSG_APPS: u16 = 0x05;
pub const MSG_FOCUSED: u16 = 0x06;
pub const MSG_FRAME_RECT: u16 = 0x07;
pub const MSG_ICON: u16 = 0x08;
pub const MSG_DRAG_DATA: u16 = 0x09;
pub const MSG_DRAG_NONE: u16 = 0x0A;
pub const MSG_CLIPBOARD: u16 = 0x0B;
pub const MSG_TEXT_INPUT: u16 = 0x0C;
const MSG_POINTER: u16 = 0x10;
const MSG_BUTTON: u16 = 0x11;
const MSG_KEY: u16 = 0x12;
const MSG_SCROLL: u16 = 0x13;
const MSG_RESIZE: u16 = 0x14;
const MSG_FOCUS: u16 = 0x15;
const MSG_CLOSE: u16 = 0x16;
const MSG_LAUNCH: u16 = 0x17;
const MSG_STREAM: u16 = 0x18;
const MSG_TEXT: u16 = 0x19;
const MSG_DROP: u16 = 0x1A;
const MSG_CONFIG: u16 = 0x1B;
const MSG_DRAG_OUT: u16 = 0x1C;
const MSG_SET_CLIPBOARD: u16 = 0x1D;
const MSG_PREEDIT: u16 = 0x1E;

const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;
const BTN_MIDDLE: u32 = 0x112;
const KEY_LEFTSHIFT_X11: u32 = 50;
const KEY_ESCAPE_X11: u32 = 9;

pub fn hello(state: &mut State) {
    let (w, h) = state.screen_pixels();
    let message = json!({
        "version": VERSION,
        "features": ["damage", "text", "scale", "wayland", "icons", "drop", "dragout", "clipboard", "clipboard-image", "popupclose", "preedit"],
        "screen": [w, h],
    });
    if let Some(link) = state.link.as_mut() {
        link.send_json(MSG_HELLO, &message);
        link.send_json(MSG_APPS, &crate::apps::list());
    }
    resend_all(state);
    crate::text_input::resend_all(state);
}

pub fn handle(state: &mut State, kind: u16, payload: &[u8]) {
    if kind == MSG_DROP {
        return crate::dnd::receive(state, payload);
    }
    let msg: Value = serde_json::from_slice(payload).unwrap_or(Value::Null);
    let id = msg["id"].as_u64().unwrap_or(0) as u32;
    let num = |key: &str| msg[key].as_f64().unwrap_or(0.0);

    match kind {
        MSG_POINTER => pointer_to(state, id, num("x"), num("y")),
        MSG_BUTTON => {
            pointer_to(state, id, num("x"), num("y"));
            let pressed = msg["pressed"].as_bool().unwrap_or(false);
            if pressed {
                focus(state, id);
            }
            let button = match msg["button"].as_u64().unwrap_or(1) {
                3 => BTN_RIGHT,
                2 => BTN_MIDDLE,
                _ => BTN_LEFT,
            };
            let pointer = state.seat.get_pointer().unwrap();
            let time = state.now_ms();
            pointer.button(
                state,
                &ButtonEvent {
                    button,
                    state: if pressed { ButtonState::Pressed } else { ButtonState::Released },
                    serial: SERIAL_COUNTER.next_serial(),
                    time,
                },
            );
            pointer.frame(state);
        }
        MSG_SCROLL => {
            pointer_to(state, id, num("x"), num("y"));
            let pointer = state.seat.get_pointer().unwrap();
            let mut frame = AxisFrame::new(state.now_ms()).source(AxisSource::Wheel);
            for (axis, steps) in [(Axis::Vertical, num("dy")), (Axis::Horizontal, num("dx"))] {
                if steps != 0.0 {
                    frame = frame.value(axis, steps * 15.0).v120(axis, (steps * 120.0) as i32);
                }
            }
            pointer.axis(state, frame);
            pointer.frame(state);
        }
        MSG_KEY => {
            let code = msg["keycode"].as_u64().unwrap_or(0) as u32;
            let pressed = msg["pressed"].as_bool().unwrap_or(false);
            if pressed {
                if !state.pressed.contains(&code) {
                    state.pressed.push(code);
                }
            } else {
                state.pressed.retain(|c| *c != code);
            }
            key(state, code, pressed);
        }
        MSG_TEXT => type_text(state, msg["text"].as_str().unwrap_or("")),
        MSG_FOCUS => focus(state, id),
        MSG_RESIZE => {
            let scale = state.scale;
            let w = (num("w") as i32 / scale).max(1);
            let h = (num("h") as i32 / scale).max(1);
            match state.window(id).map(|w| &w.role) {
                Some(Role::Toplevel(toplevel)) => {
                    toplevel.with_pending_state(|s| s.size = Some((w, h).into()));
                    toplevel.send_pending_configure();
                }
                Some(Role::X11(window)) if !window.is_override_redirect() => crate::xwayland::resize(window, w, h),
                _ => {}
            }
        }
        MSG_CLOSE => match state.window(id).map(|w| &w.role) {
            Some(Role::Toplevel(toplevel)) => toplevel.send_close(),
            Some(Role::Popup(popup)) => {
                let kind = smithay::desktop::PopupKind::Xdg(popup.clone());
                if let Ok(root) = smithay::desktop::find_popup_root_surface(&kind) {
                    if let Some(root_id) = state.windows.iter().find(|w| w.surface == root).map(|w| w.id) {
                        dismiss_popups_of(state, root_id);
                    }
                }
            }
            Some(Role::X11(window)) if !window.is_override_redirect() => {
                let _ = window.close();
            }
            Some(Role::X11(_)) => {
                key(state, KEY_ESCAPE_X11, true);
                key(state, KEY_ESCAPE_X11, false);
            }
            None => {}
        },
        MSG_DRAG_OUT => crate::dnd::drag_out(state),
        MSG_PREEDIT => {
            crate::text_input::preedit(state, msg["text"].as_str().unwrap_or(""), msg["cursor"].as_i64().unwrap_or(-1));
        }
        MSG_SET_CLIPBOARD => {
            let text = msg["text"].as_str().filter(|t| !t.is_empty()).map(String::from);
            let png = msg["image"].as_str().and_then(|b64| base64::engine::general_purpose::STANDARD.decode(b64).ok());
            crate::clipboard::set_from_mac(state, text, png);
        }
        MSG_LAUNCH => crate::apps::launch(msg["app"].as_str().unwrap_or(""), &state.socket_name.clone(), state.x_display),
        MSG_STREAM => {
            state.streaming = msg["enabled"].as_bool().unwrap_or(false);
            resend_all(state);
            if state.streaming {
                if let Some(link) = state.link.as_mut() {
                    link.send_json(MSG_APPS, &crate::apps::list());
                }
            }
        }
        MSG_CONFIG => {
            if let Some(scale) = msg["scale"].as_f64() {
                state.set_scale(scale.round() as i32);
                resend_all(state);
            }
        }
        _ => {}
    }
}

pub fn pointer_to(state: &mut State, id: u32, x: f64, y: f64) {
    let Some(managed) = state.window(id) else { return };
    let surface = managed.surface.clone();
    let scale = state.scale as f64;
    let geometry = crate::state::window_geometry(&surface);
    let origin: Point<f64, Logical> = (((id & 0xFFFF) as f64) * 20_000.0, 0.0).into();
    let local: Point<f64, Logical> = (x / scale + geometry.loc.x as f64, y / scale + geometry.loc.y as f64).into();
    let under = smithay::desktop::utils::under_from_surface_tree(
        &surface,
        local,
        (0, 0),
        smithay::desktop::WindowSurfaceType::ALL,
    );
    let focus = under.map(|(s, loc)| (s, origin + loc.to_f64()));
    let pointer = state.seat.get_pointer().unwrap();
    let time = state.now_ms();
    pointer.motion(
        state,
        focus,
        &MotionEvent { location: origin + local, serial: SERIAL_COUNTER.next_serial(), time },
    );
    pointer.frame(state);
}

pub fn focus(state: &mut State, id: u32) {
    let Some(managed) = state.window(id) else { return };
    if managed.is_popup() {
        return;
    }
    let surface = managed.surface.clone();
    if state.focused != Some(id) {
        if let Some(previous) = state.focused {
            dismiss_popups_of(state, previous);
        }
        state.focused = Some(id);
    } else {
        dismiss_popups_of(state, id);
    }
    if let Some(Role::X11(window)) = state.window(id).map(|w| &w.role) {
        let window = window.clone();
        crate::xwayland::activate(state, &window);
    }
    let keyboard = state.seat.get_keyboard().unwrap();
    keyboard.set_focus(state, Some(surface), SERIAL_COUNTER.next_serial());
}

fn key(state: &mut State, code: u32, pressed: bool) {
    let keyboard = state.seat.get_keyboard().unwrap();
    let time = state.now_ms();
    keyboard.input::<(), _>(
        state,
        Keycode::new(code),
        if pressed { KeyState::Pressed } else { KeyState::Released },
        SERIAL_COUNTER.next_serial(),
        time,
        |_, _, _| FilterResult::Forward,
    );
}

fn type_text(state: &mut State, text: &str) {
    if crate::text_input::is_active(state) {
        let mut rest = text;
        while !rest.is_empty() {
            let split = rest.find(char::is_control).unwrap_or(rest.len());
            if split > 0 {
                crate::text_input::commit(state, &rest[..split]);
            }
            let mut tail = rest[split..].chars();
            if let Some(control) = tail.next() {
                type_keys(state, &control.to_string());
            }
            rest = tail.as_str();
        }
        return;
    }
    type_keys(state, text);
}

fn type_keys(state: &mut State, text: &str) {
    for ch in text.chars() {
        let Some(stroke) = state.text.as_mut().and_then(|t| t.stroke(ch)) else { continue };
        let (code, shift) = match stroke {
            Stroke::Key { code, shift } => (code, shift),
            Stroke::Remap { code, keymap } => {
                let keyboard = state.seat.get_keyboard().unwrap();
                if let Err(error) = keyboard.set_keymap_from_string(state, keymap) {
                    tracing::warn!("keymap update failed: {error:?}");
                    continue;
                }
                (code, false)
            }
        };
        let shift_held = state.pressed.contains(&KEY_LEFTSHIFT_X11);
        let press_shift = shift && !shift_held;
        if press_shift {
            key(state, KEY_LEFTSHIFT_X11, true);
        }
        key(state, code, true);
        key(state, code, false);
        if press_shift {
            key(state, KEY_LEFTSHIFT_X11, false);
        }
    }
}
