{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Add system wide packages
  environment.systemPackages = [
    pkgs.stream-sprout # restream the v4l2loopback cam below to Twitch/YouTube/Owncast/PeerTube
    pkgs.restream # TUI for the above: edit its endpoint/destinations, run it, watch the log
    pkgs.obs-cli # remote-control OBS over obs-websocket — top-level package, not an obs-studio-plugins attr
    (pkgs.wrapOBS {
      plugins = with pkgs.obs-studio-plugins; [
        wlrobs # wayland capture support
        obs-move-transition # animated move/resize/rotate transitions between scenes
        obs-scene-as-transition # use a whole scene (e.g. a logo sting) as a transition
        obs-transition-table # pick a different transition per specific scene-A -> scene-B pair
        obs-browser-transition # HTML/CSS/JS-driven transitions, for anything the built-in set can't do
        obs-backgroundremoval # OBS plugin to replace the background in portrait images and video
        obs-3d-effect # create 3d effects for transitions
        waveform # show waveform of audio
        droidcam-obs # use droidcam app on your phone to let it work as a camera. Also can remote control OBS
        obs-pipewire-audio-capture
        input-overlay # show your keyboard and mouse on screen
        obs-text-pthread # advanced tweaks for displaying text - see https://github.com/norihiro/obs-text-pthread
        obs-shaderfilter # crazy effects - see https://github.com/exeldro/obs-shaderfilter
        obs-source-record # record a source independently of the whole scene
        obs-vintage-filter # make a source look old fashioned
        #obs-vertical-canvas # use with source record to record tiktok style vertical video at the same time as your normal recording
      ];
    })
  ];

  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
  '';
  security.polkit.enable = true;
}
