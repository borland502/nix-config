# Audio configuration with PulseAudio
{ config, lib, pkgs, ... }:

{
  # Enable sound with PulseAudio
  services.pulseaudio.enable = true;
  security.rtkit.enable = true;
  
  # PipeWire configuration (currently disabled in favor of PulseAudio)
  services.pipewire = {
    enable = false;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    systemWide = true;
  };
}
