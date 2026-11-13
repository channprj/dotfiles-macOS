-- Migrated from Herdr (~/.config/herdr/config.toml) and iTerm2 (com.googlecode.iterm2.plist).

-- Herdr, prefix ctrl+b
rex.bind("ctrl+b>shift+k", "session.previous")
rex.bind("ctrl+b>shift+j", "session.next")
rex.bind("f5", "client.config.reload")
rex.bind("ctrl+b>r", "client.config.reload")
rex.bind("ctrl+b>s", "client.settings")
-- ctrl+b starts a sequence now, so press it twice to send ctrl+b to the program.
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })

-- iTerm2 global key map
rex.bind("shift+cmd+left", "client.tab.move", { direction = "backward" })
rex.bind("shift+cmd+right", "client.tab.move", { direction = "forward" })

-- iTerm2 Default profile (Natural Text Editing)
rex.bind("delete", "pane.send_key", { key = "ctrl+d" })
rex.bind("alt+backspace", "pane.send_key", { key = "alt+backspace" })
