
use serde_json::json;
use smithay::reexports::wayland_protocols::wp::text_input::zv3::server::{
    zwp_text_input_manager_v3::{self, ZwpTextInputManagerV3},
    zwp_text_input_v3::{self, ZwpTextInputV3},
};
use smithay::reexports::wayland_server::backend::ClientId;
use smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;
use smithay::reexports::wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};
use smithay::utils::{Logical, Rectangle};

use crate::protocol::MSG_TEXT_INPUT;
use crate::state::{window_geometry, State};

pub struct Instance {
    resource: ZwpTextInputV3,
    entered: Option<WlSurface>,
    pending_enable: Option<bool>,
    pending_cursor: Option<Rectangle<i32, Logical>>,
    enabled: bool,
    cursor: Option<Rectangle<i32, Logical>>,
    commits: u32,
    reported: Option<serde_json::Value>,
}

pub fn create_global(dh: &DisplayHandle) {
    dh.create_global::<State, ZwpTextInputManagerV3, ()>(1, ());
}

impl GlobalDispatch<ZwpTextInputManagerV3, ()> for State {
    fn bind(
        _state: &mut Self,
        _dh: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpTextInputManagerV3>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZwpTextInputManagerV3, ()> for State {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpTextInputManagerV3,
        request: zwp_text_input_manager_v3::Request,
        _data: &(),
        _dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        if let zwp_text_input_manager_v3::Request::GetTextInput { id, .. } = request {
            let resource = data_init.init(id, ());
            let mut instance = Instance {
                resource,
                entered: None,
                pending_enable: None,
                pending_cursor: None,
                enabled: false,
                cursor: None,
                commits: 0,
                reported: None,
            };
            if let Some(focus) = keyboard_focus(state) {
                if focus.id().same_client_as(&instance.resource.id()) {
                    instance.resource.enter(&focus);
                    instance.entered = Some(focus);
                }
            }
            state.text_inputs.push(instance);
        }
    }
}

impl Dispatch<ZwpTextInputV3, ()> for State {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpTextInputV3,
        request: zwp_text_input_v3::Request,
        _data: &(),
        _dh: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let Some(index) = state.text_inputs.iter().position(|i| &i.resource == resource) else { return };
        let instance = &mut state.text_inputs[index];
        match request {
            zwp_text_input_v3::Request::Enable => {
                instance.pending_enable = Some(true);
                instance.pending_cursor = None;
            }
            zwp_text_input_v3::Request::Disable => instance.pending_enable = Some(false),
            zwp_text_input_v3::Request::SetCursorRectangle { x, y, width, height } => {
                instance.pending_cursor = Some(Rectangle::new((x, y).into(), (width, height).into()));
            }
            zwp_text_input_v3::Request::Commit => {
                instance.commits = instance.commits.wrapping_add(1);
                if let Some(enable) = instance.pending_enable.take() {
                    instance.enabled = enable && instance.entered.is_some();
                    if !enable {
                        instance.cursor = None;
                    }
                }
                if let Some(cursor) = instance.pending_cursor.take() {
                    instance.cursor = Some(cursor);
                }
                report(state, index);
            }
            _ => {}
        }
    }

    fn destroyed(state: &mut Self, _client: ClientId, resource: &ZwpTextInputV3, _data: &()) {
        if let Some(index) = state.text_inputs.iter().position(|i| &i.resource == resource) {
            let was_enabled = state.text_inputs[index].enabled;
            state.text_inputs[index].enabled = false;
            if was_enabled {
                report(state, index);
            }
            state.text_inputs.remove(index);
        }
    }
}

fn keyboard_focus(state: &State) -> Option<WlSurface> {
    state.seat.get_keyboard().and_then(|k| k.current_focus())
}

pub fn focus_changed(state: &mut State, focused: Option<&WlSurface>) {
    for index in 0..state.text_inputs.len() {
        let instance = &mut state.text_inputs[index];
        if instance.entered.as_ref() == focused {
            continue;
        }
        if let Some(previous) = instance.entered.take() {
            if previous.is_alive() {
                instance.resource.leave(&previous);
            }
            if instance.enabled {
                instance.enabled = false;
                report_for_surface(state, index, &previous);
            }
        }
        let instance = &mut state.text_inputs[index];
        if let Some(surface) = focused {
            if surface.id().same_client_as(&instance.resource.id()) {
                instance.resource.enter(surface);
                instance.entered = Some(surface.clone());
            }
        }
    }
}

fn active(state: &mut State) -> Option<&mut Instance> {
    let focus = keyboard_focus(state)?;
    state.text_inputs.iter_mut().find(|i| i.enabled && i.entered.as_ref() == Some(&focus))
}

pub fn is_active(state: &mut State) -> bool {
    active(state).is_some()
}

pub fn preedit(state: &mut State, text: &str, cursor: i64) -> bool {
    let Some(instance) = active(state) else { return false };
    if text.is_empty() {
        instance.resource.preedit_string(None, 0, 0);
    } else {
        let position = if cursor < 0 { -1 } else { utf16_to_byte_offset(text, cursor as usize) as i32 };
        instance.resource.preedit_string(Some(text.to_string()), position, position);
    }
    instance.resource.done(instance.commits);
    true
}

pub fn commit(state: &mut State, text: &str) -> bool {
    let Some(instance) = active(state) else { return false };
    instance.resource.preedit_string(None, 0, 0);
    instance.resource.commit_string(Some(text.to_string()));
    instance.resource.done(instance.commits);
    true
}

fn utf16_to_byte_offset(text: &str, units: usize) -> usize {
    let mut counted = 0;
    for (offset, ch) in text.char_indices() {
        if counted >= units {
            return offset;
        }
        counted += ch.len_utf16();
    }
    text.len()
}

fn report(state: &mut State, index: usize) {
    if let Some(surface) = state.text_inputs[index].entered.clone() {
        report_for_surface(state, index, &surface);
    }
}

fn report_for_surface(state: &mut State, index: usize, surface: &WlSurface) {
    let Some(window) = state.windows.iter().find(|w| &w.surface == surface) else { return };
    let id = window.id;
    let scale = state.scale;
    let geometry = window_geometry(surface);
    let instance = &state.text_inputs[index];
    let cursor = instance.cursor.unwrap_or_default();
    let value = json!({
        "id": id,
        "enabled": instance.enabled,
        "x": (cursor.loc.x - geometry.loc.x) * scale,
        "y": (cursor.loc.y - geometry.loc.y) * scale,
        "w": cursor.size.w * scale,
        "h": cursor.size.h * scale,
    });
    if instance.reported.as_ref() == Some(&value) {
        return;
    }
    state.text_inputs[index].reported = Some(value.clone());
    if let Some(link) = state.link.as_mut() {
        link.send_json(MSG_TEXT_INPUT, &value);
    }
}

pub fn resend_all(state: &mut State) {
    for index in 0..state.text_inputs.len() {
        state.text_inputs[index].reported = None;
        report(state, index);
    }
}
