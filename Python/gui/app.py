import tkinter as tk
from tkinter import filedialog, ttk, messagebox
import numpy as np
import matplotlib.pyplot as plt 
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import sys

from main_FixedHarmonic import FixedHarmonic
from main_KanaiTajimiSignal import KanaiTajimiSignal
from main_ShinozukaBenchmark import ShnozukaBenchmark


class NamazuShakeTableApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Namazu - GUI")
        self.geometry("1100x700")

        self.image = None
        self.tk_image = None
        self.last_result = None

        self.input_class = FixedHarmonic(100, 5)

        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self.on_close)

    def on_close(self):
        try:
            plt.close("all")
            self.fixedHarmonic.ser.close()
        except:
            pass

        self.quit()       # stop Tk mainloop
        self.destroy()    # destroy widgets
        sys.exit(0)       # terminate Python process

    def _build_ui(self):
        # Main control frame with scrollbar
        control_container = ttk.Frame(self)
        control_container.pack(side=tk.LEFT, fill=tk.Y, padx=5)

        # Canvas for scrolling
        canvas = tk.Canvas(control_container, width=350)
        scrollbar = ttk.Scrollbar(control_container, orient="vertical", command=canvas.yview)

        # Scrollable frame inside canvas
        control_frame = ttk.Frame(canvas)
        control_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )

        canvas.create_window((0, 0), window=control_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # Enable mouse wheel scrolling
        def _on_mousewheel(event):
            canvas.yview_scroll(int(-1*(event.delta/120)), "units")
        canvas.bind("<MouseWheel>", _on_mousewheel)


        # Input
        input_frame = ttk.LabelFrame(control_frame, text="Input")
        input_frame.pack(anchor="w", pady=5, fill=tk.X, padx=5)


        # Method Selection
        method_selection_frame = ttk.Frame(input_frame)
        method_selection_frame.pack(anchor="w", pady=5, padx=5)

        ttk.Label(method_selection_frame, text="Select Input Signal Method:").pack(side=tk.LEFT)
        self.input_method = tk.StringVar(value="Fixed Harmonic")
        self.method_dropdown = ttk.Combobox(
            method_selection_frame,
            textvariable=self.input_method,
            values=["Fixed Harmonic", "Kanai Tazimi", "Shinozuka Benchmark", "Shinozuka", "PSD"],
            state="readonly",
            width=20
        )
        self.method_dropdown.bind("<<ComboboxSelected>>", self.on_select)
        self.method_dropdown.pack(side=tk.LEFT, padx=5)

        # Number of Steps
        steps_frame = ttk.Frame(input_frame)
        steps_frame.pack(anchor="w", pady=3, padx=5)
        ttk.Label(steps_frame, text=f'{"Steps per second:":<40}').pack(side=tk.LEFT)
        self.num_steps = tk.StringVar(value="100")
        self.num_steps_entry = ttk.Entry(steps_frame, textvariable=self.num_steps, width=8)
        self.num_steps_entry.pack(side=tk.LEFT, padx=5)
        ttk.Label(steps_frame, text="steps").pack(side=tk.LEFT)

        # Max number of times
        max_frame = ttk.Frame(input_frame)
        max_frame.pack(anchor="w", pady=3, padx=5)
        ttk.Label(max_frame, text=f'{"Maximum number of times:":<28}').pack(side=tk.LEFT)
        self.max_times = tk.StringVar(value="5")
        self.max_times_entry = ttk.Entry(max_frame, textvariable=self.max_times, width=8)
        self.max_times_entry.pack(side=tk.LEFT, padx=5)
        ttk.Label(max_frame, text="nos.").pack(side=tk.LEFT)

        ttk.Button(input_frame, text="Initialize Input", command=self.display_input_signal).pack(pady=5, padx=5, fill=tk.X)

        ttk.Button(input_frame, text="Generate Marv Code", command=self.write_marv_code).pack(pady=5, padx=5, fill=tk.X)


        # Send Signal
        signal_frame = ttk.LabelFrame(input_frame, text="Send Signal")
        signal_frame.pack(anchor="w", pady=5, padx=2, fill=tk.X)

        # Port
        port_frame = ttk.Frame(signal_frame)
        port_frame.pack(anchor="w", pady=3, padx=5)
        ttk.Label(port_frame, text=f'{"PORT (COM/COM3):":<30}').pack(side=tk.LEFT)
        self.port = tk.StringVar(value="COM3")
        self.port_entry = ttk.Entry(port_frame, textvariable=self.port, width=8)
        self.port_entry.pack(side=tk.LEFT, padx=5)
        # ttk.Label(port_frame, text="steps").pack(side=tk.LEFT)

        # Baud Rate
        rate_frame = ttk.Frame(signal_frame)
        rate_frame.pack(anchor="w", pady=3, padx=5)
        ttk.Label(rate_frame, text=f'{"Baud Rate:":<40}').pack(side=tk.LEFT)
        self.baud_rate = tk.StringVar(value="921600")
        self.baud_rate_entry = ttk.Entry(rate_frame, textvariable=self.baud_rate, width=8)
        self.baud_rate_entry.pack(side=tk.LEFT, padx=5)
        # ttk.Label(rate_frame, text="steps").pack(side=tk.LEFT)

        ttk.Button(signal_frame, text="Send Signal", command=self.send_signal).pack(pady=5, padx=5, fill=tk.X)
        ttk.Button(signal_frame, text="Start Motor", command=self.start_motor).pack(pady=5, padx=5, fill=tk.X)

        # Plot display area

        self.fig, self.ax = plt.subplots()
        self.canvas = FigureCanvasTkAgg(self.fig, master=self.tk_image)
        self.widget = self.canvas.get_tk_widget()
        self.widget.pack(padx=10, pady=10)

        # Status Area
        status_frame = ttk.LabelFrame(control_frame, text="Status")
        status_frame.pack(anchor="w", pady=5, padx=2, fill=tk.X)

        self.status_var = tk.StringVar()
        status_label = ttk.Label(status_frame, textvariable=self.status_var, 
                                 wraplength=350, justify='left', anchor='nw', 
                                 foreground='blue')

        # def update_wrap(event):
        #     # wraplength is in pixels; subtract padding so it doesn't touch edges
        #     wrap = max(200, event.width - 20)
        #     status_label.configure(wraplength=wrap)
        
        # status_label.bind('<Configure>', update_wrap)
        status_label.pack(fill=tk.X)

    def on_select(self, event):
        # "Fixed Harmonic", "Shinozuka Benchmark", "Shinozuka", "PSD"
        match self.input_method.get():
            case "Fixed Harmonic":
                self.input_class = FixedHarmonic(
                    stepsPerSecond=float(self.num_steps.get()),
                    maxT=float(self.max_times.get())
                    )
            case "Shinozuka Benchmark":
                self.input_class = ShnozukaBenchmark(amplitude_scaling=3)
            case "Kanai Tazimi":
                self.input_class = KanaiTajimiSignal(
                    stepsPerSecond=float(self.num_steps.get()),
                    maxT=float(self.max_times.get()),
                    maxF=12,
                    nOmega=50
                )
            case "Shinozuka":
                pass
            case "PSD":
                pass
                
    def display_input_signal(self):
        # self.input_class = FixedHarmonic(
        #     float(self.num_steps.get()), 
        #     float(self.max_times.get())
        #     )
        [self.pos_out, self.t_out, self.shaking_data_instance] = self.input_class.simulate_input_signal()
        self.ax.clear()
        self.ax.plot(self.t_out, self.pos_out)
        self.ax.set_xlabel("time in [s]")
        self.ax.set_ylabel("x in [mm]")
        self.ax.set_title(self.shaking_data_instance.fileName)
        self.canvas.draw()
        self.update_status("Data has been initialised!")

    def write_marv_code(self):
        if hasattr(self.input_class, 'write_marv_code'):
            self.input_class.write_marv_code()
            self.update_status(f"Marv code has been successfully written to {self.shaking_data_instance.fileName}")
        else:
            self.update_status("Data not yet initialised.")

    def send_signal(self):
        if hasattr(self.input_class, 'send_signal'):
            self.input_class.com_port = self.port.get()
            self.input_class.baud_rate = self.baud_rate.get() 
            self.input_class.send_signal(self)
            # self.update_status("Data sent!")
        else:
            self.update_status("Data not yet initialised.")

    def start_motor(self):
        if hasattr(self.input_class, 'start_motor'):
            self.input_class.start_motor(self)
            # self.update_status("Shaking Finished")
        else:
            self.update_status("Data not yet initialised.")

    def update_status(self, text):
        self.status_var.set(f'{self.status_var.get()}\n{text}\n{25*"-"}')