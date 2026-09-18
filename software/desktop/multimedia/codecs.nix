# Codecs and image-format loaders, for everything that previews media.
#
# These are not applications; they are what makes other applications able to
# open a file. Nautilus thumbnails, the sushi quick-look preview and the GTK
# image loaders all depend on them, so they belong with multimedia rather than
# beside the office suite where they used to sit.

{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # GStreamer, for media preview and thumbnailing
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base # basic codecs
    gst_all_1.gst-plugins-good # common formats (JPEG, PNG, AVI, MP4)
    gst_all_1.gst-plugins-bad # additional formats (WebM, MKV)
    gst_all_1.gst-plugins-ugly # patent-encumbered formats (MP3, DVD)
    gst_all_1.gst-libav # FFmpeg-based codecs, for maximum format support

    ffmpeg-full # comprehensive video/audio codec support
    webp-pixbuf-loader # WebP in GTK applications
    libheif # HEIC/HEIF — iPhone photos
  ];
}
