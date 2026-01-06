#!/usr/bin/wish

# Simple Tcl/Tk Clipboard Test Application

# Create main window title
wm title . "Clipboard Test - Wish 8.6"

# Create a frame for better layout
pack [frame .f -padx 10 -pady 10] -fill both -expand 1

# Add instructions
pack [label .f.instructions -text "Test the clipboard functionality:" -font {Arial 12 bold}] -pady 5

# Add a button to refresh clipboard contents
pack [button .f.getBtn -text "Refresh Clipboard Contents" -command loadClipboard] -pady 10 -padx 20 -fill x

# Add a text widget to display clipboard contents
pack [label .f.outputLabel -text "Output:"] -pady {10 5} -anchor w
pack [text .f.output -height 8 -width 45 -wrap word -state disabled] -fill both -expand 1

# Procedure to load clipboard contents
proc loadClipboard {} {
    if {[catch {clipboard get} content]} {
        .f.output configure -state normal
        .f.output delete 1.0 end
        .f.output insert 1.0 "Error: $content\n(Clipboard might be empty or inaccessible)"
        .f.output configure -state disabled
    } else {
        .f.output configure -state normal
        .f.output delete 1.0 end
        .f.output insert 1.0 "Clipboard contains:\n\n$content"
        .f.output configure -state disabled
    }
}

# Add keyboard binding (Ctrl+V or Cmd+V)
bind . <Control-v> {
    loadClipboard
}

# Add a button to set clipboard (for testing)
pack [button .f.setBtn -text "Set Clipboard to 'Hello from Tcl/Tk!'" -command {
    clipboard clear
    clipboard append "Hello from Tcl/Tk! Test message from wish 8.6"
    loadClipboard
}] -pady 10 -padx 20 -fill x

# Add quit button
pack [button .f.quitBtn -text "Quit" -command exit] -pady 10 -fill x

# Load clipboard contents immediately on startup
loadClipboard


