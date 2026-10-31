
mod apps;
mod clipboard;
mod dnd;
mod icons;
mod link;
mod protocol;
mod state;
mod text;
mod text_input;
mod window;
mod xwayland;

use smithay::reexports::calloop::generic::Generic;
use smithay::reexports::calloop::timer::{TimeoutAction, Timer};
use smithay::reexports::calloop::{EventLoop, Interest, Mode, PostAction};
use smithay::reexports::wayland_server::Display;
use smithay::wayland::socket::ListeningSocketSource;
use std::sync::Arc;
use std::time::Duration;

use crate::link::Link;
use crate::state::{ClientState, State};

const DEFAULT_PORT: u32 = 5202;
const FRAME_INTERVAL: Duration = Duration::from_millis(16);
const RECONNECT_INTERVAL: Duration = Duration::from_secs(2);

fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let port: u32 = std::env::var("LINMO_WAYLAND_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(DEFAULT_PORT);
    let socket_name = std::env::var("LINMO_WAYLAND_DISPLAY").unwrap_or_else(|_| "linmo-0".into());

    let mut event_loop: EventLoop<State> = EventLoop::try_new()?;
    let display: Display<State> = Display::new()?;
    let dh = display.handle();

    let listening = ListeningSocketSource::with_name(&socket_name)?;
    event_loop.handle().insert_source(listening, |stream, _, state| {
        if let Err(error) = state.dh.insert_client(stream, Arc::new(ClientState::default())) {
            tracing::warn!("client rejected: {error}");
        }
    })?;
    event_loop.handle().insert_source(
        Generic::new(display, Interest::READ, Mode::Level),
        |_, display, state| {
            unsafe {
                display.get_mut().dispatch_clients(state).unwrap();
            }
            Ok(PostAction::Continue)
        },
    )?;

    let mut state = State::new(dh, event_loop.handle(), socket_name.clone());
    xwayland::start(&mut state);
    tracing::info!("WAYLAND_DISPLAY={socket_name}, connecting to LinMO on port {port}");

    event_loop.handle().insert_source(Timer::from_duration(FRAME_INTERVAL), |_, _, state| {
        window::tick(state);
        TimeoutAction::ToDuration(FRAME_INTERVAL)
    })?;

    event_loop.handle().insert_source(Timer::immediate(), move |_, _, state| {
        if state.link.is_none() {
            try_connect(state, port);
        }
        TimeoutAction::ToDuration(RECONNECT_INTERVAL)
    })?;

    event_loop.run(None, &mut state, |state| {
        let _ = state.dh.flush_clients();
    })?;
    Ok(())
}

fn try_connect(state: &mut State, port: u32) {
    let Some(link) = Link::connect(port) else { return };
    let Ok(stream) = link.stream().try_clone() else { return };
    let token = state.loop_handle.insert_source(Generic::new(stream, Interest::READ, Mode::Level), |_, _, state| {
        let result = match state.link.as_mut() {
            Some(link) => link.receive(),
            None => return Ok(PostAction::Remove),
        };
        match result {
            Ok(messages) => {
                for (kind, payload) in messages {
                    protocol::handle(state, kind, &payload);
                }
                Ok(PostAction::Continue)
            }
            Err(error) => {
                tracing::info!("disconnected from LinMO: {error}");
                state.link = None;
                state.link_token = None;
                state.streaming = false;
                Ok(PostAction::Remove)
            }
        }
    });
    match token {
        Ok(token) => {
            tracing::info!("connected to LinMO");
            state.link = Some(link);
            state.link_token = Some(token);
            protocol::hello(state);
        }
        Err(error) => tracing::warn!("cannot watch connection: {error}"),
    }
}
