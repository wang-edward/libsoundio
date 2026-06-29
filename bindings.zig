global: Global,

pub const version_string = soundio_version_string;
pub const version_major = soundio_version_major;
pub const version_minor = soundio_version_minor;
pub const version_patch = soundio_version_patch;

pub fn create() error{OutOfMemory}!*Global {
    return soundio_create() orelse return error.OutOfMemory;
}

pub const Global = extern struct {
    userdata: ?*anyopaque,
    on_devices_change: ?*const fn (*Global) callconv(.C) void,
    on_backend_disconnect: ?*const fn (*Global, c_int) callconv(.C) void,
    on_events_signal: ?*const fn (*Global) callconv(.C) void,
    current_backend: Backend,
    app_name: [*:0]const u8,
    emit_rtprio_warning: ?*const fn () callconv(.C) void,
    jack_info_callback: ?*const fn ([*:0]const u8) callconv(.C) void,
    jack_error_callback: ?*const fn ([*:0]const u8) callconv(.C) void,

    pub fn destroy(soundio: *Global) void {
        soundio_destroy(soundio);
    }

    pub const ConnectError = error{
        OutOfMemory,
        SystemResources,
        /// When JACK returns JackNoSuchClient.
        ///
        /// See also `disconnect`.
        NoSuchClient,
    };

    /// Tries `connect_backend` on all available backends in order.
    ///
    /// See also `disconnect`.
    pub fn connect(soundio: *Global) ConnectError!void {
        switch (soundio_connect(soundio)) {
            .None => {},
            .Invalid => unreachable, // programmer mistake; already connected
            .NoMem => return error.OutOfMemory,
            .SystemResources => return error.SystemResources,
            .NoSuchClient => return error.NoSuchClient,
            else => unreachable, // undocumented error
        }
    }

    /// Atomically update information for all connected devices.
    ///
    /// Calling this function merely flips a pointer; the actual work of
    /// collecting device information is done elsewhere. It is performant to
    /// call this function many times per second.
    ///
    /// When you call this, the following callbacks might be called:
    /// * SoundIo::on_devices_change
    /// * SoundIo::on_backend_disconnect
    /// This is the only time those callbacks can be called.
    ///
    /// This must be called from the same thread as the thread in which you call
    /// these functions:
    /// * `input_device_count`
    /// * `output_device_count`
    /// * `get_input_device`
    /// * `get_output_device`
    /// * `default_input_device_index`
    /// * `default_output_device_index`
    ///
    /// If you do not care about learning about updated devices, you might call
    /// this function only once ever and never call `wait_events`.
    pub const flush_events = soundio_flush_events;

    /// Returns the index of the default output device.
    ///
    /// Returns `-1` if there are no devices or if you never called
    /// `flush_events`.
    pub const default_output_device_index = soundio_default_output_device_index;

    /// Always returns a device. Call `Device.unref` when done.
    ///
    /// `index` must be 0 <= index < `output_device_count`.
    pub fn get_output_device(soundio: *Global, index: c_int) *Device {
        return soundio_get_output_device(soundio, index).?;
    }

    /// This function calls `flush_events` then blocks until another event is
    /// ready or you call `wakeup`. Be ready for spurious wakeups.
    pub const wait_events = soundio_wait_events;

    /// Makes `wait_events` stop blocking.
    pub const wakeup = soundio_wakeup;
};

pub const ChannelLayout = extern struct {
    name: [*:0]const u8,
    channel_count: c_int,
    channels: [24]ChannelId,
};

pub const SampleRateRange = extern struct {
    min: c_int,
    max: c_int,
};

pub const ChannelArea = extern struct {
    ptr: [*]u8,
    step: c_int,
};

pub const Device = extern struct {
    soundio: *Global,
    id: [*:0]u8,
    name: [*:0]u8,
    aim: DeviceAim,
    layouts: [*]ChannelLayout,
    layout_count: c_int,
    current_layout: ChannelLayout,
    formats: [*]Format,
    format_count: c_int,
    current_format: Format,
    sample_rates: [*]SampleRateRange,
    sample_rate_count: c_int,
    sample_rate_current: c_int,
    software_latency_min: f64,
    software_latency_max: f64,
    software_latency_current: f64,
    is_raw: bool,
    ref_count: c_int,
    probe_error: c_int,

    /// Allocates memory and sets defaults.
    ///
    /// Next you should fill out the struct fields and then call
    /// `OutStream.open`.
    ///
    /// Sets all fields to defaults.
    ///
    /// See also `OutStream.destroy`.
    pub fn outstream_create(device: *Device) error{OutOfMemory}!*OutStream {
        return soundio_outstream_create(device) orelse return error.OutOfMemory;
    }

    pub const ref = soundio_device_ref;
    pub const unref = soundio_device_unref;
};

pub const OutStream = extern struct {
    device: *Device,
    format: Format,
    sample_rate: c_int,
    layout: ChannelLayout,
    software_latency: f64,
    volume: f32,
    userdata: ?*anyopaque,
    write_callback: ?*const fn (*OutStream, c_int, c_int) callconv(.C) void,
    underflow_callback: ?*const fn (*OutStream) callconv(.C) void,
    error_callback: ?*const fn (*OutStream, c_int) callconv(.C) void,
    name: [*:0]const u8,
    non_terminal_hint: bool,
    bytes_per_frame: c_int,
    bytes_per_sample: c_int,
    layout_error: c_int,

    pub const destroy = soundio_outstream_destroy;

    pub const OpenError = error{
        OutOfMemory,
        OpeningDevice,
        BackendDisconnected,
        SystemResources,
        /// when JACK returns `JackNoSuchClient`.
        NoSuchClient,
        /// `OutStream.channel_count` is greater than the number of channels
        /// the backend can handle.
        IncompatibleBackend,
        /// Stream parameters requested are not compatible with the chosen
        /// device.
        IncompatibleDevice,
    };

    /// After you call this function, `OutStream.software_latency` is set to
    /// the correct value.
    ///
    /// The next thing to do is call `outstream_start`.
    ///
    /// If this function returns an error, the outstream is in an invalid state
    /// and you must call `outstream_destroy` on it.
    pub fn open(outstream: *OutStream) OpenError!void {
        switch (soundio_outstream_open(outstream)) {
            .None => {},
            // SoundIoDevice::aim is not #SoundIoDeviceAimOutput
            // SoundIoOutStream::format is not valid
            // SoundIoOutStream::channel_count is greater than #SOUNDIO_MAX_CHANNELS
            .Invalid => unreachable, // programmer mistake
            .NoMem => return error.OutOfMemory,
            .OpeningDevice => return error.OpeningDevice,
            .BackendDisconnected => return error.BackendDisconnected,
            .SystemResources => return error.SystemResources,
            .NoSuchClient => return error.NoSuchClient,
            .IncompatibleBackend => return error.IncompatibleBackend,
            .IncompatibleDevice => return error.IncompatibleDevice,
            else => unreachable, // undocumented error
        }
    }

    pub const StartError = error{
        Streaming,
        OutOfMemory,
        SystemResources,
        BackendDisconnected,
    };

    /// After you call this function, `OutStream.write_callback` will be called.
    ///
    /// This function might directly call `OutStream.write_callback`.
    pub fn start(outstream: *OutStream) StartError!void {
        switch (soundio_outstream_start(outstream)) {
            .None => {},
            .Streaming => return error.Streaming,
            .NoMem => return error.OutOfMemory,
            .SystemResources => return error.SystemResources,
            .BackendDisconnected => return error.BackendDisconnected,
            else => unreachable, // undocumented error
        }
    }

    pub const BeginWriteError = error{
        Invalid,
        Streaming,
        Underflow,
        IncompatibleDevice,
    };
    /// Call this in the context of handling `OutStream.write_callback`.
    /// The given `frame_count` must be within `frame_count_min`, `frame_count_max` inclusive,
    /// and represents the preferred number of frames to write.
    /// `frame_count` will be modified to inform the caller of the actual number of frames
    /// that should be written to the returned area.
    /// After writing the frames, call `OutStream.end_write`.
    pub fn begin_write(outstream: *OutStream, frame_count: *c_int) BeginWriteError![*]ChannelArea {
        var areas: [*]ChannelArea = undefined;
        switch (soundio_outstream_begin_write(outstream, &areas, frame_count)) {
            .None => {},
            .Invalid => return error.Invalid,
            .Streaming => return error.Streaming,
            .Underflow => return error.Underflow,
            .IncompatibleDevice => return error.IncompatibleDevice,
            else => unreachable, // undocumented error
        }
        return areas;
    }
    /// Ends the write operation began by `OutStream.begin_write`.
    /// This must also be called in the context of handling `OutStream.write_callback`.
    pub fn end_write(outstream: *OutStream) error{ Streaming, Underflow }!void {
        switch (soundio_outstream_end_write(outstream)) {
            .None => {},
            .Streaming => return error.Streaming,
            .Underflow => return error.Underflow,
            else => unreachable, // undocumented error
        }
    }

    pub const PauseError = error{
        BackendDisconnected,
        Streaming,
        /// Device does not support pausing/unpausing. This error code might
        /// not be returned even if the device does not support
        /// pausing/unpausing.
        IncompatibleDevice,
        /// Backend does not support pausing/unpausing.
        IncompatibleBackend,
    };

    /// If the underlying backend and device support pausing, this pauses the
    /// stream.
    ///
    /// `OutStream.write_callback` may be called a few more times if the buffer
    /// is not full.
    ///
    /// Pausing might put the hardware into a low power state which is ideal if
    /// your software is silent for some time.
    ///
    /// This function may be called from any thread context, including
    /// `OutStream.write_callback`.
    ///
    /// Pausing when already paused or unpausing when already unpaused has no
    /// effect.
    pub fn pause(outstream: *OutStream, paused: bool) PauseError!void {
        switch (soundio_outstream_pause(outstream, paused)) {
            .None => {},
            .BackendDisconnected => return error.BackendDisconnected,
            .Streaming => return error.Streaming,
            .IncompatibleDevice => return error.IncompatibleDevice,
            .IncompatibleBackend => return error.IncompatibleBackend,
            .Invalid => unreachable, // programmer error
            else => unreachable, // undocumented error
        }
    }

    pub const ClearBufferError = error{
        Streaming,
        IncompatibleBackend,
        IncompatibleDevice,
    };

    /// Clears the output stream buffer.
    ///
    /// This function can be called from any thread.
    ///
    /// This function can be called regardless of whether the outstream is
    /// paused or not.
    ///
    /// Some backends do not support clearing the buffer. On these backends
    /// this function will return SoundIoErrorIncompatibleBackend.
    ///
    /// Some devices do not support clearing the buffer. On these devices this
    /// function might return SoundIoErrorIncompatibleDevice.
    pub fn clear_buffer(outstream: *OutStream) ClearBufferError!void {
        switch (soundio_outstream_clear_buffer(outstream)) {
            .None => {},
            .Streaming => return error.Streaming,
            .IncompatibleBackend => return error.IncompatibleBackend,
            .IncompatibleDevice => return error.IncompatibleDevice,
            else => unreachable, // undocumented error
        }
    }
};

pub const InStream = extern struct {
    device: *Device,
    format: Format,
    sample_rate: c_int,
    layout: ChannelLayout,
    software_latency: f64,
    userdata: ?*anyopaque,
    read_callback: ?*const fn (*InStream, c_int, c_int) callconv(.C) void,
    overflow_callback: ?*const fn (*InStream) callconv(.C) void,
    error_callback: ?*const fn (*InStream, c_int) callconv(.C) void,
    name: [*:0]const u8,
    non_terminal_hint: bool,
    bytes_per_frame: c_int,
    bytes_per_sample: c_int,
    layout_error: c_int,
};

pub const Error = enum(c_uint) {
    None = 0,
    NoMem = 1,
    InitAudioBackend = 2,
    SystemResources = 3,
    OpeningDevice = 4,
    NoSuchDevice = 5,
    Invalid = 6,
    BackendUnavailable = 7,
    Streaming = 8,
    IncompatibleDevice = 9,
    NoSuchClient = 10,
    IncompatibleBackend = 11,
    BackendDisconnected = 12,
    Interrupted = 13,
    Underflow = 14,
    EncodingString = 15,
};

pub const ChannelId = enum(c_uint) {
    Invalid = 0,
    FrontLeft = 1,
    FrontRight = 2,
    FrontCenter = 3,
    Lfe = 4,
    BackLeft = 5,
    BackRight = 6,
    FrontLeftCenter = 7,
    FrontRightCenter = 8,
    BackCenter = 9,
    SideLeft = 10,
    SideRight = 11,
    TopCenter = 12,
    TopFrontLeft = 13,
    TopFrontCenter = 14,
    TopFrontRight = 15,
    TopBackLeft = 16,
    TopBackCenter = 17,
    TopBackRight = 18,
    BackLeftCenter = 19,
    BackRightCenter = 20,
    FrontLeftWide = 21,
    FrontRightWide = 22,
    FrontLeftHigh = 23,
    FrontCenterHigh = 24,
    FrontRightHigh = 25,
    TopFrontLeftCenter = 26,
    TopFrontRightCenter = 27,
    TopSideLeft = 28,
    TopSideRight = 29,
    LeftLfe = 30,
    RightLfe = 31,
    Lfe2 = 32,
    BottomCenter = 33,
    BottomLeftCenter = 34,
    BottomRightCenter = 35,
    MsMid = 36,
    MsSide = 37,
    AmbisonicW = 38,
    AmbisonicX = 39,
    AmbisonicY = 40,
    AmbisonicZ = 41,
    XyX = 42,
    XyY = 43,
    HeadphonesLeft = 44,
    HeadphonesRight = 45,
    ClickTrack = 46,
    ForeignLanguage = 47,
    HearingImpaired = 48,
    Narration = 49,
    Haptic = 50,
    DialogCentricMix = 51,
    Aux = 52,
    Aux0 = 53,
    Aux1 = 54,
    Aux2 = 55,
    Aux3 = 56,
    Aux4 = 57,
    Aux5 = 58,
    Aux6 = 59,
    Aux7 = 60,
    Aux8 = 61,
    Aux9 = 62,
    Aux10 = 63,
    Aux11 = 64,
    Aux12 = 65,
    Aux13 = 66,
    Aux14 = 67,
    Aux15 = 68,
};

pub const ChannelLayoutId = enum(c_uint) {
    Mono = 0,
    Stereo = 1,
    @"2Point1" = 2,
    @"3Point0" = 3,
    @"3Point0Back" = 4,
    @"3Point1" = 5,
    @"4Point0" = 6,
    Quad = 7,
    QuadSide = 8,
    @"4Point1" = 9,
    @"5Point0Back" = 10,
    @"5Point0Side" = 11,
    @"5Point1" = 12,
    @"5Point1Back" = 13,
    @"6Point0Side" = 14,
    @"6Point0Front" = 15,
    Hexagonal = 16,
    @"6Point1" = 17,
    @"6Point1Back" = 18,
    @"6Point1Front" = 19,
    @"7Point0" = 20,
    @"7Point0Front" = 21,
    @"7Point1" = 22,
    @"7Point1Wide" = 23,
    @"7Point1WideBack" = 24,
    Octagonal = 25,
};

pub const Backend = enum(c_uint) {
    None = 0,
    Jack = 1,
    PulseAudio = 2,
    Alsa = 3,
    CoreAudio = 4,
    Wasapi = 5,
    Dummy = 6,
};

pub const DeviceAim = enum(c_uint) {
    Input = 0,
    Output = 1,
};

pub const Format = enum(c_uint) {
    Invalid = 0,
    S8 = 1,
    U8 = 2,
    S16LE = 3,
    S16BE = 4,
    U16LE = 5,
    U16BE = 6,
    S24LE = 7,
    S24BE = 8,
    U24LE = 9,
    U24BE = 10,
    S32LE = 11,
    S32BE = 12,
    U32LE = 13,
    U32BE = 14,
    Float32LE = 15,
    Float32BE = 16,
    Float64LE = 17,
    Float64BE = 18,

    pub fn get_bytes_per_frame(format: Format, channel_count: c_int) c_int {
        return soundio_get_bytes_per_sample(format) * channel_count;
    }
    pub fn get_bytes_per_second(format: Format, channel_count: c_int, sample_rate: c_int) c_int {
        return format.get_bytes_per_frame(format, channel_count) * sample_rate;
    }
};

extern fn soundio_version_string() [*:0]const u8;
extern fn soundio_version_major() c_int;
extern fn soundio_version_minor() c_int;
extern fn soundio_version_patch() c_int;
extern fn soundio_create() ?*Global;
extern fn soundio_destroy(soundio: *Global) void;
extern fn soundio_connect(soundio: *Global) Error;
extern fn soundio_connect_backend(soundio: *Global, backend: Backend) Error;
extern fn soundio_disconnect(soundio: *Global) void;
extern fn soundio_strerror(@"error": c_int) [*:0]const u8;
extern fn soundio_backend_name(backend: Backend) [*:0]const u8;
extern fn soundio_backend_count(soundio: *Global) c_int;
extern fn soundio_get_backend(soundio: *Global, index: c_int) Backend;
extern fn soundio_have_backend(backend: Backend) bool;
extern fn soundio_flush_events(soundio: *Global) void;
extern fn soundio_wait_events(soundio: *Global) void;
extern fn soundio_wakeup(soundio: *Global) void;
extern fn soundio_force_device_scan(soundio: *Global) void;
extern fn soundio_channel_layout_equal(a: *const ChannelLayout, b: *const ChannelLayout) bool;
extern fn soundio_get_channel_name(id: ChannelId) [*:0]const u8;
extern fn soundio_parse_channel_id(str: [*:0]const u8, str_len: c_int) ChannelId;
extern fn soundio_channel_layout_builtin_count() c_int;
extern fn soundio_channel_layout_get_builtin(index: c_int) *const ChannelLayout;
extern fn soundio_channel_layout_get_default(channel_count: c_int) *const ChannelLayout;
extern fn soundio_channel_layout_find_channel(layout: *const ChannelLayout, channel: ChannelId) c_int;
extern fn soundio_channel_layout_detect_builtin(layout: *ChannelLayout) bool;
extern fn soundio_best_matching_channel_layout(preferred_layouts: *const ChannelLayout, preferred_layout_count: c_int, available_layouts: *const ChannelLayout, available_layout_count: c_int) *const ChannelLayout;
extern fn soundio_sort_channel_layouts(layouts: *ChannelLayout, layout_count: c_int) void;
extern fn soundio_get_bytes_per_sample(format: Format) c_int;
extern fn soundio_format_string(format: Format) [*:0]const u8;
extern fn soundio_input_device_count(soundio: *Global) c_int;
extern fn soundio_output_device_count(soundio: *Global) c_int;
extern fn soundio_get_input_device(soundio: *Global, index: c_int) ?*Device;
extern fn soundio_get_output_device(soundio: *Global, index: c_int) ?*Device;
extern fn soundio_default_input_device_index(soundio: *Global) c_int;
extern fn soundio_default_output_device_index(soundio: *Global) c_int;
extern fn soundio_device_ref(device: *Device) void;
extern fn soundio_device_unref(device: *Device) void;
extern fn soundio_device_equal(a: *const Device, b: *const Device) bool;
extern fn soundio_device_sort_channel_layouts(device: *Device) void;
extern fn soundio_device_supports_format(device: *Device, format: Format) bool;
extern fn soundio_device_supports_layout(device: *Device, layout: *const ChannelLayout) bool;
extern fn soundio_device_supports_sample_rate(device: *Device, sample_rate: c_int) bool;
extern fn soundio_device_nearest_sample_rate(device: *Device, sample_rate: c_int) c_int;
extern fn soundio_outstream_create(device: *Device) ?*OutStream;
extern fn soundio_outstream_destroy(outstream: *OutStream) void;
extern fn soundio_outstream_open(outstream: *OutStream) Error;
extern fn soundio_outstream_start(outstream: *OutStream) Error;
extern fn soundio_outstream_begin_write(outstream: *OutStream, areas: *[*]ChannelArea, frame_count: *c_int) Error;
extern fn soundio_outstream_end_write(outstream: *OutStream) Error;
extern fn soundio_outstream_clear_buffer(outstream: *OutStream) Error;
extern fn soundio_outstream_pause(outstream: *OutStream, pause: bool) Error;
extern fn soundio_outstream_get_latency(outstream: *OutStream, out_latency: *f64) c_int;
extern fn soundio_outstream_set_volume(outstream: *OutStream, volume: f64) c_int;
extern fn soundio_instream_create(device: *Device) ?*InStream;
extern fn soundio_instream_destroy(instream: *InStream) void;
extern fn soundio_instream_open(instream: *InStream) c_int;
extern fn soundio_instream_start(instream: *InStream) c_int;
extern fn soundio_instream_begin_read(instream: *InStream, areas: [*][*]ChannelArea, frame_count: *c_int) c_int;
extern fn soundio_instream_end_read(instream: *InStream) c_int;
extern fn soundio_instream_pause(instream: *InStream, pause: bool) c_int;
extern fn soundio_instream_get_latency(instream: *InStream, out_latency: *f64) c_int;
const RingBuffer = opaque {};
extern fn soundio_ring_buffer_create(soundio: *Global, requested_capacity: c_int) ?*RingBuffer;
extern fn soundio_ring_buffer_destroy(ring_buffer: ?*RingBuffer) void;
extern fn soundio_ring_buffer_capacity(ring_buffer: ?*RingBuffer) c_int;
extern fn soundio_ring_buffer_write_ptr(ring_buffer: ?*RingBuffer) [*:0]u8;
extern fn soundio_ring_buffer_advance_write_ptr(ring_buffer: ?*RingBuffer, count: c_int) void;
extern fn soundio_ring_buffer_read_ptr(ring_buffer: ?*RingBuffer) [*:0]u8;
extern fn soundio_ring_buffer_advance_read_ptr(ring_buffer: ?*RingBuffer, count: c_int) void;
extern fn soundio_ring_buffer_fill_count(ring_buffer: ?*RingBuffer) c_int;
extern fn soundio_ring_buffer_free_count(ring_buffer: ?*RingBuffer) c_int;
extern fn soundio_ring_buffer_clear(ring_buffer: ?*RingBuffer) void;
