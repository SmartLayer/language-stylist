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

## Adding Prompts

Create `.txt` files in `prompts/` directory. Filename becomes the button label.

## Keyboard Shortcuts

- `1-9, 0`: Select prompts 1-10
- `Enter`: Copy and exit (when Copy button focused)
