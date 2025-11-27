# Language Stylist

A hotkey-invoked desktop tool that transforms clipboard text using LLM prompts.

## Setup

1. Add your DeepSeek API key to `deepseek.json`:
   ```json
   {
     "api_key": "sk-your-key-here",
     "api_base": "https://api.deepseek.com",
     "model": "deepseek-chat"
   }
   ```

2. Make executable: `chmod +x language-stylist.tcl`

## Usage

1. Copy text to clipboard
2. Run `./language-stylist.tcl`
3. Press Enter to copy result and exit

### Test Mode

```bash
echo "Your text here" | xclip -selection clipboard && ./language-stylist.tcl --test
```

Outputs transformed text to stdout and exits automatically.

### Autoclose Mode

```bash
./language-stylist.tcl --autoclose 2>/tmp/stylist.log
```

Automatically transforms using the last-used prompt, copies the result to clipboard, and exits. All errors and status messages are written to stderr for debugging. If an error occurs, the window stays open for 5 seconds before exiting with a non-zero exit code.

## Adding Prompts

Create `.txt` files in `prompts/` directory. Filename becomes the button label.

## Keyboard Shortcuts

- `1-9, 0`: Select prompts 1-10
- `Enter`: Copy and exit (when Copy button focused)
