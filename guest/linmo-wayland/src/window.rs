
use serde_json::json;
use smithay::backend::allocator::Fourcc;
use smithay::backend::renderer::damage::OutputDamageTracker;
use smithay::backend::renderer::element::surface::{render_elements_from_surface_tree, WaylandSurfaceRenderElement};
use smithay::backend::renderer::element::Kind;
use smithay::backend::renderer::pixman::PixmanRenderer;
use smithay::backend::renderer::{Bind, Offscreen};
use smithay::desktop::{get_popup_toplevel_coords, PopupKind, PopupManager};
use smithay::reexports::pixman;
use smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;
use smithay::utils::IsAlive;
use smithay::utils::{Physical, Point, Rectangle, Size, Transform};
use std::rc::Rc;
use std::time::Duration;

use crate::protocol::{MSG_FRAME, MSG_FRAME_RECT, MSG_ICON, MSG_WINDOW, MSG_WINDOW_CLOSED};
use crate::state::{has_buffer, toplevel_title, window_geometry, State};

const FULL_FRAME_RATIO: f64 = 0.6;

pub enum Role {
    Toplevel(smithay::wayland::shell::xdg::ToplevelSurface),
    Popup(smithay::wayland::shell::xdg::PopupSurface),
    X11(smithay::xwayland::X11Surface),
}

pub struct Managed {
    pub id: u32,
    pub role: Role,
    pub surface: WlSurface,
    image: Option<pixman::Image<'static, 'static>>,
    tracker: Option<OutputDamageTracker>,
    pub dirty: bool,
    pub needs_full: bool,
    sent_info: Option<serde_json::Value>,
    sent_icon: Option<String>,
}

impl Managed {
    pub fn new(id: u32, role: Role, surface: WlSurface) -> Self {
        Managed { id, role, surface, image: None, tracker: None, dirty: true, needs_full: true, sent_info: None, sent_icon: None }
    }

    pub fn is_popup(&self) -> bool {
        match &self.role {
            Role::Popup(_) => true,
            Role::X11(window) => window.is_override_redirect(),
            Role::Toplevel(_) => false,
        }
    }
}

fn popup_root(state: &State, popup: &smithay::wayland::shell::xdg::PopupSurface) -> Option<u32> {
    let root = smithay::desktop::find_popup_root_surface(&PopupKind::Xdg(popup.clone())).ok()?;
    state.windows.iter().find(|w| w.surface == root).map(|w| w.id)
}

fn x11_parent(state: &State, popup: &smithay::xwayland::X11Surface) -> Option<u32> {
    let focused = state.focused.and_then(|id| state.window(id));
    let is_x11 = |m: &&Managed| matches!(&m.role, Role::X11(w) if w != popup && !w.is_override_redirect());
    focused.filter(is_x11).or_else(|| state.windows.iter().rev().find(is_x11)).map(|m| m.id)
}

fn info(state: &State, managed: &Managed) -> Option<serde_json::Value> {
    let scale = state.scale;
    let geometry = window_geometry(&managed.surface);
    if geometry.size.w <= 0 || geometry.size.h <= 0 {
        return None;
    }
    let (w, h) = (geometry.size.w * scale, geometry.size.h * scale);
    match &managed.role {
        Role::Toplevel(toplevel) => {
            let (title, app) = toplevel_title(toplevel);
            let parent = toplevel
                .parent()
                .and_then(|p| state.windows.iter().find(|w| w.surface == p))
                .map(|w| w.id);
            let (x, y) = match parent.and_then(|id| state.window(id)) {
                Some(parent_window) => {
                    let pg = window_geometry(&parent_window.surface);
                    ((pg.size.w * scale - w) / 2, (pg.size.h * scale - h) / 2)
                }
                None => (0, 0),
            };
            Some(json!({
                "id": managed.id, "kind": "normal", "title": title, "app": app,
                "x": x, "y": y, "w": w, "h": h, "parent": parent.unwrap_or(0),
            }))
        }
        Role::Popup(popup) => {
            let kind = PopupKind::Xdg(popup.clone());
            let position = popup.with_pending_state(|state| state.geometry.loc);
            let location = get_popup_toplevel_coords(&kind) + position;
            Some(json!({
                "id": managed.id, "kind": "popup", "title": "", "app": "",
                "x": location.x * scale, "y": location.y * scale, "w": w, "h": h,
                "parent": popup_root(state, popup).unwrap_or(0),
            }))
        }
        Role::X11(window) => {
            let location = window.geometry().loc;
            if window.is_override_redirect() {
                let parent = x11_parent(state, window);
                return Some(json!({
                    "id": managed.id, "kind": "popup", "title": "", "app": "",
                    "x": location.x * scale, "y": location.y * scale, "w": w, "h": h,
                    "parent": parent.unwrap_or(0),
                }));
            }
            let parent = window
                .is_transient_for()
                .and_then(|x| state.windows.iter().find(|m| matches!(&m.role, Role::X11(o) if o.window_id() == x)))
                .map(|m| m.id);
            let (x, y) = match parent.and_then(|id| state.window(id)) {
                Some(parent_window) => {
                    let pg = window_geometry(&parent_window.surface);
                    ((pg.size.w * scale - w) / 2, (pg.size.h * scale - h) / 2)
                }
                None => (0, 0),
            };
            Some(json!({
                "id": managed.id, "kind": "normal", "title": window.title(), "app": window.class(),
                "x": x, "y": y, "w": w, "h": h, "parent": parent.unwrap_or(0),
            }))
        }
    }
}

pub fn tick(state: &mut State) {
    let time = Duration::from_millis(state.now_ms() as u64);
    crate::xwayland::adopt_pending(state);

    for index in 0..state.windows.len() {
        let surface = state.windows[index].surface.clone();
        if !surface.alive() || !has_buffer(&surface) {
            continue;
        }

        if state.windows[index].dirty {
            if let Some(value) = info(state, &state.windows[index]) {
                if state.windows[index].sent_info.as_ref() != Some(&value) {
                    state.windows[index].sent_info = Some(value.clone());
                    if let Some(link) = state.link.as_mut() {
                        link.send_json(MSG_WINDOW, &value);
                    }
                    send_icon(state, index);
                }
            }
        }

        if state.streaming && state.windows[index].dirty {
            let backlogged = state.link.as_ref().map(|l| l.backlogged()).unwrap_or(true);
            if !backlogged {
                render(state, index);
            }
        }

        smithay::desktop::utils::send_frames_surface_tree(
            &surface,
            &state.output,
            time,
            Some(Duration::from_millis(16)),
            |_, _| None,
        );
    }

    state.popups.cleanup();
    if let Some(link) = state.link.as_mut() {
        let _ = link.flush();
    }
}

fn send_icon(state: &mut State, index: usize) {
    let app_id = match &state.windows[index].role {
        Role::Toplevel(toplevel) => toplevel_title(toplevel).1,
        Role::X11(window) if !window.is_override_redirect() => window.class(),
        _ => return,
    };
    if app_id.is_empty() || state.windows[index].sent_icon.as_deref() == Some(app_id.as_str()) || state.link.is_none() {
        return;
    }
    state.windows[index].sent_icon = Some(app_id.clone());
    let icon = state.icons.entry(app_id.clone()).or_insert_with(|| crate::icons::Icon::load(&app_id).map(Rc::new)).clone();
    if let (Some(icon), Some(link)) = (icon, state.link.as_mut()) {
        link.send(MSG_ICON, &icon.message(state.windows[index].id));
    }
}

fn render(state: &mut State, index: usize) {
    let scale = state.scale;
    let id = state.windows[index].id;
    let surface = state.windows[index].surface.clone();
    let geometry = window_geometry(&surface);
    let size: Size<i32, Physical> = (geometry.size.w * scale, geometry.size.h * scale).into();
    if size.w <= 0 || size.h <= 0 {
        return;
    }

    let renderer: &mut PixmanRenderer = &mut state.renderer;
    let managed = &mut state.windows[index];
    let resized = managed
        .image
        .as_ref()
        .map(|image| image.width() as i32 != size.w || image.height() as i32 != size.h)
        .unwrap_or(true);
    if resized {
        match renderer.create_buffer(Fourcc::Argb8888, (size.w, size.h).into()) {
            Ok(image) => managed.image = Some(image),
            Err(_) => return,
        }
        managed.tracker = Some(OutputDamageTracker::new(size, scale as f64, Transform::Normal));
        managed.needs_full = true;
    }

    let location: Point<i32, Physical> = (-geometry.loc.x * scale, -geometry.loc.y * scale).into();
    let elements: Vec<WaylandSurfaceRenderElement<PixmanRenderer>> =
        render_elements_from_surface_tree(renderer, &surface, location, scale as f64, 1.0, Kind::Unspecified);

    let full = managed.needs_full;
    let age = if full { 0 } else { 1 };
    let damage: Vec<Rectangle<i32, Physical>> = {
        let (Some(image), Some(tracker)) = (managed.image.as_mut(), managed.tracker.as_mut()) else { return };
        let Ok(mut framebuffer) = renderer.bind(image) else { return };
        match tracker.render_output(renderer, &mut framebuffer, age, &elements, [0.0, 0.0, 0.0, 0.0]) {
            Ok(result) => {
                let _ = result.sync.wait();
                result.damage.cloned().unwrap_or_default()
            }
            Err(_) => return,
        }
    };
    managed.dirty = false;
    if !full && damage.is_empty() {
        return;
    }

    let bounds = damage.iter().fold(None::<Rectangle<i32, Physical>>, |acc, rect| {
        Some(match acc {
            Some(a) => a.merge(*rect),
            None => *rect,
        })
    });
    let whole = Rectangle::<i32, Physical>::from_size(size);
    let mut rect = bounds.and_then(|b| b.intersection(whole)).unwrap_or(whole);
    let area = (rect.size.w as f64) * (rect.size.h as f64);
    let send_full = full || area >= FULL_FRAME_RATIO * (size.w as f64) * (size.h as f64);
    if send_full {
        rect = whole;
    }

    let Some(image) = managed.image.as_ref() else { return };
    let stride = image.stride();
    let pixels = unsafe { std::slice::from_raw_parts(image.data() as *const u8, stride * size.h as usize) };
    let row_bytes = rect.size.w as usize * 4;
    let mut payload = Vec::with_capacity(32 + row_bytes * rect.size.h as usize);
    if send_full {
        for value in [id, size.w as u32, size.h as u32, row_bytes as u32] {
            payload.extend_from_slice(&value.to_le_bytes());
        }
    } else {
        for value in [
            id, size.w as u32, size.h as u32,
            rect.loc.x as u32, rect.loc.y as u32, rect.size.w as u32, rect.size.h as u32, row_bytes as u32,
        ] {
            payload.extend_from_slice(&value.to_le_bytes());
        }
    }
    for row in rect.loc.y..rect.loc.y + rect.size.h {
        let start = row as usize * stride + rect.loc.x as usize * 4;
        payload.extend_from_slice(&pixels[start..start + row_bytes]);
    }
    managed.needs_full = false;
    if let Some(link) = state.link.as_mut() {
        link.send(if send_full { MSG_FRAME } else { MSG_FRAME_RECT }, &payload);
    }
}

pub fn forget_surface(state: &mut State, surface: &WlSurface) {
    if let Some(position) = state.windows.iter().position(|w| &w.surface == surface) {
        let managed = state.windows.remove(position);
        if managed.sent_info.is_some() {
            if let Some(link) = state.link.as_mut() {
                link.send_json(MSG_WINDOW_CLOSED, &json!({ "id": managed.id }));
            }
        }
        if state.focused == Some(managed.id) {
            state.focused = None;
        }
    }
}

pub fn dismiss_popups_of(state: &mut State, toplevel_id: u32) {
    let Some(surface) = state.window(toplevel_id).map(|w| w.surface.clone()) else { return };
    let popups: Vec<PopupKind> = PopupManager::popups_for_surface(&surface).map(|(p, _)| p).collect();
    for popup in popups.iter().rev() {
        let _ = PopupManager::dismiss_popup(&surface, popup);
    }
}

pub fn resend_all(state: &mut State) {
    for managed in &mut state.windows {
        managed.sent_info = None;
        managed.sent_icon = None;
        managed.dirty = true;
        managed.needs_full = true;
    }
}
