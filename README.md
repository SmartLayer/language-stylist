# Language Stylist - Quick Start Guide

## Installation

1. **Add your DeepSeek API Key**

   Edit `deepseek.json` and add your API key:
   ```json
   {
     "api_key": "sk-your-deepseek-api-key-here",
     "api_base": "https://api.deepseek.com",
     "model": "deepseek-chat"
   }
   ```

2. **Ensure dependencies are installed**
   
   The application requires Tcl/Tk 8.6+ with the following packages:
   - `tls` (for HTTPS)
   - `json` (for JSON parsing)
   
   Most Tcl installations include these by default.

## Usage

### Normal Mode

1. Copy some text to your clipboard
2. Run the application:
   ```bash
   ./language-stylist.tcl
   ```
3. The app will show:
   - Your original text (top)
   - Prompt buttons (middle)
   - Transformed text (bottom)
4. Press Enter (or click Copy) to copy the result and exit

### Test Mode

Test mode runs without GUI and outputs to stdout:

```bash
echo "Your text here" | xclip -selection clipboard
./language-stylist.tcl --test
```

Or using a different clipboard manager:

```bash
# On systems with xsel
echo "Your text here" | xsel --clipboard
./language-stylist.tcl --test

# On macOS
echo "Your text here" | pbcopy
./language-stylist.tcl --test
```

## Keyboard Shortcuts

- `1-9, 0`: Select prompts 1-10
- `Enter`: Copy result and exit (when Copy button is focused)

## Adding Custom Prompts

1. Create a `.txt` file in the `prompts/` directory
2. The filename (without .txt) becomes the button label
3. The file content is the system prompt sent to the LLM

Example: Create `prompts/formal.txt`:
```
You are a formal writing assistant. Transform the user's text into formal, professional language suitable for business communications. Maintain the original meaning while elevating the tone and vocabulary.
```

## Configuration Files

- `session.conf` - Stores the last selected prompt (auto-generated)
- `deepseek.json` - Contains API credentials (you must configure this)

## Troubleshooting

**Error: "Clipboard is empty"**
- Make sure you've copied text before launching the app

**Error: "API key not found"**
- Add your DeepSeek API key to `deepseek.json`

**Error: "Network error"**
- Check your internet connection
- Verify the API endpoint in `deepseek.json` is correct

**Error: "Prompts directory not found"**
- Ensure the `prompts/` folder exists in the same directory as the script


