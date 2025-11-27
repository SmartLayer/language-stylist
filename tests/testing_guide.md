# Language Stylist Testing Guide

## Overview
This document describes how to test the language-stylist tool in different modes.

## Test Mode (--test)

### Purpose
Test mode outputs the transformed text to stdout without showing GUI. Useful for quick testing and debugging.

### Test Procedure

1. **Prepare test text in clipboard**
   ```bash
   echo "create director's reply in response to the conduct issue, requiring John to fine tune the SOP, ensure they are signed and ensure they are followed leading to the peak season. further requires update to rules that stay on site requires director approval to prevent the similar case of airbnb use, on site groundman requires approval from director to move in and that roles and authority must be clearly documented by the sop and published. prepare that letter to send it to all key employees. propose key employee list." | xclip -selection clipboard
   ```

2. **Run in test mode**
   ```bash
   ./language-stylist.tcl --test
   ```

3. **Observe output**
   - The transformed text is printed to stdout
   - No GUI window appears
   - Original clipboard content remains unchanged

### Expected Behavior
- Reads text from clipboard
- Uses the last saved prompt (from `current-mode.conf`)
- Outputs transformed text to stdout
- Exits with code 0 on success, 1 on error
- Does NOT modify clipboard

## Autoclose Mode (-autoclose)

### Purpose
Autoclose mode transforms text using the saved prompt and automatically copies the result to clipboard, then exits. Useful for hotkey integration.

### Test Procedure

1. **Prepare test text in clipboard**
   ```bash
   echo "create director's reply in response to the conduct issue, requiring John to fine tune the SOP, ensure they are signed and ensure they are followed leading to the peak season. further requires update to rules that stay on site requires director approval to prevent the similar case of airbnb use, on site groundman requires approval from director to move in and that roles and authority must be clearly documented by the sop and published. prepare that letter to send it to all key employees. propose key employee list." | xclip -selection clipboard
   ```

2. **Run in autoclose mode**
   ```bash
   ./language-stylist.tcl -autoclose
   ```

3. **Verify transformed text is in clipboard**
   ```bash
   xclip -selection clipboard -o
   ```

### Expected Behavior
- Reads text from clipboard
- Shows minimal GUI briefly
- Uses the last saved prompt (from `current-mode.conf`)
- Automatically copies transformed text to clipboard
- Exits after 5 seconds (to ensure clipboard operation completes)
- Clipboard now contains the transformed text

### Expected Output
```
Create director's response addressing conduct issue. Require John to refine SOPs, obtain signatures, and ensure compliance before peak season. Update rules: site stays need director approval to prevent Airbnb cases, ground staff moves require director approval. Document roles and authority clearly in SOPs and distribute. Draft letter for all key employees. Propose key employee list.
```

## GUI Mode (default)

### Purpose
Full GUI mode for interactive use.

### Test Procedure

1. **Prepare test text in clipboard**
   ```bash
   echo "create director's reply in response to the conduct issue, requiring John to fine tune the SOP, ensure they are signed and ensure they are followed leading to the peak season. further requires update to rules that stay on site requires director approval to prevent the similar case of airbnb use, on site groundman requires approval from director to move in and that roles and authority must be clearly documented by the sop and published. prepare that letter to send it to all key employees. propose key employee list." | xclip -selection clipboard
   ```

2. **Run without flags**
   ```bash
   ./language-stylist.tcl
   ```

3. **Interact with GUI**
   - Original text appears in top pane
   - Prompt buttons appear in middle
   - Transformed text appears in bottom pane after API call
   - Click "Copy" button or wait for user to copy manually

### Expected Behavior
- Shows full GUI window
- Displays original text from clipboard
- Shows all available prompt buttons
- Automatically starts transformation with last used prompt
- User must manually click "Copy" button to copy result
- Window stays open until user closes it

## Common Issues

### Test Mode Issue: Multiple API requests in background
**Symptom**: When running `--test`, multiple API requests appear in stderr.
**Cause**: Unknown - test mode should make only one request.
**Workaround**: Use the first output, ignore repeated outputs.

### Autoclose Issue: Clipboard is empty after exit
**Symptom**: After autoclose completes, clipboard doesn't contain transformed text.
**Cause**: Application exits too quickly before clipboard operation completes.
**Solution**: The delay in `copyAndExit` proc is set to 5000ms (5 seconds). If issue persists, increase this value.

### Autoclose Issue: Window closes before seeing result
**Symptom**: Can't see what the transformed text looks like.
**Solution**: Check clipboard contents with `xclip -selection clipboard -o` after autoclose exits.

## Notes
- All modes use the saved prompt from `current-mode.conf`
- Default prompt is "concise" if no saved config exists
- The 5-second delay in autoclose mode is necessary for clipboard reliability
- Test mode does NOT modify clipboard, only outputs to stdout
- Autoclose mode DOES modify clipboard with the transformed text
