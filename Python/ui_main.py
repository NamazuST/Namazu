"""
Namazu Shaking Table Control Interface
A lightweight UI for generating signals and controlling the shaking table
"""

import tkinter as tk
from tkinter import ttk, messagebox
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure
import numpy as np
import sys
import os
import serial.tools.list_ports

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
        

class FixedHarmonicPanel(SignalParameterPanel):
    """Parameter panel for Fixed Harmonic signal generation"""
    def __init__(self, parent, on_update_callback):
        super().__init__(parent, on_update_callback)
        
        ttk.Label(self, text="Fixed Harmonic Parameters", font=('Arial', 10, 'bold')).grid(row=0, column=0, columnspan=2, pady=5)
        
        # Frequencies input
        ttk.Label(self, text="Frequencies (Hz, comma-separated):").grid(row=1, column=0, sticky='w', padx=5, pady=2)
        self.freq_entry = ttk.Entry(self, width=30)
        self.freq_entry.insert(0, "1.0, 2.0, 3.0")
        self.freq_entry.grid(row=1, column=1, padx=5, pady=2)
        self.freq_entry.bind('<KeyRelease>', lambda e: on_update_callback())
        
        # Amplitudes input
        ttk.Label(self, text="Amplitudes (mm, comma-separated):").grid(row=2, column=0, sticky='w', padx=5, pady=2)
        self.amp_entry = ttk.Entry(self, width=30)
        self.amp_entry.insert(0, "5.0, 3.0, 2.0")
        self.amp_entry.grid(row=2, column=1, padx=5, pady=2)
        self.amp_entry.bind('<KeyRelease>', lambda e: on_update_callback())
        
    def get_frequencies(self):
        try:
            return [float(x.strip()) for x in self.freq_entry.get().split(',')]
        except:
            return [1.0, 2.0, 3.0]
    
    def get_amplitudes(self):
        try:
            return [float(x.strip()) for x in self.amp_entry.get().split(',')]
        except:
            return [5.0, 3.0, 2.0]
    
    def get_shaking_data(self):
        data = FixedHarmonicShakingData()
        # TODO: Set frequencies and amplitudes on data object
        return data


class ShinozukaPanel(SignalParameterPanel):
    """Parameter panel for Shinozuka signal generation"""
    def __init__(self, parent, on_update_callback):
        super().__init__(parent, on_update_callback)
        
        ttk.Label(self, text="Shinozuka Parameters", font=('Arial', 10, 'bold')).grid(row=0, column=0, columnspan=2, pady=5)
        
        # PSD parameters (placeholder - adjust based on your implementation)
        ttk.Label(self, text="PSD Type:").grid(row=1, column=0, sticky='w', padx=5, pady=2)
        self.psd_combo = ttk.Combobox(self, values=["Kanai-Tajimi", "Custom"], state='readonly', width=27)
        self.psd_combo.set("Kanai-Tajimi")
        self.psd_combo.grid(row=1, column=1, padx=5, pady=2)
        self.psd_combo.bind('<<ComboboxSelected>>', lambda e: on_update_callback())
        
        ttk.Label(self, text="Ground frequency ωg (rad/s):").grid(row=2, column=0, sticky='w', padx=5, pady=2)
        self.omega_g_entry = ttk.Entry(self, width=30)
        self.omega_g_entry.insert(0, "15.0")
        self.omega_g_entry.grid(row=2, column=1, padx=5, pady=2)
        self.omega_g_entry.bind('<KeyRelease>', lambda e: on_update_callback())
        
        ttk.Label(self, text="Damping ratio ζg:").grid(row=3, column=0, sticky='w', padx=5, pady=2)
        self.zeta_g_entry = ttk.Entry(self, width=30)
        self.zeta_g_entry.insert(0, "0.6")
        self.zeta_g_entry.grid(row=3, column=1, padx=5, pady=2)
        self.zeta_g_entry.bind('<KeyRelease>', lambda e: on_update_callback())
        
    def get_shaking_data(self):
        data = ShinozukaShakingData()
        # TODO: Set PSD parameters on data object
        return data


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
        
        # Create UI
        self.create_menu()
        self.create_main_layout()
        
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
        """Switch parameter panel based on selected method"""
        # Destroy old panel
        if self.current_param_panel:
            self.current_param_panel.destroy()
        
        # Create new panel based on method
        method = self.method_var.get()
        
        if method == SignalGenerationMethod.FIXED_HARMONIC:
            self.current_param_panel = FixedHarmonicPanel(self.param_panel_container, self.update_plot)
        elif method == SignalGenerationMethod.SHINOZUKA:
            self.current_param_panel = ShinozukaPanel(self.param_panel_container, self.update_plot)
        else:
            self.current_param_panel = ttk.Label(self.param_panel_container, text="Coming soon...")
        
        self.current_param_panel.pack(fill='both', expand=True)
        self.update_plot()
        
    def generate_signal(self):
        """Generate signal based on current parameters"""
        try:
            max_t = float(self.max_t_entry.get())
            sample_rate = float(self.sample_rate_entry.get())
            
            # Generate signal based on method
            method = self.method_var.get()
            
            if method == SignalGenerationMethod.FIXED_HARMONIC:
                freqs = self.current_param_panel.get_frequencies()
                amps = self.current_param_panel.get_amplitudes()
                
                # Create ShakingData instance
                self.shaking_data = FixedHarmonicShakingData(
                    namazuInstance=self.namazu_instance,
                    frequencies=freqs,
                    amplitudes=amps,
                    sampleRate=sample_rate,
                    maxT=max_t
                )
                
                # Generate the signal (this also calls setup() and generates MarvCode)
                self.shaking_data.generate_signal()
                self.current_signal = self.shaking_data.inputSignal
                    
            elif method == SignalGenerationMethod.SHINOZUKA:
                # Create ShakingData instance
                self.shaking_data = ShinozukaShakingData(
                    namazuInstance=self.namazu_instance,
                    psd_func=None,  # TODO: Get from panel
                    sampleRate=sample_rate,
                    maxT=max_t
                )
                
                # TODO: Implement Shinozuka generate_signal method
                # For now, placeholder
                t = np.linspace(0, max_t, int(max_t * sample_rate))
                signal = 5 * np.random.randn(len(t))
                self.shaking_data.inputSignal = np.column_stack([t, signal])
                self.shaking_data.setup()
                self.current_signal = self.shaking_data.inputSignal
                
            else:
                messagebox.showwarning("Not Implemented", "This method is not yet implemented")
                return
            
            # Update plot
            self.update_plot()
            
            # Update MarvCode status
            self.update_marv_status()
            
            marv_status = ""
            if self.shaking_data.marvCode:
                marv_status = f"\nMarvCode generated: {len(self.shaking_data.marvCode)} chars"
            
            self.marv_status_label.config(
                    text=f"Signal generated: {len(self.current_signal)} samples over {max_t}s{marv_status}",
                    foreground='green'
                )
            
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
            
            self.namazu_instance = NamazuInstance(comport)
            self.namazu_instance.connect()
            
            self.health_canvas.itemconfig(self.health_indicator, fill='green')
            self.status_label.config(text="Connected")
            self.update_marv_status()
            
            messagebox.showinfo("Success", f"Connected to {comport}")
            
        except Exception as e:
            self.health_canvas.itemconfig(self.health_indicator, fill='red')
            self.status_label.config(text="Error")
            messagebox.showerror("Connection Error", f"Failed to connect:\n{str(e)}")
    
    def disconnect_device(self):
        """Disconnect from device"""
        if self.namazu_instance:
            self.namazu_instance.disconnect()
            self.namazu_instance = None
            
        self.health_canvas.itemconfig(self.health_indicator, fill='gray')
        self.status_label.config(text="Disconnected")
        self.shaking_data = None  # Clear MarvCode when disconnecting
        self.update_marv_status()
        
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
        messagebox.showinfo("TODO", "Start command not yet implemented")
    
    def stop_shake(self):
        """Stop shaking"""
        if not self.namazu_instance:
            messagebox.showwarning("Not Connected", "Please connect to device first")
            return
        messagebox.showinfo("TODO", "Stop command not yet implemented")
    
    def center_table(self):
        """Center the table"""
        if not self.namazu_instance:
            messagebox.showwarning("Not Connected", "Please connect to device first")
            return
        messagebox.showinfo("TODO", "Center command not yet implemented")
    
    def home_table(self):
        """Home the table"""
        if not self.namazu_instance:
            messagebox.showwarning("Not Connected", "Please connect to device first")
            return
        messagebox.showinfo("TODO", "Home command not yet implemented")
    
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


def main():
    root = tk.Tk()
    app = NamazuUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
