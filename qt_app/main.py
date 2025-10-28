import os
import sys
import time
import signal
import tempfile
from datetime import datetime

from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import (
    QApplication,
    QMainWindow,
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QTableWidget,
    QTableWidgetItem,
    QHeaderView,
    QPushButton,
    QAbstractItemView,
    QMessageBox,
    QDialog,
    QTextEdit,
    QLabel,
)

try:
    import psutil
except ImportError as exc:
    raise SystemExit(
        "psutil is required. Install dependencies with: pip install -r requirements.txt"
    ) from exc


class SummaryDialog(QDialog):
    def __init__(self, parent: QWidget, summary_text: str):
        super().__init__(parent)
        self.setWindowTitle("Operation Complete")
        self.resize(720, 520)
        layout = QVBoxLayout()
        self.setLayout(layout)

        header = QLabel("RAM Management Summary")
        header.setAlignment(Qt.AlignmentFlag.AlignHCenter)
        layout.addWidget(header)

        text = QTextEdit()
        text.setReadOnly(True)
        text.setPlainText(summary_text)
        layout.addWidget(text)

        buttons = QHBoxLayout()
        close_btn = QPushButton("Close")
        close_btn.clicked.connect(self.accept)
        buttons.addStretch(1)
        buttons.addWidget(close_btn)
        layout.addLayout(buttons)


class RamManagerWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("RAM Management Tool")
        self.resize(900, 560)

        self.temp_dir = tempfile.mkdtemp(prefix="ram_manager_")
        self.log_file = os.path.join(self.temp_dir, "ram_manager.log")
        self.terminated: list[str] = []
        self.failed: list[str] = []
        self.menu_rows: list[dict] = []

        central = QWidget()
        self.setCentralWidget(central)
        root = QVBoxLayout()
        central.setLayout(root)

        self.info_label = QLabel("Identify and terminate memory‑intensive processes.")
        root.addWidget(self.info_label)

        self.table = QTableWidget(0, 5)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.setColumnCount(5)
        self.table.setHorizontalHeaderLabels(["Select", "PID", "Process", "RAM (MB)", "% MEM"])
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
        root.addWidget(self.table)

        btns = QHBoxLayout()
        self.refresh_btn = QPushButton("Refresh")
        self.terminate_btn = QPushButton("Terminate Selected")
        self.summary_btn = QPushButton("Show Summary")
        btns.addWidget(self.refresh_btn)
        btns.addStretch(1)
        btns.addWidget(self.terminate_btn)
        btns.addWidget(self.summary_btn)
        root.addLayout(btns)

        self.refresh_btn.clicked.connect(self.refresh_process_list)
        self.terminate_btn.clicked.connect(self.terminate_selected)
        self.summary_btn.clicked.connect(self.show_summary)

        self.ram_before_mb = self.get_total_ram_usage_mb()
        self.ram_after_mb = None
        self.log_message("=== RAM Management App Started ===")
        self.log_message(f"User: {psutil.Process().username()}")
        self.log_message(f"Initial RAM usage: {self.ram_before_mb} MB")
        self.refresh_process_list()

    def log_message(self, message: str) -> None:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = f"[{timestamp}] {message}\n"
        try:
            with open(self.log_file, "a", encoding="utf-8") as f:
                f.write(line)
        except Exception:
            pass

    def get_total_ram_usage_mb(self) -> int:
        total_rss = 0
        for proc in psutil.process_iter(attrs=["memory_info"]):
            try:
                mem = proc.info.get("memory_info")
                if mem is not None:
                    total_rss += getattr(mem, "rss", 0)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        return int(total_rss / (1024 * 1024))

    def get_available_memory_mb(self) -> int:
        vm = psutil.virtual_memory()
        return int(vm.available / (1024 * 1024))

    def fetch_top_processes(self) -> list[dict]:
        items: list[dict] = []
        for proc in psutil.process_iter(attrs=["pid", "name", "memory_info", "memory_percent"]):
            try:
                info = proc.info
                mem = info.get("memory_info")
                mem_rss = int(getattr(mem, "rss", 0))
                mem_mb = mem_rss / (1024 * 1024)
                mem_pct = info.get("memory_percent") or 0.0
                name = info.get("name") or "(unknown)"
                items.append(
                    {
                        "pid": int(info.get("pid")),
                        "name": name,
                        "mem_mb": float(f"{mem_mb:.1f}"),
                        "mem_pct": float(f"{mem_pct:.1f}"),
                        "rss": mem_rss,
                    }
                )
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        items.sort(key=lambda x: x["rss"], reverse=True)
        return items[:10]

    def refresh_process_list(self) -> None:
        self.menu_rows = self.fetch_top_processes()
        self.table.setRowCount(len(self.menu_rows))
        for row, item in enumerate(self.menu_rows):
            select_item = QTableWidgetItem()
            select_item.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled)
            select_item.setCheckState(Qt.CheckState.Unchecked)
            self.table.setItem(row, 0, select_item)

            pid_item = QTableWidgetItem(str(item["pid"]))
            pid_item.setTextAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
            self.table.setItem(row, 1, pid_item)

            name_item = QTableWidgetItem(item["name"]) 
            self.table.setItem(row, 2, name_item)

            mem_item = QTableWidgetItem(f"{item['mem_mb']:.1f}")
            mem_item.setTextAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
            self.table.setItem(row, 3, mem_item)

            pct_item = QTableWidgetItem(f"{item['mem_pct']:.1f}")
            pct_item.setTextAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
            self.table.setItem(row, 4, pct_item)

        self.table.resizeRowsToContents()

    def _selected_pids(self) -> list[int]:
        pids: list[int] = []
        for row in range(self.table.rowCount()):
            item = self.table.item(row, 0)
            if item is not None and item.checkState() == Qt.CheckState.Checked:
                pid_item = self.table.item(row, 1)
                if pid_item is not None:
                    try:
                        pids.append(int(pid_item.text()))
                    except ValueError:
                        continue
        return pids

    def terminate_selected(self) -> None:
        pids = self._selected_pids()
        if not pids:
            QMessageBox.information(self, "No Selection", "No processes were selected for termination.")
            return

        self.terminated = []
        self.failed = []

        for pid in pids:
            proc_desc = self._format_proc_desc(pid)
            self.log_message(f"Attempting to terminate: {proc_desc}")
            ok = self._terminate_with_fallback(pid)
            if ok:
                self.terminated.append(proc_desc)
                self.log_message(f"Successfully terminated: {proc_desc}")
            else:
                self.failed.append(proc_desc + " (Insufficient permissions or busy)")
                self.log_message(f"Failed to terminate: {proc_desc}")

        time.sleep(1.5)
        self.ram_after_mb = self.get_total_ram_usage_mb()
        self.log_message(f"Final RAM usage: {self.ram_after_mb} MB")
        self.refresh_process_list()

        self.show_summary()

    def _terminate_with_fallback(self, pid: int) -> bool:
        if not psutil.pid_exists(pid):
            return True
        try:
            os.kill(pid, signal.SIGTERM)
        except PermissionError:
            pass
        except ProcessLookupError:
            return True

        deadline = time.time() + 1.0
        while time.time() < deadline:
            if not psutil.pid_exists(pid):
                return True
            time.sleep(0.1)

        try:
            os.kill(pid, signal.SIGKILL)
        except PermissionError:
            return False
        except ProcessLookupError:
            return True

        time.sleep(0.5)
        return not psutil.pid_exists(pid)

    def _format_proc_desc(self, pid: int) -> str:
        try:
            p = psutil.Process(pid)
            rss_mb = int(p.memory_info().rss / (1024 * 1024))
            name = p.name()
            return f"PID {pid}: {name} ({rss_mb} MB)"
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            return f"PID {pid}: (unknown)"

    def _build_summary_text(self) -> str:
        ram_after = self.ram_after_mb if self.ram_after_mb is not None else self.get_total_ram_usage_mb()
        ram_freed = max(self.ram_before_mb - ram_after, 0)
        available_after = self.get_available_memory_mb()

        lines: list[str] = []
        lines.append("=" * 72)
        lines.append("RAM MANAGEMENT SUMMARY")
        lines.append("=" * 72)
        lines.append("")
        lines.append("RAM USAGE STATISTICS:")
        lines.append(f"  Before Operation:  {self.ram_before_mb} MB")
        lines.append(f"  After Operation:   {ram_after} MB")
        lines.append(f"  RAM Freed:         {ram_freed} MB")
        lines.append(f"  Available Memory:  {available_after} MB")
        lines.append("")
        lines.append("-" * 72)
        lines.append("")
        if self.terminated:
            lines.append(f"SUCCESSFULLY TERMINATED PROCESSES ({len(self.terminated)}):")
            for t in self.terminated:
                lines.append(f"  \u2713 {t}")
            lines.append("")
        else:
            lines.append("SUCCESSFULLY TERMINATED PROCESSES: None")
            lines.append("")
        if self.failed:
            lines.append(f"FAILED TO TERMINATE ({len(self.failed)}):")
            for f in self.failed:
                lines.append(f"  \u2717 {f}")
            lines.append("")
            lines.append("NOTE: Failed terminations may require administrator privileges.")
            lines.append("      Run with 'sudo' or use Activity Monitor with admin rights.")
            lines.append("")
        lines.append("-" * 72)
        lines.append("")
        lines.append(f"Operation completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append("")
        lines.append(f"Log file: {self.log_file}")
        return "\n".join(lines)

    def show_summary(self) -> None:
        summary = self._build_summary_text()
        dlg = SummaryDialog(self, summary)
        dlg.exec()


def main() -> None:
    app = QApplication(sys.argv)
    win = RamManagerWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()


