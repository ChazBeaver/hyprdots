-- Hide password-manager and authenticator windows from screen sharing.
o.window("^(proton-authenticator)$", { no_screen_share = true })
o.window({ title = "^(Proton Authenticator)$" }, { no_screen_share = true })
o.window("^([Kk]ee[Pp]ass[Xx][Cc])$", { no_screen_share = true })
o.window({ title = "^(KeePassXC)$" }, { no_screen_share = true })
