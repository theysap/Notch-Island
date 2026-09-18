-- Arranges the disk image window, once, on a machine with a Finder.
--
-- The result is a .DS_Store, which is committed and copied into every disk
-- image built afterwards. A build machine has no Finder to drive and must
-- never need one; see Scripts/make-dmg-layout.sh.

on run argv
    set volumeName to item 1 of argv

    tell application "Finder"
        tell disk volumeName
            open

            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            try
                set pathbar visible of container window to false
            end try
            try
                set sidebar width of container window to 0
            end try
            -- 640 x 400 of content plus the title bar. Finder measures the
            -- window, the background picture fills the content area, so the
            -- difference has to be allowed for or the picture is cropped.
            -- Height allows for both the title bar and the toolbar, which recent
-- versions of Finder will not hide however politely they are asked.
-- Measured on the real window: 64pt of chrome above the content.
            set the bounds of container window to {300, 120, 940, 584}

            set options to the icon view options of container window
            set arrangement of options to not arranged
            set icon size of options to 128
            set text size of options to 13
            set background picture of options to file ".background:background.tiff"

            -- These have to agree with Scripts/make-dmg-background.swift, which
            -- draws the arrow between them.
            set position of item "NotchIsland.app" of container window to {170, 215}
            set position of item "Applications" of container window to {470, 215}

            update without registering applications
            delay 3
            close
        end tell
    end tell
end run
