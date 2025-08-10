{
    enable = true;
    workspace = {
      lookAndFeel =
        "org.kde.breezedark.desktop"; 
      colorScheme = "BreezeDark"; 
      theme = "breeze-dark";
      wallpaperPictureOfTheDay = {
        provider = "natgeo";
      };
    };

    session = {
      sessionRestore = {
        restoreOpenApplicationsOnLogin = "onLastLogout";
      };
    };

    powerdevil.AC = {
      powerProfile = "performance";
      autoSuspend.idleTimeout = 600000; # 10 minutes
      whenLaptopLidClosed = "doNothing";
    };
}