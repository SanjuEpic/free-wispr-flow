import tkinter as tk
from tkinter import ttk
from datetime import datetime

from ..logger import setup_logger
from .. import history

log = setup_logger("uttr-win.history-ui")


class HistoryWindow:
    """A Toplevel history window. All methods must run on the main (tkinter)
    thread — the window is a child of the app's persistent hidden root."""

    def __init__(self, parent: tk.Misc):
        self._parent = parent
        self._win: tk.Toplevel | None = None

    def open(self) -> None:
        if self._win is not None and self._win.winfo_exists():
            self._refresh()
            self._win.lift()
            self._win.focus_force()
            return
        self._win = tk.Toplevel(self._parent)
        self._win.title("uttr-win — Transcription History")
        self._win.resizable(False, False)
        self._win.attributes("-topmost", True)
        self._win.protocol("WM_DELETE_WINDOW", self._close)
        self._build_ui()
        self._center_window()

    def _refresh(self) -> None:
        """Rebuild the contents so re-opening shows the latest transcriptions."""
        for child in self._win.winfo_children():
            child.destroy()
        self._build_ui()
        self._center_window()

    def _center_window(self) -> None:
        self._win.update_idletasks()
        w = self._win.winfo_width()
        h = self._win.winfo_height()
        x = (self._win.winfo_screenwidth() - w) // 2
        y = (self._win.winfo_screenheight() - h) // 2
        self._win.geometry(f"+{x}+{y}")

    def _build_ui(self) -> None:
        root = self._win
        root.configure(padx=20, pady=15)

        title = ttk.Label(root, text="Transcription History", font=("Segoe UI", 14, "bold"))
        title.pack(anchor="w", pady=(0, 10))

        entries = history.get_all()
        entries.reverse()

        if not entries:
            ttk.Label(root, text="No transcriptions yet. Press Ctrl+Space to start.",
                      foreground="gray").pack(anchor="w", pady=20)
        else:
            container = ttk.Frame(root)
            container.pack(fill="both", expand=True)

            canvas = tk.Canvas(container, width=480, height=350, highlightthickness=0)
            scrollbar = ttk.Scrollbar(container, orient="vertical", command=canvas.yview)
            scroll_frame = ttk.Frame(canvas)

            scroll_frame.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
            canvas.create_window((0, 0), window=scroll_frame, anchor="nw")
            canvas.configure(yscrollcommand=scrollbar.set)

            canvas.pack(side="left", fill="both", expand=True)
            scrollbar.pack(side="right", fill="y")

            # Scope the mouse-wheel binding to this canvas only (bind/unbind on
            # hover) so it never leaks to other windows under the shared root.
            def _on_wheel(e):
                canvas.yview_scroll(-1 * (e.delta // 120), "units")
            canvas.bind("<Enter>", lambda e: canvas.bind_all("<MouseWheel>", _on_wheel))
            canvas.bind("<Leave>", lambda e: canvas.unbind_all("<MouseWheel>"))

            for i, entry in enumerate(entries):
                frame = ttk.LabelFrame(scroll_frame, text="", padding=8)
                frame.pack(fill="x", pady=(0, 6), padx=(0, 10))

                ts = entry.get("timestamp", "")
                try:
                    dt = datetime.fromisoformat(ts)
                    time_str = dt.strftime("%b %d, %I:%M %p")
                except (ValueError, TypeError):
                    time_str = "Unknown time"

                header = ttk.Frame(frame)
                header.pack(fill="x")
                ttk.Label(header, text=f"#{len(entries) - i}", font=("Segoe UI", 9, "bold"),
                          foreground="gray").pack(side="left")
                ttk.Label(header, text=time_str, foreground="gray",
                          font=("Segoe UI", 8)).pack(side="right")

                text = entry.get("text", "")
                text_widget = tk.Text(frame, wrap="word", height=min(3, max(1, len(text) // 60 + 1)),
                                      font=("Segoe UI", 10), relief="flat", bg="#f5f5f5",
                                      padx=6, pady=4)
                text_widget.insert("1.0", text)
                text_widget.config(state="disabled")
                text_widget.pack(fill="x", pady=(4, 2))

                btn_frame = ttk.Frame(frame)
                btn_frame.pack(anchor="e")
                copy_btn = ttk.Button(btn_frame, text="Copy",
                                      command=lambda t=text: self._copy_text(t))
                copy_btn.pack(side="right")

        sep = ttk.Separator(root, orient="horizontal")
        sep.pack(fill="x", pady=(10, 8))

        btn_frame = ttk.Frame(root)
        btn_frame.pack(fill="x")

        ttk.Button(btn_frame, text="Close", command=self._close).pack(side="right")
        if entries:
            ttk.Button(btn_frame, text="Clear History",
                       command=self._clear_history).pack(side="left")

    def _copy_text(self, text: str) -> None:
        self._win.clipboard_clear()
        self._win.clipboard_append(text)
        log.info("Copied text to clipboard (%d chars)", len(text))

    def _clear_history(self) -> None:
        history.clear()
        self._refresh()

    def _close(self) -> None:
        if self._win is not None:
            self._win.destroy()
            self._win = None
