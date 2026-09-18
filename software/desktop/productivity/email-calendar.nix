{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    thunderbird # Full-featured email, calendar, and contacts client
    gnome-calendar # GNOME Calendar - integrates with GNOME Online Accounts
    geary # GNOME email client - clean, modern interface
  ];

  # Enable GNOME Online Accounts for calendar/email integration
  services.gnome.gnome-online-accounts.enable = true;
  services.gnome.evolution-data-server.enable = true;
}
