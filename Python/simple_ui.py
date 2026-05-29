"""
Hardcode the signal parameters!!!
Namazu Shaking Table - Minimal Control Interface
Pre-configured freq sweep signal with Run/Stop only
"""
import sys
import os
import time
import threading
import matplotlib
matplotlib.use('TkAgg')
import tkinter as tk
from tkinter import ttk, messagebox
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure
import numpy as np
import serial.tools.list_ports

# Add Classes directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), 'Classes'))

# from ShakingDataClass import FixedHarmonicShakingData
from ShakingDataClass import FrequencySweepShakingData
from NamazuInstance import NamazuInstance


class MinimalShakingUI:
    """Minimal UI - Fixed harmonic signal with Run/Stop only"""
    
    # Fixed signal parameters
    FREQUENCY = 1.0      # Hz
    AMPLITUDE = 10.0     # mm
    DURATION = 10.0      # seconds
    SAMPLE_RATE = 100.0  # Hz
    # Add frequency sweep parameters:
    START_FREQ = 0.5     # Hz
    END_FREQ = 5.0       # Hz
    

    def __init__(self, root):
        self.root = root
        self.root.title("Namazu Shaking Table")
        # 
        self.root.geometry("1080x900")
        
        # State
        self.current_signal = None
        self.shaking_data = None
        self.namazu_instance = None
        self.is_shaking = False
        self.shake_thread = None
        self.stop_shake_flag = threading.Event()
        
        # Auto-generate the fixed signal
        self.generate_fixed_signal()
        
        # Create UI
        self.create_ui()
        
        # Handle window close
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)
    
    def generate_fixed_signal(self):
        """Generate the fixed harmonic signal"""
        try:
            # First, let's check what parameters FixedHarmonicShakingData expects
            # by looking at its parameter definitions
           # param_defs = FixedHarmonicShakingData.get_parameter_definitions()
            #print("FixedHarmonicShakingData expects these parameters:")
            #for p in param_defs:
               # print(f"  - {p.name}: {p.type} (default: {p.default})")
                
            param_defs = FrequencySweepShakingData.get_parameter_definitions()
            print("FrequencySweepShakingData expects these parameters:")
            for p in param_defs:
                print(f"  - {p.name}: {p.type} (default: {p.default})")

            # Try to create the signal directly with the class
            # Let's inspect what from_params expects
            import inspect
            sig = inspect.signature(FrequencySweepShakingData.from_params)
            print(f"\nfrom_params signature: {sig}")
            
            # Create a temporary instance to understand the structure
            # Let's try a direct approach
            params = {}
            for p in param_defs:
             if p.name == 'start_frequency' or p.name == 'f_start':
                params[p.name] = self.START_FREQ
             elif p.name == 'end_frequency' or p.name == 'f_end':
                params[p.name] = self.END_FREQ
             elif p.name == 'amplitude':
                params[p.name] = self.AMPLITUDE
             else:
                    # Use default for other parameters
                    if p.type == "float_list":
                        params[p.name] = [float(x) for x in str(p.default).strip('[]').split(',')]
                    elif p.type == "float":
                        params[p.name] = float(p.default)
                    elif p.type == "int":
                        params[p.name] = int(p.default)
                    else:
                        params[p.name] = p.default
            
            print(f"\nUsing parameters: {params}")
            
            # Create without device instance initially
            self.shaking_data = FrequencySweepShakingData.from_params(
                params, None, self.SAMPLE_RATE, self.DURATION)
            
            # Generate the signal
            self.shaking_data.generate_signal()
            self.current_signal = self.shaking_data.inputSignal
            
            print(f"Signal generated successfully: {len(self.current_signal)} samples")
            
        except Exception as e:
            print(f"Error generating fixed signal: {e}")
            import traceback
            traceback.print_exc()
            
            # Create a fallback simple signal
            self._create_fallback_signal()
    
    def _create_fallback_signal(self):
        """Create a simple fallback signal if class-based generation fails"""
        print("Creating fallback signal...")
        t = np.linspace(0, self.DURATION, int(self.SAMPLE_RATE * self.DURATION))
        # Linear frequency sweep
        freq = self.START_FREQ + (self.END_FREQ - self.START_FREQ) * t / self.DURATION
        # Phase is integral of frequency
        phase = 2 * np.pi * (self.START_FREQ * t + 0.5 * (self.END_FREQ - self.START_FREQ) * t**2 / self.DURATION)
        x = self.AMPLITUDE * np.sin(phase)
        # For a simple fixed harmonic signal
        # x = self.AMPLITUDE * np.sin(2 * np.pi * self.FREQUENCY * t)
        
        self.current_signal = np.column_stack((t, x))
        print(f"Fallback signal created: {len(self.current_signal)} samples")
    
    def regenerate_with_device(self):
        """Regenerate signal with device instance for MarvCode"""
        if self.namazu_instance:
            try:
                param_defs = FrequencySweepShakingData.get_parameter_definitions()
                params = {}
                for p in param_defs:
                    if p.name == 'start_frequency' or p.name == 'f_start':
                        params[p.name] = self.START_FREQ
                    elif p.name == 'end_frequency' or p.name == 'f_end':
                        params[p.name] = self.END_FREQ
                    elif p.name == 'amplitude':
                        params[p.name] = self.AMPLITUDE
                    else:
                        if p.type == "float_list":
                            params[p.name] = [float(x) for x in str(p.default).strip('[]').split(',')]
                        elif p.type == "float":
                            params[p.name] = float(p.default)
                        elif p.type == "int":
                            params[p.name] = int(p.default)
                        else:
                            params[p.name] = p.default

                self.shaking_data = FrequencySweepShakingData.from_params(
                    params, self.namazu_instance, self.SAMPLE_RATE, self.DURATION)
                self.shaking_data.generate_signal()
                self.current_signal = self.shaking_data.inputSignal
                print("Regenerated signal with device")
            except Exception as e:
                print(f"Error regenerating with device: {e}")

    def create_ui(self):
        """Create minimal UI layout"""
        # Main container
        main_frame = ttk.Frame(self.root, padding="20")
        main_frame.pack(fill='both', expand=True)
        
        # Connection section
        connection_frame = ttk.LabelFrame(main_frame, text="Device Connection", padding="15")
        connection_frame.pack(fill='x', pady=(0, 20))
        
        # Port selection row
        port_row = ttk.Frame(connection_frame)
        port_row.pack(fill='x', pady=(0, 10))
        
        ttk.Label(port_row, text="COM Port:", font=('Arial', 10)).pack(side='left', padx=(0, 10))
        self.port_combo = ttk.Combobox(port_row, state='readonly', width=15, font=('Arial', 10))
        self.port_combo.pack(side='left', padx=(0, 10))
        
        refresh_btn = ttk.Button(port_row, text="↻", width=3, command=self.refresh_ports)
        refresh_btn.pack(side='left')
        
        # Status and connect row
        status_row = ttk.Frame(connection_frame)
        status_row.pack(fill='x')
        
        # Connection indicator
        self.conn_canvas = tk.Canvas(status_row, width=25, height=25, bg='white', highlightthickness=1)
        self.conn_canvas.pack(side='left', padx=(0, 10))
        self.conn_light = self.conn_canvas.create_oval(3, 3, 22, 22, fill='gray', outline='black')
        
        self.conn_label = ttk.Label(status_row, text="Not Connected", font=('Arial', 10))
        self.conn_label.pack(side='left', padx=(0, 20))
        
        self.connect_btn = ttk.Button(status_row, text="Connect", command=self.toggle_connection)
        self.connect_btn.pack(side='right')
        
        # Initial port scan
        self.refresh_ports()
        
        # Signal info section
        signal_frame = ttk.LabelFrame(main_frame, text="Signal Configuration", padding="15")
        signal_frame.pack(fill='x', pady=(0, 20))
        
        # Signal parameters display (read-only)
        info_grid = ttk.Frame(signal_frame)
        info_grid.pack()
        
        ttk.Label(info_grid, text="Type:", font=('Arial', 10, 'bold')).grid(row=0, column=0, sticky='w', padx=(0, 20), pady=2)
        ttk.Label(info_grid, text="Frequency Sweep", font=('Arial', 10)).grid(row=0, column=1, sticky='w', pady=2)

        # Instead of single frequency, show start/end:
        ttk.Label(info_grid, text="Start Frequency:", font=('Arial', 10, 'bold')).grid(row=1, column=0, sticky='w', padx=(0, 20), pady=2)
        ttk.Label(info_grid, text=f"{self.START_FREQ} Hz", font=('Arial', 10)).grid(row=1, column=1, sticky='w', pady=2)

        ttk.Label(info_grid, text="End Frequency:", font=('Arial', 10, 'bold')).grid(row=2, column=0, sticky='w', padx=(0, 20), pady=2)
        ttk.Label(info_grid, text=f"{self.END_FREQ} Hz", font=('Arial', 10)).grid(row=2, column=1, sticky='w', pady=2)

        # Keep amplitude but move to row 3
        ttk.Label(info_grid, text="Amplitude:", font=('Arial', 10, 'bold')).grid(row=3, column=0, sticky='w', padx=(0, 20), pady=2)
        ttk.Label(info_grid, text=f"{self.AMPLITUDE} mm", font=('Arial', 10)).grid(row=3, column=1, sticky='w', pady=2)
        # Sample count (with safety check)
        sample_count = len(self.current_signal) if self.current_signal is not None else 0
        ttk.Label(info_grid, text="Samples:", font=('Arial', 10, 'bold')).grid(row=4, column=0, sticky='w', padx=(0, 20), pady=2)
        ttk.Label(info_grid, text=f"{sample_count}", font=('Arial', 10)).grid(row=4, column=1, sticky='w', pady=2)
        
        # Control buttons
        control_frame = ttk.Frame(main_frame)
        control_frame.pack(fill='x', pady=(0, 20))
        
        # Run button
        self.run_btn = tk.Button(control_frame, text="▶ RUN", 
                                 font=('Arial', 18, 'bold'),
                                 bg='#4CAF50', fg='white',
                                 activebackground='#45a049',
                                 relief='raised', borderwidth=3,
                                 command=self.start_shake,
                                 height=2)
        self.run_btn.pack(side='left', fill='x', expand=True, padx=(0, 5))
        
        # Stop button
        self.stop_btn = tk.Button(control_frame, text="■ STOP",
                                  font=('Arial', 18, 'bold'),
                                  bg='#f44336', fg='white',
                                  activebackground='#da190b',
                                  relief='raised', borderwidth=3,
                                  command=self.stop_shake,
                                  height=2)
        self.stop_btn.pack(side='left', fill='x', expand=True, padx=(5, 0))
        
        # Plot section
        plot_frame = ttk.LabelFrame(main_frame, text="Signal Preview", padding="10")
        plot_frame.pack(fill='both', expand=True)
        
        # Create plot (with safety check)
        if self.current_signal is not None and len(self.current_signal) > 0:
            self.fig = Figure(figsize=(8, 3), dpi=100)
            self.ax = self.fig.add_subplot(111)
            self.ax.plot(self.current_signal[:, 0], self.current_signal[:, 1], 'b-', linewidth=1.5)
            self.ax.set_xlabel('Time (s)')
            self.ax.set_ylabel('Position (mm)')
            self.ax.set_title(f'Frequency Sweep Signal: {self.START_FREQ}-{self.END_FREQ} Hz, {self.AMPLITUDE}mm')
            self.ax.grid(True, alpha=0.3)
            self.ax.axhline(y=0, color='k', linestyle='-', alpha=0.3)
        else:
            self.fig = Figure(figsize=(8, 3), dpi=100)
            self.ax = self.fig.add_subplot(111)
            self.ax.text(0.5, 0.5, 'Signal generation failed\nCheck console for details', 
                        ha='center', va='center', transform=self.ax.transAxes)
        
        self.canvas = FigureCanvasTkAgg(self.fig, master=plot_frame)
        self.canvas.draw()
        self.canvas.get_tk_widget().pack(fill='both', expand=True)
        
        # Status bar
        self.status_var = tk.StringVar(value="Ready" if self.current_signal is not None else "Signal Error - Check Console")
        status_bar = ttk.Label(main_frame, textvariable=self.status_var, 
                               relief='sunken', anchor='w', padding=(10, 5))
        status_bar.pack(fill='x')
        
    def refresh_ports(self):
        """Refresh available COM ports"""
        ports = serial.tools.list_ports.comports()
        port_list = [f"{p.device}" for p in ports]
        
        self.port_combo['values'] = port_list
        if port_list and not self.port_combo.get():
            self.port_combo.current(0)
        elif not port_list:
            self.port_combo.set("No ports found")
            
    def toggle_connection(self):
        """Toggle device connection"""
        if self.namazu_instance:
            self.disconnect_device()
        else:
            self.connect_device()
    
    def connect_device(self):
        """Connect to Namazu device"""
        try:
            port_selection = self.port_combo.get()
            
            if not port_selection or port_selection == "No ports found":
                messagebox.showwarning("No Port", "Please select a COM port")
                return
            
            comport = port_selection.split(' - ')[0].strip()
            
            self.status_var.set(f"Connecting to {comport}...")
            self.namazu_instance = NamazuInstance(comport)
            self.namazu_instance.connect()
            
            # Regenerate signal with device for MarvCode
            self.regenerate_with_device()
            
            # Update UI
            self.conn_canvas.itemconfig(self.conn_light, fill='#00ff00')
            self.conn_label.config(text=f"Connected - {comport}")
            self.connect_btn.config(text="Disconnect")
            self.status_var.set(f"Connected to {comport} - Ready")
            
        except Exception as e:
            self.conn_canvas.itemconfig(self.conn_light, fill='red')
            self.conn_label.config(text="Connection Failed")
            self.status_var.set(f"Connection failed: {e}")
            messagebox.showerror("Connection Error", str(e))
    
    def disconnect_device(self):
        """Disconnect from device"""
        if self.is_shaking:
            self.stop_shake_flag.set()
            if self.shake_thread and self.shake_thread.is_alive():
                self.shake_thread.join(timeout=2.0)
        
        if self.namazu_instance:
            self.namazu_instance.disconnect()
            self.namazu_instance = None
            
        self.conn_canvas.itemconfig(self.conn_light, fill='gray')
        self.conn_label.config(text="Not Connected")
        self.connect_btn.config(text="Connect")
        self.status_var.set("Disconnected")
    
    def start_shake(self):
        """Send signal and start shaking"""
        if not self.namazu_instance:
            messagebox.showwarning("Not Connected", "Connect to device first")
            return
        
        if self.is_shaking:
            messagebox.showwarning("Running", "Shaking already in progress")
            return
        
        if not self.shaking_data or not self.shaking_data.marvCode:
            messagebox.showwarning("No Signal", "Signal not properly generated")
            return
        
        try:
            # Send MarvCode
            self.status_var.set("Sending signal to device...")
            self.namazu_instance.send_command(self.shaking_data.marvCode)
            
            # Start shaking
            self.stop_shake_flag.clear()
            self.is_shaking = True
            self.shake_thread = threading.Thread(target=self._shake_worker, daemon=True)
            self.shake_thread.start()
            
            # Update UI
            self.run_btn.config(state='disabled', bg='#81C784')
            self.status_var.set("Shaking in progress...")
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed to start:\n{str(e)}")
            self.status_var.set(f"Error: {e}")
    
    def _shake_worker(self):
        """Background thread for shake monitoring"""
        try:
            self.namazu_instance.send_command("start\n")
            
            while not self.stop_shake_flag.is_set():
                try:
                    response = self.namazu_instance.query_status()
                    if response and "RUNNING" not in response:
                        break
                    time.sleep(0.5)
                except:
                    break
            
            if self.stop_shake_flag.is_set():
                self.root.after(0, lambda: self.status_var.set("Shaking stopped"))
            else:
                self.root.after(0, lambda: self.status_var.set("Shaking completed"))
                
        except Exception as e:
            self.root.after(0, lambda: self.status_var.set(f"Error: {e}"))
        finally:
            self.root.after(0, self._shake_finished)
    
    def _shake_finished(self):
        """Reset UI after shake completes"""
        self.is_shaking = False
        self.run_btn.config(state='normal', bg='#4CAF50')
        # Regenerate signal for next run
        if self.namazu_instance:
            self.regenerate_with_device()
    
    def stop_shake(self):
        """Stop the shaking"""
        if not self.namazu_instance or not self.is_shaking:
            return
        
        try:
            self.stop_shake_flag.set()
            self.namazu_instance.send_command("stop\n")
            self.status_var.set("Stopping...")
            
        except Exception as e:
            self.status_var.set(f"Stop error: {e}")
    
    def on_closing(self):
        """Handle window close"""
        if self.is_shaking:
            self.stop_shake_flag.set()
            if self.shake_thread and self.shake_thread.is_alive():
                self.shake_thread.join(timeout=2.0)
        
        if self.namazu_instance:
            try:
                self.namazu_instance.disconnect()
            except:
                pass
        
        self.root.destroy()


def main():
    root = tk.Tk()
    app = MinimalShakingUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
    