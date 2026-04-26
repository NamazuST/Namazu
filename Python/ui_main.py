"""
Namazu Shaking Table Control Interface
A lightweight UI for generating signals and controlling the shaking table
"""

import time
import tkinter as tk
from tkinter import ttk, messagebox
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure
import numpy as np
import sys
import os
import serial.tools.list_ports
import threading

# Add Classes directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), 'Classes'))

from ShakingDataClass import SignalGenerationMethod, ShakingData, FixedHarmonicShakingData, ShinozukaShakingData
from NamazuInstance import NamazuInstance

class SignalParameterPanel(ttk.Frame):
    """Base class for signal-specific parameter panels"""
    def __init__(self, parent, on_update_callback):
        super().__init__(parent)
        self.on_update_callback = on_update_callback
        
    def get_shaking_data(self):
        """Override in subclasses to return configured ShakingData instance"""
        raise NotImplementedError
        

# Registry: maps SignalGenerationMethod value -> ShakingData subclass
METHOD_CLASS_MAP = {
    SignalGenerationMethod.FIXED_HARMONIC: FixedHarmonicShakingData,
    SignalGenerationMethod.SHINOZUKA:      ShinozukaShakingData,
}


class AutoParameterPanel(SignalParameterPanel):
    """Automatically builds a parameter panel from a ShakingData class's definitions."""

    def __init__(self, parent, on_update_callback, shaking_data_class):
        super().__init__(parent, on_update_callback)
        self._class = shaking_data_class
        self._widgets = {}  # name -> widget

        defs = shaking_data_class.get_parameter_definitions()
        ttk.Label(self, text=f"{shaking_data_class.__name__} Parameters",
                  font=('Arial', 10, 'bold')).grid(row=0, column=0, columnspan=2, pady=5)

        for row, p in enumerate(defs, start=1):
            unit_suffix = f" ({p.unit})" if p.unit else ""
            ttk.Label(self, text=f"{p.label}{unit_suffix}:").grid(
                row=row, column=0, sticky='w', padx=5, pady=2)

            if p.type == "choice":
                w = ttk.Combobox(self, values=p.choices, state='readonly', width=27)
                w.set(p.default)
                w.bind('<<ComboboxSelected>>', lambda e: on_update_callback())
            else:
                w = ttk.Entry(self, width=30)
                w.insert(0, str(p.default))
                w.bind('<KeyRelease>', lambda e: on_update_callback())

            w.grid(row=row, column=1, padx=5, pady=2)
            self._widgets[p.name] = (p, w)

    def _parse_value(self, param_def, raw: str):
        """Convert raw string to the appropriate Python type."""
        t = param_def.type
        if t == "float":
            return float(raw)
        if t == "int":
            return int(raw)
        if t == "float_list":
            return [float(x.strip()) for x in raw.split(',')]
        return raw  # str / choice

    def get_params(self) -> dict:
        """Return {name: typed_value} for all parameters; falls back to defaults on error."""
        result = {}
        for name, (p, w) in self._widgets.items():
            try:
                result[name] = self._parse_value(p, w.get())
            except (ValueError, TypeError):
                result[name] = self._parse_value(p, str(p.default))
        return result

    def get_shaking_data(self):
        # Thin wrapper — real instantiation happens in generate_signal via from_params
        raise NotImplementedError("Use from_params() on the ShakingData class directly.")


class NamazuUI:
    """Main UI for Namazu Shaking Table Control"""
    
    def __init__(self, root):
        self.root = root
        self.root.title("Namazu Shaking Table Control")
        self.root.geometry("1200x700")
        
        # State
        self.current_signal = None
        self.shaking_data = None  # Store the ShakingData object
        self.namazu_instance = None
        self.health_check_running = False
        self.is_shaking = False  # Track if shaking is in progress
        self.shake_thread = None  # Thread for shake monitoring
        self.stop_shake_flag = threading.Event()  # Flag to stop shaking
        
        # Create UI
        self.create_menu()
        self.create_main_layout()
        
        # Handle window close
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)
        
    def create_menu(self):
        """Create menu bar"""
        menubar = tk.Menu(self.root)
        self.root.config(menu=menubar)
        
        # File menu
        file_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="File", menu=file_menu)
        file_menu.add_command(label="Load Signal...", command=self.load_signal)
        file_menu.add_command(label="Save Signal...", command=self.save_signal)
        file_menu.add_separator()
        file_menu.add_command(label="Exit", command=self.root.quit)
        
        # Settings menu
        settings_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Settings", menu=settings_menu)
        settings_menu.add_command(label="Device Settings...", command=self.open_device_settings)
        settings_menu.add_command(label="Signal Settings...", command=self.open_signal_settings)
        
        # Help menu
        help_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Help", menu=help_menu)
        help_menu.add_command(label="About", command=self.show_about)
        
    def create_main_layout(self):
        """Create main window layout"""
        # Left panel: Controls and parameters
        left_panel = ttk.Frame(self.root, width=400)
        left_panel.pack(side='left', fill='both', padx=5, pady=5)
        left_panel.pack_propagate(False)
        
        # Right panel: Plot
        right_panel = ttk.Frame(self.root)
        right_panel.pack(side='right', fill='both', expand=True, padx=5, pady=5)
        
        # --- LEFT PANEL CONTENTS ---
        
        # Connection status
        self.create_connection_panel(left_panel)
        
        # Signal generation method selector
        self.create_method_selector(left_panel)
        
        # Common parameters
        self.create_common_parameters(left_panel)
        
        # Method-specific parameters (dynamic)
        self.param_panel_container = ttk.LabelFrame(left_panel, text="Method Parameters", padding=10)
        self.param_panel_container.pack(fill='x', padx=5, pady=5)
        self.current_param_panel = None
        self.switch_parameter_panel()  # Initialize with default method
        
        # Control buttons
        self.create_control_buttons(left_panel)
        
        # --- RIGHT PANEL CONTENTS ---
        
        # Plot
        self.create_plot(right_panel)
        
    def create_connection_panel(self, parent):
        """Create connection status and controls"""
        frame = ttk.LabelFrame(parent, text="Device Connection", padding=10)
        frame.pack(fill='x', padx=5, pady=5)
        
        # COM port selector
        port_frame = ttk.Frame(frame)
        port_frame.pack(fill='x', pady=2)
        
        ttk.Label(port_frame, text="COM Port:").pack(side='left', padx=5)
        self.port_combo = ttk.Combobox(port_frame, state='readonly', width=20)
        self.port_combo.pack(side='left', padx=5, fill='x', expand=True)
        
        # Refresh button
        refresh_btn = ttk.Button(port_frame, text="🔄", width=3, command=self.refresh_ports)
        refresh_btn.pack(side='left', padx=2)
        
        # Initial port scan
        self.refresh_ports()
        
        # Health indicator
        indicator_frame = ttk.Frame(frame)
        indicator_frame.pack(fill='x', pady=2)
        
        ttk.Label(indicator_frame, text="Status:").pack(side='left', padx=5)
        self.health_canvas = tk.Canvas(indicator_frame, width=20, height=20, bg='white', highlightthickness=1)
        self.health_canvas.pack(side='left', padx=5)
        self.health_indicator = self.health_canvas.create_oval(2, 2, 18, 18, fill='gray', outline='black')
        self.status_label = ttk.Label(indicator_frame, text="Disconnected")
        self.status_label.pack(side='left', padx=5)
        
        # Connect/Disconnect buttons
        btn_frame = ttk.Frame(frame)
        btn_frame.pack(fill='x', pady=5)
        
        ttk.Button(btn_frame, text="Connect", command=self.connect_device).pack(side='left', padx=2, expand=True, fill='x')
        ttk.Button(btn_frame, text="Disconnect", command=self.disconnect_device).pack(side='left', padx=2, expand=True, fill='x')
        
    def create_method_selector(self, parent):
        """Create signal generation method selector"""
        frame = ttk.LabelFrame(parent, text="Signal Generation Method", padding=10)
        frame.pack(fill='x', padx=5, pady=5)
        
        self.method_var = tk.StringVar(value=SignalGenerationMethod.FIXED_HARMONIC)
        
        methods = [
            (SignalGenerationMethod.FIXED_HARMONIC, "Fixed Harmonic"),
            (SignalGenerationMethod.SHINOZUKA, "Shinozuka (Spectral)"),
            (SignalGenerationMethod.KANAI_TAJIMI, "Kanai-Tajimi (Coming Soon)")
        ]
        
        for value, text in methods:
            rb = ttk.Radiobutton(frame, text=text, variable=self.method_var, value=value,
                               command=self.switch_parameter_panel)
            rb.pack(anchor='w', pady=2)
            
    def create_common_parameters(self, parent):
        """Create common signal parameters"""
        frame = ttk.LabelFrame(parent, text="Common Parameters", padding=10)
        frame.pack(fill='x', padx=5, pady=5)
        
        # Max time
        ttk.Label(frame, text="Duration (s):").grid(row=0, column=0, sticky='w', pady=2)
        self.max_t_entry = ttk.Entry(frame, width=15)
        self.max_t_entry.insert(0, "10.0")
        self.max_t_entry.grid(row=0, column=1, sticky='ew', pady=2, padx=5)
        self.max_t_entry.bind('<KeyRelease>', lambda e: self.update_plot())
        
        # Sampling rate
        ttk.Label(frame, text="Sampling Rate (Hz):").grid(row=1, column=0, sticky='w', pady=2)
        self.sample_rate_entry = ttk.Entry(frame, width=15)
        self.sample_rate_entry.insert(0, "100.0")
        self.sample_rate_entry.grid(row=1, column=1, sticky='ew', pady=2, padx=5)
        self.sample_rate_entry.bind('<KeyRelease>', lambda e: self.update_plot())
        
        frame.columnconfigure(1, weight=1)
        
    def create_control_buttons(self, parent):
        """Create control buttons"""
        frame = ttk.LabelFrame(parent, text="Controls", padding=10)
        frame.pack(fill='x', padx=5, pady=5)
        
        # Generate signal button
        ttk.Button(frame, text="Generate Signal", command=self.generate_signal).pack(fill='x', pady=2)
        
        # MarvCode status
        self.marv_status_label = ttk.Label(frame, text="MarvCode: Not generated", foreground='gray')
        self.marv_status_label.pack(fill='x', pady=2)
        
        # Send to device
        ttk.Button(frame, text="Send to Device", command=self.send_to_device).pack(fill='x', pady=2)
        
        # Shake status indicator
        self.shake_status_label = ttk.Label(frame, text="Table: Idle", foreground='gray')
        self.shake_status_label.pack(fill='x', pady=2)
        
        ttk.Separator(frame, orient='horizontal').pack(fill='x', pady=5)
        
        # Movement controls
        btn_grid = ttk.Frame(frame)
        btn_grid.pack(fill='x', pady=2)
        
        ttk.Button(btn_grid, text="Start", command=self.start_shake).grid(row=0, column=0, padx=2, pady=2, sticky='ew')
        ttk.Button(btn_grid, text="Stop", command=self.stop_shake).grid(row=0, column=1, padx=2, pady=2, sticky='ew')
        ttk.Button(btn_grid, text="Center", command=self.center_table).grid(row=1, column=0, padx=2, pady=2, sticky='ew')
        ttk.Button(btn_grid, text="Home", command=self.home_table).grid(row=1, column=1, padx=2, pady=2, sticky='ew')
        
        btn_grid.columnconfigure(0, weight=1)
        btn_grid.columnconfigure(1, weight=1)
        
    def create_plot(self, parent):
        """Create matplotlib plot"""
        plot_frame = ttk.LabelFrame(parent, text="Signal Preview", padding=10)
        plot_frame.pack(fill='both', expand=True)
        
        # Create matplotlib figure
        self.fig = Figure(figsize=(8, 6), dpi=100)
        self.ax = self.fig.add_subplot(111)
        self.ax.set_xlabel('Time (s)')
        self.ax.set_ylabel('Position (mm)')
        self.ax.set_title('Generated Signal')
        self.ax.grid(True, alpha=0.3)
        
        # Embed in tkinter
        self.canvas = FigureCanvasTkAgg(self.fig, master=plot_frame)
        self.canvas.draw()
        self.canvas.get_tk_widget().pack(fill='both', expand=True)
        
        # Initial empty plot
        self.ax.plot([], [])
        self.canvas.draw()
        
    def switch_parameter_panel(self):
        if self.current_param_panel:
            self.current_param_panel.destroy()

        method = self.method_var.get()
        cls = METHOD_CLASS_MAP.get(method)

        if cls:
            self.current_param_panel = AutoParameterPanel(
                self.param_panel_container, self.update_plot, cls)
        else:
            self.current_param_panel = ttk.Label(
                self.param_panel_container, text="Coming soon...")

        self.current_param_panel.pack(fill='both', expand=True)
        self.update_plot()

    def generate_signal(self):
        try:
            max_t       = float(self.max_t_entry.get())
            sample_rate = float(self.sample_rate_entry.get())
            method      = self.method_var.get()
            cls         = METHOD_CLASS_MAP.get(method)

            if cls is None:
                messagebox.showwarning("Not Implemented", "This method is not yet implemented")
                return

            params = self.current_param_panel.get_params()
            self.shaking_data = cls.from_params(params, self.namazu_instance, sample_rate, max_t)
            self.shaking_data.generate_signal()
            self.current_signal = self.shaking_data.inputSignal

            self.update_plot()
            self.update_marv_status()

            marv_suffix = ""
            if self.shaking_data.marvCode:
                marv_suffix = f"\nMarvCode: {len(self.shaking_data.marvCode)} chars"
            self.marv_status_label.config(
                text=f"Signal generated: {len(self.current_signal)} samples over {max_t}s{marv_suffix}",
                foreground='green')

        except Exception as e:
            messagebox.showerror("Error", f"Failed to generate signal:\n{str(e)}")

    def update_plot(self):
        """Update the plot with current signal"""
        if self.current_signal is not None:
            self.ax.clear()
            self.ax.plot(self.current_signal[:, 0], self.current_signal[:, 1])
            self.ax.set_xlabel('Time (s)')
            self.ax.set_ylabel('Position (mm)')
            self.ax.set_title('Generated Signal')
            self.ax.grid(True, alpha=0.3)
            self.canvas.draw()
    
    def update_marv_status(self):
        """Update MarvCode status label"""
        if self.shaking_data and self.shaking_data.marvCode:
            num_lines = self.shaking_data.marvCode.count('\n')
            self.marv_status_label.config(
                text=f"MarvCode: Ready ({num_lines} commands)",
                foreground='green'
            )
        else:
            if self.namazu_instance:
                self.marv_status_label.config(
                    text="MarvCode: Generate signal to create",
                    foreground='orange'
                )
            else:
                self.marv_status_label.config(
                    text="MarvCode: Connect device first",
                    foreground='gray'
                )
    
    # Connection methods
    def refresh_ports(self):
        """Refresh the list of available COM ports"""
        ports = serial.tools.list_ports.comports()
        port_list = []
        
        for port in ports:
            # Format: "COM3 - USB Serial Device"
            port_desc = f"{port.device}"
            if port.description and port.description != port.device:
                port_desc += f" - {port.description}"
            port_list.append(port_desc)
        
        # Update combobox
        self.port_combo['values'] = port_list
        
        # Auto-select first port if available
        if port_list and not self.port_combo.get():
            self.port_combo.current(0)
        elif not port_list:
            self.port_combo.set("No ports found")
        
        return len(port_list)
    
    def connect_device(self):
        """Connect to Namazu device"""
        try:
            # Get selected COM port from dropdown
            port_selection = self.port_combo.get()
            
            if not port_selection or port_selection == "No ports found":
                messagebox.showwarning("No Port Selected", 
                    "Please select a COM port.\n\n" +
                    "Click the refresh button (🔄) to scan for ports.")
                return
            
            # Extract just the port name (e.g., "COM3" from "COM3 - USB Serial Device")
            comport = port_selection.split(' - ')[0].split()[0]
            
            print("creating namazu instance")
            self.namazu_instance = NamazuInstance(comport)
            print("connecting")
            self.namazu_instance.connect()
            
            print("checking serial")
            self.health_canvas.itemconfig(self.health_indicator, fill='green')
            self.status_label.config(text="Connected")
            print("updating status")
            self.update_marv_status()
            
            messagebox.showinfo("Success", f"Connected to {comport}")
            
        except Exception as e:
            self.health_canvas.itemconfig(self.health_indicator, fill='red')
            self.status_label.config(text="Error")
            messagebox.showerror("Connection Error", f"Failed to connect:\n{str(e)}")
    
    def disconnect_device(self):
        """Disconnect from device"""
        # Stop any ongoing shake
        if self.is_shaking:
            self.stop_shake_flag.set()
            if self.shake_thread and self.shake_thread.is_alive():
                self.shake_thread.join(timeout=2.0)
        
        if self.namazu_instance:
            self.namazu_instance.disconnect()
            self.namazu_instance = None
            
        self.health_canvas.itemconfig(self.health_indicator, fill='gray')
        self.status_label.config(text="Disconnected")
        self.shaking_data = None  # Clear MarvCode when disconnecting
        self.update_marv_status()
        self._update_shake_status(False, "Idle", "gray")
        
        # Refresh port list in case device was unplugged
        self.refresh_ports()
    
    # Control methods
    def send_to_device(self):
        """Send MarvCode to device"""
        if not self.namazu_instance:
            messagebox.showwarning("Not Connected", "Please connect to device first")
            return
        
        if not self.shaking_data or not self.shaking_data.marvCode:
            messagebox.showwarning("No MarvCode", 
                "Please generate a signal first.\n\n" + 
                "Note: MarvCode is only generated when connected to a device.")
            return
        
        try:
            # Send MarvCode to the device
            num_lines = self.shaking_data.marvCode.count('\n')
            
            # Ask for confirmation
            response = messagebox.askyesno(
                "Send to Device", 
                f"Send MarvCode to {self.namazu_instance.comport}?\n\n" +
                f"Signal: {len(self.current_signal)} samples\n" +
                f"Commands: {num_lines} lines\n" +
                f"Duration: {self.shaking_data.maxT}s\n" +
                f"Rate: {self.namazu_instance.motorRate} Hz"
            )
            
            if response:
                # Send the command
                self.namazu_instance.send_command(self.shaking_data.marvCode)
                messagebox.showinfo("Success", 
                    f"MarvCode sent successfully!\n" +
                    f"{num_lines} commands uploaded to device.")
                
        except Exception as e:
            messagebox.showerror("Error", f"Failed to send to device:\n{str(e)}")
    
    def start_shake(self):
        """Start shaking"""
        if not self.namazu_instance:
            messagebox.showwarning("Not Connected", "Please connect to device first")
            return
        
        if self.is_shaking:
            messagebox.showwarning("Already Running", "Shaking is already in progress")
            return
        
        # Start shake in background thread
        print("clearing stop shake flag")
        self.stop_shake_flag.clear()
        print("creating shake thread")
        self.shake_thread = threading.Thread(target=self._shake_worker, daemon=True)
        print("starting shake thread")
        self.shake_thread.start()
        
    def _shake_worker(self):
        """Worker thread that monitors shake status"""
        print("shake worker started")
        try:
            # Update UI status (thread-safe using after)
            print("updating shake status to running")
            self.root.after(0, self._update_shake_status, True, "Running...", "blue")
            print("sending start command to device")
            self.namazu_instance.send_command("start\n")
            
            # Monitor until shaking finishes or stop is requested
            while not self.stop_shake_flag.is_set():
                try:
                    response = self.namazu_instance.query_status()
                    
                    if response:
                        print(f"Device status: {response}")
                    
                    if response and "RUNNING" not in response:
                        print("breaking")
                        break
                    time.sleep(0.5)
                    
                except Exception as e:
                    print(f"Error reading status: {e}")
                    break
            
            # Update UI when done
            if self.stop_shake_flag.is_set():
                self.root.after(0, self._update_shake_status, False, "Stopped", "orange")
            else:
                self.root.after(0, self._update_shake_status, False, "Completed", "green")
            
        except Exception as e:
            print(f"Shake worker error: {e}")
            self.root.after(0, messagebox.showerror, "Shake Error", f"Error during shaking:\n{str(e)}")
            self.root.after(0, self._update_shake_status, False, "Error", "red")
    
    def _update_shake_status(self, is_shaking, status_text, color):
        """Update shake status label (thread-safe)"""
        self.is_shaking = is_shaking
        self.shake_status_label.config(
            text=f"Table: {status_text}",
            foreground=color
        )
    
    def stop_shake(self):
        """Stop shaking"""
        if not self.namazu_instance:
            messagebox.showwarning("Not Connected", "Please connect to device first")
            return
    
        try:
            self.stop_shake_flag.set()
            self.namazu_instance.send_command("stop\n")
            self._update_shake_status(False, "Stopping...", "orange")
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to stop shaking:\n{str(e)}")
    
    def center_table(self):
        """Center the table"""
        if not self.namazu_instance:
            messagebox.showwarning("Not Connected", "Please connect to device first")
            return
        
        messagebox.showerror("Not Implemented", "Centering command not yet implemented in NamazuInstance")
        return
    
    def home_table(self):
        """Home the table"""
        if not self.namazu_instance:
            messagebox.showwarning("Not Connected", "Please connect to device first")
            return
        
        messagebox.showerror("Not Implemented", "Homing command not yet implemented in NamazuInstance")
        return
    
    # Menu callbacks
    def load_signal(self):
        messagebox.showinfo("TODO", "Load signal not yet implemented")
    
    def save_signal(self):
        messagebox.showinfo("TODO", "Save signal not yet implemented")
    
    def open_device_settings(self):
        messagebox.showinfo("TODO", "Device settings dialog not yet implemented")
    
    def open_signal_settings(self):
        messagebox.showinfo("TODO", "Signal settings dialog not yet implemented")
    
    def show_about(self):
        messagebox.showinfo("About", "Namazu Shaking Table Control v0.1\n\nA lightweight interface for controlling the Namazu shaking table")
    
    def on_closing(self):
        """Handle window close event"""
        # Stop any running shake
        if self.is_shaking:
            self.stop_shake_flag.set()
            if self.shake_thread and self.shake_thread.is_alive():
                self.shake_thread.join(timeout=2.0)
        
        # Disconnect device
        if self.namazu_instance:
            try:
                self.namazu_instance.disconnect()
            except:
                pass
        
        # Close window
        self.root.destroy()


def main():
    root = tk.Tk()
    app = NamazuUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
