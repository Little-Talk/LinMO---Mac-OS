
use smithay::delegate_xwayland_shell;
use smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;
use smithay::utils::{Logical, Rectangle};
use smithay::wayland::selection::SelectionTarget;
use smithay::wayland::xwayland_shell::{XWaylandShellHandler, XWaylandShellState};
use smithay::xwayland::xwm::{Reorder, ResizeEdge, WmWindowProperty, XwmId};
use smithay::xwayland::{X11Surface, X11Wm, XWayland, XWaylandEvent, XwmHandler};
use std::os::fd::OwnedFd;
use std::process::Stdio;

use crate::state::State;
use crate::window::Role;

pub fn start(state: &mut State) {
    if std::env::var("LINMO_XWAYLAND").is_ok_and(|v| v == "0") {
        return;
    }
    if std::fs::create_dir_all("/tmp/.X11-unix").is_ok() {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions("/tmp/.X11-unix", std::fs::Permissions::from_mode(0o1777));
    }
    let spawned = XWayland::spawn(
        &state.dh,
        None,
        std::iter::empty::<(String, String)>(),
        true,
        Stdio::null(),
        Stdio::null(),
        |_| (),
    );
    let (xwayland, client) = match spawned {
        Ok(spawned) => spawned,
        Err(error) => {
            tracing::info!("XWayland not available ({error}) — X11 apps open on the normal Linux screen");
            return;
        }
    };
    let result = state.loop_handle.insert_source(xwayland, move |event, _, state| match event {
        XWaylandEvent::Ready { x11_socket, display_number } => {
            match X11Wm::start_wm(state.loop_handle.clone(), x11_socket, client.clone()) {
                Ok(wm) => {
                    tracing::info!("XWayland ready on DISPLAY=:{display_number}");
                    state.xwm = Some(wm);
                    state.x_display = Some(display_number);
                }
                Err(error) => tracing::warn!("cannot start X11 window manager: {error}"),
            }
        }
        XWaylandEvent::Error => tracing::warn!("XWayland exited during startup"),
    });
    if let Err(error) = result {
        tracing::warn!("cannot watch XWayland: {error}");
    }
}

pub fn adopt_pending(state: &mut State) {
    let mut index = 0;
    while index < state.x11_pending.len() {
        let window = state.x11_pending[index].clone();
        if !window.alive() {
            state.x11_pending.remove(index);
            continue;
        }
        match window.wl_surface() {
            Some(surface) => {
                state.x11_pending.remove(index);
                if state.window_for_x11(&window).is_none() {
                    state.add_window(Role::X11(window), surface.clone());
                    crate::state::enter_output(&state.output.clone(), &surface, state.scale);
                }
            }
            None => index += 1,
        }
    }
}

fn forget(state: &mut State, window: &X11Surface) {
    state.x11_pending.retain(|w| w != window);
    if let Some(surface) = state.window_for_x11(window).map(|w| w.surface.clone()) {
        crate::window::forget_surface(state, &surface);
    }
}

fn mark_dirty(state: &mut State, window: &X11Surface) {
    if let Some(managed) = state.window_for_x11_mut(window) {
        managed.dirty = true;
    }
}

pub fn place(window: &X11Surface, size: smithay::utils::Size<i32, Logical>) {
    let _ = window.configure(Rectangle::new((0, 0).into(), size));
}

pub fn resize(window: &X11Surface, w: i32, h: i32) {
    place(window, (w.max(1), h.max(1)).into());
}

pub fn activate(state: &mut State, window: &X11Surface) {
    for managed in &state.windows {
        if let Role::X11(other) = &managed.role {
            if other != window && !other.is_override_redirect() {
                let _ = other.set_activated(false);
            }
        }
    }
    let _ = window.set_activated(true);
    if let Some(xwm) = state.xwm.as_mut() {
        let _ = xwm.raise_window(window);
    }
}

impl XWaylandShellHandler for State {
    fn xwayland_shell_state(&mut self) -> &mut XWaylandShellState {
        &mut self.xwayland_shell_state
    }

    fn surface_associated(&mut self, _xwm: XwmId, _wl_surface: WlSurface, _surface: X11Surface) {
        adopt_pending(self);
    }
}

impl XwmHandler for State {
    fn xwm_state(&mut self, _xwm: XwmId) -> &mut X11Wm {
        self.xwm.as_mut().expect("X11 window manager")
    }

    fn new_window(&mut self, _xwm: XwmId, _window: X11Surface) {}
    fn new_override_redirect_window(&mut self, _xwm: XwmId, _window: X11Surface) {}

    fn map_window_request(&mut self, _xwm: XwmId, window: X11Surface) {
        if window.set_mapped(true).is_err() {
            return;
        }
        place(&window, window.geometry().size);
        self.x11_pending.push(window);
        adopt_pending(self);
    }

    fn mapped_override_redirect_window(&mut self, _xwm: XwmId, window: X11Surface) {
        self.x11_pending.push(window);
        adopt_pending(self);
    }

    fn unmapped_window(&mut self, _xwm: XwmId, window: X11Surface) {
        forget(self, &window);
        if !window.is_override_redirect() {
            let _ = window.set_mapped(false);
        }
    }

    fn destroyed_window(&mut self, _xwm: XwmId, window: X11Surface) {
        forget(self, &window);
    }

    fn configure_request(
        &mut self,
        _xwm: XwmId,
        window: X11Surface,
        _x: Option<i32>,
        _y: Option<i32>,
        w: Option<u32>,
        h: Option<u32>,
        _reorder: Option<Reorder>,
    ) {
        let current = window.geometry().size;
        let size = (w.map(|w| w as i32).unwrap_or(current.w), h.map(|h| h as i32).unwrap_or(current.h));
        place(&window, size.into());
        mark_dirty(self, &window);
    }

    fn configure_notify(
        &mut self,
        _xwm: XwmId,
        window: X11Surface,
        _geometry: Rectangle<i32, Logical>,
        _above: Option<u32>,
    ) {
        mark_dirty(self, &window);
    }

    fn property_notify(&mut self, _xwm: XwmId, window: X11Surface, _property: WmWindowProperty) {
        mark_dirty(self, &window);
    }

    fn resize_request(&mut self, _xwm: XwmId, _window: X11Surface, _button: u32, _edge: ResizeEdge) {}
    fn move_request(&mut self, _xwm: XwmId, _window: X11Surface, _button: u32) {}

    fn allow_selection_access(&mut self, _xwm: XwmId, selection: SelectionTarget) -> bool {
        selection == SelectionTarget::Clipboard
    }

    fn send_selection(&mut self, _xwm: XwmId, selection: SelectionTarget, mime_type: String, fd: OwnedFd) {
        if selection == SelectionTarget::Clipboard {
            crate::clipboard::x11_paste(self, mime_type, fd);
        }
    }

    fn new_selection(&mut self, _xwm: XwmId, selection: SelectionTarget, mime_types: Vec<String>) {
        if selection == SelectionTarget::Clipboard {
            crate::clipboard::x11_copied(self, mime_types);
        }
    }

    fn cleared_selection(&mut self, _xwm: XwmId, selection: SelectionTarget) {
        if selection == SelectionTarget::Clipboard {
            crate::clipboard::x11_cleared(self);
        }
    }
}

delegate_xwayland_shell!(State);
