# Audio configuration with PulseAudio
{ config, lib, pkgs, ... }:

{
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
