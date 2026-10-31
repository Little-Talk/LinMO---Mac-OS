
use smithay::input::keyboard::{xkb, Keycode};
use std::collections::HashMap;

pub const LAYOUT: &str = "us,th";
pub const OPTIONS: &str = "grp:alt_shift_toggle";
const POOL: usize = 40;

pub enum Stroke {
    Key { code: u32, shift: bool },
    Remap { code: u32, keymap: String },
}

pub struct TextKeymap {
    base: String,
    existing: HashMap<u32, (u32, bool)>,
    spare: Vec<(u32, String)>,
    assigned: Vec<(u32, u32)>,
}

impl TextKeymap {
    pub fn new() -> Option<Self> {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        let keymap = xkb::Keymap::new_from_names(
            &context, "evdev", "pc105", LAYOUT, "", Some(OPTIONS.to_string()), xkb::KEYMAP_COMPILE_NO_FLAGS,
        )?;
        let base = keymap.get_as_string(xkb::KEYMAP_FORMAT_TEXT_V1);

        let mut existing = HashMap::new();
        let mut spare = Vec::new();
        let (min, max) = (keymap.min_keycode().raw(), keymap.max_keycode().raw());
        for raw in min..=max {
            let code = Keycode::new(raw);
            let layouts = keymap.num_layouts_for_key(code);
            if layouts == 0 {
                if raw >= 140 {
                    if let Some(name) = keymap.key_get_name(code) {
                        spare.push((raw, name.to_string()));
                    }
                }
                continue;
            }
            for level in 0..keymap.num_levels_for_key(code, 0).min(2) {
                for sym in keymap.key_get_syms_by_level(code, 0, level) {
                    existing.entry(sym.raw()).or_insert((raw, level == 1));
                }
            }
        }
        spare.truncate(POOL);
        Some(TextKeymap { base, existing, spare, assigned: Vec::new() })
    }

    pub fn base_keymap(&self) -> &str {
        &self.base
    }

    pub fn stroke(&mut self, ch: char) -> Option<Stroke> {
        let sym = match ch {
            '\n' => xkb::keysyms::KEY_Return,
            '\t' => xkb::keysyms::KEY_Tab,
            _ => xkb::utf32_to_keysym(ch as u32).raw(),
        };
        if sym == 0 {
            return None;
        }
        if let Some(&(code, shift)) = self.existing.get(&sym) {
            return Some(Stroke::Key { code, shift });
        }
        if let Some(&(_, code)) = self.assigned.iter().find(|(s, _)| *s == sym) {
            return Some(Stroke::Key { code, shift: false });
        }
        if self.spare.is_empty() {
            return None;
        }
        let code = if self.assigned.len() < self.spare.len() {
            self.spare[self.assigned.len()].0
        } else {
            self.assigned.remove(0).1
        };
        self.assigned.push((sym, code));
        Some(Stroke::Remap { code, keymap: self.render() })
    }

    fn render(&self) -> String {
        let mut extra = String::new();
        for (sym, code) in &self.assigned {
            if let Some((_, name)) = self.spare.iter().find(|(c, _)| c == code) {
                let sym_name = xkb::keysym_get_name(xkb::Keysym::new(*sym));
                extra.push_str(&format!("\tkey <{name}> {{ [ {sym_name}, {sym_name} ] }};\n"));
            }
        }
        insert_into_symbols(&self.base, &extra)
    }
}

fn insert_into_symbols(keymap: &str, extra: &str) -> String {
    let Some(start) = keymap.find("xkb_symbols") else { return keymap.to_string() };
    let mut depth = 0i32;
    let bytes = keymap.as_bytes();
    let mut index = start;
    while index < bytes.len() {
        match bytes[index] {
            b'{' => depth += 1,
            b'}' => {
                depth -= 1;
                if depth == 0 {
                    let mut out = String::with_capacity(keymap.len() + extra.len());
                    out.push_str(&keymap[..index]);
                    out.push_str(extra);
                    out.push_str(&keymap[index..]);
                    return out;
                }
            }
            _ => {}
        }
        index += 1;
    }
    keymap.to_string()
}
