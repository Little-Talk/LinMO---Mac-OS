#!/usr/bin/env python3
import os
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

GLib.set_prgname(os.environ.get("LINMO_TEST_APP_ID", "linmotest"))


def say(*parts):
    print(*parts, flush=True)


window = Gtk.Window(title="LinMO test")
window.set_default_size(320, 220)
layout = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
entry = Gtk.Entry()
entry.connect("preedit-changed", lambda _e, text: say("PREEDIT", text))
entry.connect("activate", lambda _e: say("ACTIVATE", entry.get_text()))
box = Gtk.EventBox()
box.add(Gtk.Label(label="LinMO test"))
layout.pack_start(box, True, True, 0)
layout.pack_end(entry, False, False, 0)
window.add(layout)
clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)

menu = Gtk.Menu()
for name in ("first", "second"):
    item = Gtk.MenuItem(label=name)
    item.connect("activate", lambda _item, n=name: say("MENU", n))
    menu.append(item)
menu.show_all()


def on_press(_widget, event):
    if event.button == 3:
        menu.popup_at_pointer(event)
    return False


box.connect("button-press-event", on_press)

box.drag_dest_set(Gtk.DestDefaults.ALL, [], Gdk.DragAction.COPY)
box.drag_dest_add_uri_targets()
box.connect("drag-data-received", lambda _w, _c, _x, _y, data, _i, _t: say("DROP", " ".join(data.get_uris())))


drag_file = []
box.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, [], Gdk.DragAction.COPY)
box.drag_source_add_uri_targets()
box.connect("drag-data-get", lambda _w, _c, data, _i, _t: data.set_uris(drag_file))
box.connect("drag-begin", lambda *_: say("DRAG_BEGIN"))
box.connect("drag-end", lambda *_: say("DRAG_END"))


def on_stdin(source, _condition):
    line = source.readline()
    if not line:
        Gtk.main_quit()
        return False
    command, _, argument = line.rstrip("\n").partition(" ")
    if command == "copy":
        clipboard.set_text(argument, -1)
    elif command == "drag":
        drag_file[:] = [GLib.filename_to_uri(argument)]
    elif command == "paste":
        clipboard.request_text(lambda _c, text: say("PASTE", text or ""))
    elif command == "copyimage":
        clipboard.set_image(GdkPixbuf.Pixbuf.new_from_file(argument))
    elif command == "pasteimage":
        def got_image(_c, pixbuf):
            if pixbuf is None:
                say("PASTEIMAGE", "none")
            else:
                say("PASTEIMAGE", pixbuf.get_width(), pixbuf.get_height(), pixbuf.get_pixels()[:3].hex())
        clipboard.request_image(got_image)
    return True


GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, on_stdin)
window.connect("map-event", lambda *_: say("READY"))
window.connect("destroy", Gtk.main_quit)
window.show_all()
Gtk.main()
