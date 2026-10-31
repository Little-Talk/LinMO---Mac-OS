
use std::io::{self, Read, Write};
use std::os::fd::{FromRawFd, RawFd};
use std::os::unix::net::UnixStream;

const BACKLOG_LIMIT: usize = 32 * 1024 * 1024;

pub struct Link {
    stream: UnixStream,
    inbox: Vec<u8>,
    outbox: Vec<u8>,
}

impl Link {
    pub fn connect(port: u32) -> Option<Link> {
        let stream = if let Ok(path) = std::env::var("LINMO_AGENT_UNIX") {
            UnixStream::connect(path).ok()?
        } else {
            connect_vsock(2, port).ok()?
        };
        stream.set_nonblocking(true).ok()?;
        Some(Link { stream, inbox: Vec::new(), outbox: Vec::new() })
    }

    pub fn stream(&self) -> &UnixStream {
        &self.stream
    }

    pub fn backlogged(&self) -> bool {
        self.outbox.len() > BACKLOG_LIMIT
    }

    pub fn send(&mut self, kind: u16, payload: &[u8]) {
        self.outbox.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        self.outbox.extend_from_slice(&kind.to_le_bytes());
        self.outbox.extend_from_slice(payload);
        let _ = self.flush();
    }

    pub fn send_json(&mut self, kind: u16, value: &serde_json::Value) {
        let payload = serde_json::to_vec(value).unwrap_or_default();
        self.send(kind, &payload);
    }

    pub fn flush(&mut self) -> io::Result<()> {
        while !self.outbox.is_empty() {
            match self.stream.write(&self.outbox) {
                Ok(0) => return Err(io::ErrorKind::WriteZero.into()),
                Ok(n) => {
                    self.outbox.drain(..n);
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok(()),
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }

    pub fn receive(&mut self) -> io::Result<Vec<(u16, Vec<u8>)>> {
        let mut buffer = [0u8; 65536];
        loop {
            match self.stream.read(&mut buffer) {
                Ok(0) => return Err(io::ErrorKind::UnexpectedEof.into()),
                Ok(n) => self.inbox.extend_from_slice(&buffer[..n]),
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e),
            }
        }
        let mut messages = Vec::new();
        while self.inbox.len() >= 6 {
            let length = u32::from_le_bytes(self.inbox[0..4].try_into().unwrap()) as usize;
            let kind = u16::from_le_bytes(self.inbox[4..6].try_into().unwrap());
            if self.inbox.len() < 6 + length {
                break;
            }
            let payload = self.inbox[6..6 + length].to_vec();
            self.inbox.drain(..6 + length);
            messages.push((kind, payload));
        }
        Ok(messages)
    }
}

#[repr(C)]
struct SockaddrVm {
    svm_family: libc::sa_family_t,
    svm_reserved1: u16,
    svm_port: u32,
    svm_cid: u32,
    svm_zero: [u8; 4],
}

fn connect_vsock(cid: u32, port: u32) -> io::Result<UnixStream> {
    const AF_VSOCK: libc::c_int = 40;
    unsafe {
        let fd: RawFd = libc::socket(AF_VSOCK, libc::SOCK_STREAM | libc::SOCK_CLOEXEC, 0);
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        let address = SockaddrVm {
            svm_family: AF_VSOCK as libc::sa_family_t,
            svm_reserved1: 0,
            svm_port: port,
            svm_cid: cid,
            svm_zero: [0; 4],
        };
        let result = libc::connect(
            fd,
            &address as *const SockaddrVm as *const libc::sockaddr,
            std::mem::size_of::<SockaddrVm>() as libc::socklen_t,
        );
        if result < 0 {
            let error = io::Error::last_os_error();
            libc::close(fd);
            return Err(error);
        }
        Ok(UnixStream::from_raw_fd(fd))
    }
}
