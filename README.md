# 🤖 Free Pilot for Vim/Neovim (BETA)

A fast, lightweight, and configurable AI completion plugin that works with both local and cloud models. Get GitHub Copilot-like functionality for free or at a fraction of the cost! Built as an experiment to see what was possible with local ollama and remote openrouter AI models.

## ✨ Features

- 🚀 Real-time AI-powered code completion
- 🏠 Support for local models via [Ollama](https://ollama.com]
- ☁️  Cloud model support via [OpenRouter](https://openrouter.ai) 
- ⚡ Minimal latency, maximum productivity
- 🎯 Filetype-specific enabling/disabling
- 🎨 Fully customizable behavior

## 🎬 Demo

https://github.com/user-attachments/assets/6f5b3031-fc62-4c73-9a4c-fda0968a27a4


## 💡 Why Free Pilot?

- **Free/Low-Cost Alternative**: Use local models or pay-as-you-go cloud services instead of expensive subscriptions
- **Privacy-Focused**: Run everything locally with Ollama
- **Flexible**: Choose between local and cloud models based on your needs
- **Lightweight**: Minimal impact on editor performance
- **Customizable**: Configure exactly how and when you want AI assistance

## 🚀 Getting Started

### Prerequisites

#### Option 1: Local Setup (Free!)
1. Install [Ollama](https://ollama.ai)
2. Pull a coding-focused model:
```bash
ollama pull codellama:7b
# or for better results:
ollama pull codellama:13b
```

#### Option 2: Cloud Setup (Pay-as-you-go)
1. Create an account at [OpenRouter](https://openrouter.ai)
2. Get your API key

### Installation

Using [Vundle](https://github.com/VundleVim/Vundle.vim):
```vim
Plugin 'whatever555/free-pilot-vim'
```

Using [vim-plug](https://github.com/junegunn/vim-plug):
```vim
Plug 'whatever555/free-pilot-vim'
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
use 'whatever555/free-pilot-vim'
```

## 🛠️ Configuration Options

### General Settings
```vim
" How long to wait before triggering completion (in ms)
let g:free_pilot_debounce_delay = 500

" Maximum number of suggestions to show
let g:free_pilot_max_suggestions = 3

" Enable debug logging
let g:free_pilot_debug = 0

" Choose backend: 'ollama' or 'openrouter'
let g:free_pilot_backend = 'ollama'

" AI temperature (0.0 - 1.0, lower = more focused)
let g:free_pilot_temperature = 0.1

" Debug log file location (empty = no logging)
let g:free_pilot_log_file = ''

" Maximum tokens to generate
let g:free_pilot_max_tokens = 120
```

### Ollama Settings
```vim
" Model to use with Ollama
let g:free_pilot_ollama_model = 'codellama:13b'

" Ollama API endpoint
let g:free_pilot_ollama_url = 'http://localhost:11434/api/generate'
```

### OpenRouter Settings
```vim
" Your OpenRouter API key
let g:free_pilot_openrouter_api_key = 'your-api-key'

" Preferred model
let g:free_pilot_openrouter_model = 'anthropic/claude-2:1'

" Your site URL for OpenRouter analytics
let g:free_pilot_openrouter_site_url = 'https://github.com/whatever555/free-pilot-vim'

" Your site name for OpenRouter analytics
let g:free_pilot_openrouter_site_name = 'FreePilot.vim'
```

### Behavior Settings
```vim
" Enable on startup
let g:free_pilot_autostart = 1

" Only enable for specific filetypes (empty = all)
let g:free_pilot_include_filetypes = []

" Disable for specific filetypes
let g:free_pilot_exclude_filetypes = ['help', 'netrw', 'NvimTree', 'TelescopePrompt', 
    \ 'fugitive', 'gitcommit', 'quickfix', 'prompt']
```

## 💰 Cost Comparison

| Service | Cost | Notes |
|---------|------|-------|
| GitHub Copilot | $10/month | Fixed subscription |
| Free Pilot (Ollama) | $0 | Free, runs locally |
| Free Pilot (OpenRouter) | ~$0.01-0.10/1000 tokens | Pay for what you use |

## 🚦 Usage

1. Start typing code as normal
2. Watch as AI suggestions appear
3. Press `Tab` to accept a suggestion
4. Press `Ctrl-]` to skip a suggestion

### Commands

- `:FreePilotEnable` - Enable completion
- `:FreePilotDisable` - Disable completion
- `:FreePilotToggle` - Toggle completion
- `:FreePilotStatus` - Check current status

## 📝 A Note About Local Models

While freePilot offers completely free local AI completion through Ollama, it's important to set realistic expectations:

### Current Limitations
- Local models (like CodeLlama) running on consumer hardware may be:
  - Slower than cloud solutions
  - Less accurate in their suggestions
  - More memory-intensive
  - Limited in context understanding

This is not a limitation of freePilot itself, but rather the current state of running large language models locally.

### The Future Looks Bright
- Smaller, more efficient models are being developed
- Local model performance is improving quickly
- Hardware acceleration is getting better

### Recommended Approach
- Start with local models to test the waters
- If you need more reliable completion, consider using the OpenRouter backend
- Keep updating your Ollama models as new versions are released
- Consider this an investment in the future of local AI tools

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests

## 🐛 Troubleshooting

### Common Issues

1. **Completion not showing up?**
   - Check if the backend is running (`ollama ps` for local)
   - Verify API key for OpenRouter
   - Check `:FreePilotStatus`

2. **Slow completion?**
   - For Ollama: Try a smaller model
   - For OpenRouter: Check your internet connection
   - Adjust `g:free_pilot_debounce_delay`

3. **Wrong completions?**
   - Try a different model
   - Check if the correct filetype is detected

## 📝 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

- Ollama team for making local AI accessible
- OpenRouter for providing affordable cloud AI
- The Vim/Neovim community

---

Made with ❤️ by the Free Pilot team

*Note: This is not affiliated with GitHub Copilot or OpenAI*
