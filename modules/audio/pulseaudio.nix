# Audio configuration with PulseAudio
_: {
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  # PipeWire configuration
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
    systemWide = false;
  };
}
