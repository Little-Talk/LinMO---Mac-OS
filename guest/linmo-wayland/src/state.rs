
use smithay::backend::renderer::pixman::PixmanRenderer;
use smithay::backend::renderer::utils::on_commit_buffer_handler;
use smithay::delegate_compositor;
use smithay::delegate_data_device;
use smithay::delegate_output;
use smithay::delegate_seat;
use smithay::delegate_shm;
use smithay::delegate_xdg_decoration;
use smithay::delegate_xdg_shell;
use smithay::desktop::{
    find_popup_root_surface, PopupKeyboardGrab, PopupKind, PopupManager, PopupPointerGrab, PopupUngrabStrategy,
};
use smithay::input::pointer::Focus;
use smithay::input::keyboard::XkbConfig;
use smithay::input::{Seat, SeatHandler, SeatState};
use smithay::output::{Mode as OutputMode, Output, PhysicalProperties, Scale, Subpixel};
use smithay::reexports::calloop::{LoopHandle, RegistrationToken};
use smithay::reexports::wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode as DecorationMode;
use smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel;
use smithay::reexports::wayland_server::backend::{ClientData, ClientId, DisconnectReason};
use smithay::reexports::wayland_server::protocol::wl_buffer::WlBuffer;
use smithay::reexports::wayland_server::protocol::wl_data_source::WlDataSource;
use smithay::reexports::wayland_server::protocol::wl_seat::WlSeat;
use smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;
use smithay::reexports::wayland_server::{Client, DisplayHandle};
use smithay::utils::IsAlive;
use smithay::utils::{Rectangle, Serial, Transform};
use smithay::wayland::buffer::BufferHandler;
use smithay::wayland::compositor::{
    get_parent, is_sync_subsurface, with_states, with_surface_tree_downward, CompositorClientState,
    CompositorHandler, CompositorState, SurfaceAttributes, TraversalAction,
};
use smithay::wayland::output::{OutputHandler, OutputManagerState};
use smithay::reexports::wayland_server::Resource;
use smithay::wayland::selection::data_device::{
    set_data_device_focus, ClientDndGrabHandler, DataDeviceHandler, DataDeviceState, ServerDndGrabHandler,
};
use smithay::wayland::selection::{SelectionHandler, SelectionSource, SelectionTarget};
use smithay::wayland::shell::xdg::decoration::{XdgDecorationHandler, XdgDecorationState};
use smithay::wayland::shell::xdg::{
    PopupSurface, PositionerState, SurfaceCachedState, ToplevelSurface, XdgShellHandler, XdgShellState,
    XdgToplevelSurfaceData,
};
use smithay::wayland::shm::{ShmHandler, ShmState};
use std::collections::HashMap;
use std::os::fd::OwnedFd;
use std::rc::Rc;
use std::time::Instant;
use smithay::wayland::xwayland_shell::XWaylandShellState;
use smithay::xwayland::{X11Surface, X11Wm};

use crate::icons::Icon;
use crate::link::Link;
use crate::text::{TextKeymap, LAYOUT, OPTIONS};
use crate::window::{Managed, Role};

pub const SCREEN_LOGICAL: (i32, i32) = (2560, 1600);

pub struct State {
    pub start: Instant,
    pub dh: DisplayHandle,
    pub loop_handle: LoopHandle<'static, State>,
    pub socket_name: String,

    pub compositor_state: CompositorState,
    pub xdg_shell_state: XdgShellState,
    pub shm_state: ShmState,
    pub output_manager_state: OutputManagerState,
    pub seat_state: SeatState<State>,
    pub data_device_state: DataDeviceState,
    pub decoration_state: XdgDecorationState,
    pub popups: PopupManager,

    pub seat: Seat<State>,
    pub output: Output,
    pub scale: i32,
    pub renderer: PixmanRenderer,

    pub windows: Vec<Managed>,
    pub next_id: u32,
    pub focused: Option<u32>,

    pub link: Option<Link>,
    pub link_token: Option<RegistrationToken>,
    pub streaming: bool,
    pub text: Option<TextKeymap>,
    pub pressed: Vec<u32>,
    pub icons: HashMap<String, Option<Rc<Icon>>>,
    pub clipboard_from_mac: Option<std::sync::Arc<crate::clipboard::MacClipboard>>,
    pub clipboard_serial: u64,
    pub drop_uris: Option<String>,
    pub client_drag: Option<WlDataSource>,
    pub text_inputs: Vec<crate::text_input::Instance>,

    pub xwayland_shell_state: XWaylandShellState,
    pub xwm: Option<X11Wm>,
    pub x_display: Option<u32>,
    pub x11_pending: Vec<X11Surface>,
}

impl State {
    pub fn new(dh: DisplayHandle, loop_handle: LoopHandle<'static, State>, socket_name: String) -> Self {
        let compositor_state = CompositorState::new::<Self>(&dh);
        let xdg_shell_state = XdgShellState::new::<Self>(&dh);
        let shm_state = ShmState::new::<Self>(&dh, vec![]);
        let output_manager_state = OutputManagerState::new_with_xdg_output::<Self>(&dh);
        let mut seat_state = SeatState::new();
        let data_device_state = DataDeviceState::new::<Self>(&dh);
        let decoration_state = XdgDecorationState::new::<Self>(&dh);
        crate::text_input::create_global(&dh);
        let dh_for_xwayland = dh.clone();

        let mut seat = seat_state.new_wl_seat(&dh, "seat0");
        let xkb = XkbConfig { layout: LAYOUT, options: Some(OPTIONS.to_string()), ..Default::default() };
        seat.add_keyboard(xkb, 400, 30).expect("keyboard");
        seat.add_pointer();

        let output = Output::new(
            "LINMO-1".into(),
            PhysicalProperties {
                size: (600, 380).into(),
                subpixel: Subpixel::Unknown,
                make: "LinMO".into(),
                model: "Mac".into(),
            },
        );
        let _global = output.create_global::<Self>(&dh);

        let mut state = State {
            start: Instant::now(),
            dh,
            loop_handle,
            socket_name,
            compositor_state,
            xdg_shell_state,
            shm_state,
            output_manager_state,
            seat_state,
            data_device_state,
            decoration_state,
            popups: PopupManager::default(),
            seat,
            output,
            scale: 1,
            renderer: PixmanRenderer::new().expect("pixman renderer"),
            windows: Vec::new(),
            next_id: 0x8000_0001,
            focused: None,
            link: None,
            link_token: None,
            streaming: false,
            text: TextKeymap::new(),
            pressed: Vec::new(),
            icons: HashMap::new(),
            clipboard_from_mac: None,
            clipboard_serial: 0,
            drop_uris: None,
            client_drag: None,
            text_inputs: Vec::new(),
            xwayland_shell_state: XWaylandShellState::new::<Self>(&dh_for_xwayland),
            xwm: None,
            x_display: None,
            x11_pending: Vec::new(),
        };
        state.set_scale(1);
        state
    }

    pub fn set_scale(&mut self, scale: i32) {
        let scale = scale.clamp(1, 2);
        self.scale = scale;
        let mode = OutputMode {
            size: (SCREEN_LOGICAL.0 * scale, SCREEN_LOGICAL.1 * scale).into(),
            refresh: 60_000,
        };
        self.output.change_current_state(Some(mode), Some(Transform::Normal), Some(Scale::Integer(scale)), Some((0, 0).into()));
        self.output.set_preferred(mode);
        for managed in &mut self.windows {
            managed.needs_full = true;
            managed.dirty = true;
            let surface = managed.surface.clone();
            enter_output(&self.output, &surface, scale);
        }
    }

    pub fn screen_pixels(&self) -> (i32, i32) {
        (SCREEN_LOGICAL.0 * self.scale, SCREEN_LOGICAL.1 * self.scale)
    }

    pub fn now_ms(&self) -> u32 {
        self.start.elapsed().as_millis() as u32
    }

    pub fn window(&self, id: u32) -> Option<&Managed> {
        self.windows.iter().find(|w| w.id == id)
    }

    pub fn window_mut(&mut self, id: u32) -> Option<&mut Managed> {
        self.windows.iter_mut().find(|w| w.id == id)
    }

    fn window_for_surface(&mut self, surface: &WlSurface) -> Option<&mut Managed> {
        self.windows.iter_mut().find(|w| &w.surface == surface)
    }

    pub fn window_for_x11(&self, window: &X11Surface) -> Option<&Managed> {
        self.windows.iter().find(|w| matches!(&w.role, Role::X11(x) if x == window))
    }

    pub fn window_for_x11_mut(&mut self, window: &X11Surface) -> Option<&mut Managed> {
        self.windows.iter_mut().find(|w| matches!(&w.role, Role::X11(x) if x == window))
    }

    pub fn add_window(&mut self, role: Role, surface: WlSurface) {
        let id = self.next_id;
        self.next_id += 1;
        self.windows.push(Managed::new(id, role, surface));
    }
}

pub fn enter_output(output: &Output, surface: &WlSurface, scale: i32) {
    with_surface_tree_downward(
        surface,
        (),
        |_, _, _| TraversalAction::DoChildren(()),
        |surface, states, _| {
            output.enter(surface);
            smithay::wayland::compositor::send_surface_state(surface, states, scale, Transform::Normal);
        },
        |_, _, _| true,
    );
}


#[derive(Default)]
pub struct ClientState {
    pub compositor_state: CompositorClientState,
}

impl ClientData for ClientState {
    fn initialized(&self, _client_id: ClientId) {}
    fn disconnected(&self, _client_id: ClientId, _reason: DisconnectReason) {}
}


impl CompositorHandler for State {
    fn compositor_state(&mut self) -> &mut CompositorState {
        &mut self.compositor_state
    }

    fn client_compositor_state<'a>(&self, client: &'a Client) -> &'a CompositorClientState {
        if let Some(xwayland) = client.get_data::<smithay::xwayland::XWaylandClientData>() {
            return &xwayland.compositor_state;
        }
        &client.get_data::<ClientState>().unwrap().compositor_state
    }

    fn commit(&mut self, surface: &WlSurface) {
        on_commit_buffer_handler::<Self>(surface);
        self.popups.commit(surface);

        if is_sync_subsurface(surface) {
            return;
        }
        let mut root = surface.clone();
        while let Some(parent) = get_parent(&root) {
            root = parent;
        }

        let scale = self.scale;
        let output = self.output.clone();
        if let Some(managed) = self.window_for_surface(&root) {
            managed.dirty = true;
            match &managed.role {
                Role::Toplevel(toplevel) => {
                    let initial = with_states(&root, |states| {
                        states
                            .data_map
                            .get::<XdgToplevelSurfaceData>()
                            .map(|data| data.lock().unwrap().initial_configure_sent)
                            .unwrap_or(true)
                    });
                    if !initial {
                        toplevel.send_configure();
                    }
                }
                Role::Popup(popup) => {
                    if !popup.is_initial_configure_sent() {
                        let _ = popup.send_configure();
                    }
                }
                Role::X11(_) => {}
            }
            enter_output(&output, &root, scale);
        }
    }
}

impl BufferHandler for State {
    fn buffer_destroyed(&mut self, _buffer: &WlBuffer) {}
}

impl ShmHandler for State {
    fn shm_state(&self) -> &ShmState {
        &self.shm_state
    }
}

impl OutputHandler for State {}


impl XdgShellHandler for State {
    fn xdg_shell_state(&mut self) -> &mut XdgShellState {
        &mut self.xdg_shell_state
    }

    fn new_toplevel(&mut self, surface: ToplevelSurface) {
        surface.with_pending_state(|state| {
            state.states.set(xdg_toplevel::State::Activated);
        });
        let wl = surface.wl_surface().clone();
        self.add_window(Role::Toplevel(surface), wl);
    }

    fn new_popup(&mut self, surface: PopupSurface, positioner: PositionerState) {
        surface.with_pending_state(|state| {
            state.geometry = positioner.get_geometry();
        });
        let wl = surface.wl_surface().clone();
        let _ = self.popups.track_popup(PopupKind::Xdg(surface.clone()));
        self.add_window(Role::Popup(surface), wl);
    }

    fn reposition_request(&mut self, surface: PopupSurface, positioner: PositionerState, token: u32) {
        surface.with_pending_state(|state| {
            state.geometry = positioner.get_geometry();
            state.positioner = positioner;
        });
        surface.send_repositioned(token);
        if let Some(managed) = self.window_for_surface(surface.wl_surface()) {
            managed.dirty = true;
        }
    }

    fn grab(&mut self, surface: PopupSurface, seat: WlSeat, serial: Serial) {
        let Some(seat) = Seat::<State>::from_resource(&seat) else { return };
        let kind = PopupKind::Xdg(surface);
        let Ok(root) = find_popup_root_surface(&kind) else { return };
        let Ok(mut grab) = self.popups.grab_popup(root, kind, &seat, serial) else { return };
        let fallback_serial = grab.previous_serial().unwrap_or_else(|| grab.serial());

        if let Some(keyboard) = seat.get_keyboard() {
            if keyboard.is_grabbed() && !(keyboard.has_grab(serial) || keyboard.has_grab(fallback_serial)) {
                grab.ungrab(PopupUngrabStrategy::All);
                return;
            }
            keyboard.set_focus(self, grab.current_grab(), serial);
            keyboard.set_grab(self, PopupKeyboardGrab::new(&grab), serial);
        }
        if let Some(pointer) = seat.get_pointer() {
            if pointer.is_grabbed() && !(pointer.has_grab(serial) || pointer.has_grab(fallback_serial)) {
                grab.ungrab(PopupUngrabStrategy::All);
                return;
            }
            pointer.set_grab(self, PopupPointerGrab::new(&grab), serial, Focus::Keep);
        }
    }

    fn title_changed(&mut self, surface: ToplevelSurface) {
        if let Some(managed) = self.window_for_surface(surface.wl_surface()) {
            managed.dirty = true;
        }
    }

    fn app_id_changed(&mut self, surface: ToplevelSurface) {
        self.title_changed(surface);
    }

    fn maximize_request(&mut self, surface: ToplevelSurface) {
        surface.with_pending_state(|state| {
            state.states.set(xdg_toplevel::State::Maximized);
            state.size = Some(SCREEN_LOGICAL.into());
        });
        surface.send_configure();
    }

    fn unmaximize_request(&mut self, surface: ToplevelSurface) {
        surface.with_pending_state(|state| {
            state.states.unset(xdg_toplevel::State::Maximized);
            state.size = None;
        });
        surface.send_configure();
    }

    fn toplevel_destroyed(&mut self, surface: ToplevelSurface) {
        crate::window::forget_surface(self, surface.wl_surface());
    }

    fn popup_destroyed(&mut self, surface: PopupSurface) {
        crate::window::forget_surface(self, surface.wl_surface());
    }
}


impl XdgDecorationHandler for State {
    fn new_decoration(&mut self, toplevel: ToplevelSurface) {
        toplevel.with_pending_state(|state| state.decoration_mode = Some(DecorationMode::ServerSide));
    }

    fn request_mode(&mut self, toplevel: ToplevelSurface, _mode: DecorationMode) {
        toplevel.with_pending_state(|state| state.decoration_mode = Some(DecorationMode::ServerSide));
        if toplevel.is_initial_configure_sent() {
            toplevel.send_pending_configure();
        }
    }

    fn unset_mode(&mut self, toplevel: ToplevelSurface) {
        self.request_mode(toplevel, DecorationMode::ServerSide);
    }
}


impl SeatHandler for State {
    type KeyboardFocus = WlSurface;
    type PointerFocus = WlSurface;
    type TouchFocus = WlSurface;

    fn seat_state(&mut self) -> &mut SeatState<Self> {
        &mut self.seat_state
    }

    fn focus_changed(&mut self, seat: &Seat<Self>, focused: Option<&WlSurface>) {
        let client = focused.and_then(|surface| self.dh.get_client(surface.id()).ok());
        set_data_device_focus(&self.dh, seat, client);
        crate::text_input::focus_changed(self, focused);
    }
}

impl SelectionHandler for State {
    type SelectionUserData = crate::clipboard::Owner;

    fn new_selection(&mut self, ty: SelectionTarget, source: Option<SelectionSource>, _seat: Seat<Self>) {
        if let (SelectionTarget::Clipboard, Some(source)) = (ty, source) {
            crate::clipboard::client_selection_changed(self, source);
        }
    }

    fn send_selection(
        &mut self,
        ty: SelectionTarget,
        mime_type: String,
        fd: OwnedFd,
        _seat: Seat<Self>,
        user_data: &crate::clipboard::Owner,
    ) {
        if ty == SelectionTarget::Clipboard {
            crate::clipboard::send_owned(self, &user_data.clone(), mime_type, fd);
        }
    }
}

impl DataDeviceHandler for State {
    fn data_device_state(&self) -> &DataDeviceState {
        &self.data_device_state
    }
}

impl ClientDndGrabHandler for State {
    fn started(&mut self, source: Option<WlDataSource>, _icon: Option<WlSurface>, _seat: Seat<Self>) {
        self.client_drag = source;
    }

    fn dropped(&mut self, _target: Option<WlSurface>, _validated: bool, _seat: Seat<Self>) {
        self.client_drag = None;
    }
}

impl ServerDndGrabHandler for State {
    fn send(&mut self, mime_type: String, fd: OwnedFd, _seat: Seat<Self>) {
        crate::dnd::send(self, &mime_type, fd);
    }
}


pub fn window_geometry(surface: &WlSurface) -> Rectangle<i32, smithay::utils::Logical> {
    let geometry = with_states(surface, |states| states.cached_state.get::<SurfaceCachedState>().current().geometry);
    geometry.unwrap_or_else(|| smithay::desktop::utils::bbox_from_surface_tree(surface, (0, 0)))
}

pub fn toplevel_title(toplevel: &ToplevelSurface) -> (String, String) {
    with_states(toplevel.wl_surface(), |states| {
        states
            .data_map
            .get::<XdgToplevelSurfaceData>()
            .map(|data| {
                let data = data.lock().unwrap();
                (data.title.clone().unwrap_or_default(), data.app_id.clone().unwrap_or_default())
            })
            .unwrap_or_default()
    })
}

pub fn has_buffer(surface: &WlSurface) -> bool {
    smithay::backend::renderer::utils::with_renderer_surface_state(surface, |state| state.buffer().is_some())
        .unwrap_or(false)
}

pub fn frame_callbacks_pending(surface: &WlSurface) -> bool {
    with_states(surface, |states| !states.cached_state.get::<SurfaceAttributes>().current().frame_callbacks.is_empty())
}

delegate_compositor!(State);
delegate_shm!(State);
delegate_xdg_shell!(State);
delegate_xdg_decoration!(State);
delegate_seat!(State);
delegate_data_device!(State);
delegate_output!(State);

#[allow(unused)]
fn _assert_alive(surface: &WlSurface) -> bool {
    surface.alive()
}
