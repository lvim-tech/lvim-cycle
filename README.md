# lvim-cycle

A smarter `<C-a>`/`<C-x>` for Neovim — increment, decrement and cycle the value under (or after) the cursor: integers in any base, floats, dates, semantic versions, hex colors and configurable word groups.

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://github.com/lvim-tech/lvim-cycle/blob/main/LICENSE)

## Features

- **Integers** — decimal (signed), hex `0x`, binary `0b`, octal `0o`; zero-padded width preserved (`007 → 008`), hex letter case preserved, non-decimal bases clamp at 0
- **Floats** — fixed-point decimals, written precision preserved (`3.14 → 4.14`)
- **Dates & times** — `2024-01-31`, `31/12/2024`, `23:59`, `2024-06-01T10:30`, …; the **field under the cursor** (day / month / year / hour / minute) is stepped and the result is normalised (month-end, leap years, DST)
- **Semver** — the segment under the cursor is bumped and the lower ones are zeroed (`1.2.3 → 1.3.0` from the minor)
- **Hex colors** — `#rrggbb` / `#rrggbbaa`: the channel under the cursor is stepped (clamped 0–255); from the `#` all channels step at once
- **Word groups** — `true ⇄ false`, `on ⇄ off`, `&& ⇄ ||` out of the box; any custom cycle via `elements`, with case transfer (`True → False`, `TRUE → FALSE`)
- **Markdown headings** — `# ⇄ ## … ######` (a built-in augend for a `markdown` group)
- **Counts** (`5<C-a>`), **dot-repeat** (via the native `operatorfunc` seam — `.` repeats with its count), **visual mode** (first match on every selected line) and **sequential visual** `g<C-a>`/`g<C-x>` (the k-th matched line gets k × count — numbered lists in one stroke)
- **Groups** — a `default` augend list, per-**filetype** lists, and a per-buffer override (`vim.b.lvim_cycle_group`)
- **Flash** — the changed span is briefly tinted (`LvimCycleFlash`, self-themed from the lvim-utils palette)

The engine never matches **backwards**: like native `<C-a>`, only a value under or after the cursor changes (the markdown-heading augend is the deliberate exception — it works from anywhere on the heading line).

## Installation

Requires Neovim >= 0.10. [lvim-utils](https://github.com/lvim-tech/lvim-utils) is an optional dependency (palette-derived flash color and the shared config merge); without it lvim-cycle falls back to an `IncSearch` link and a bundled merge.

### lvim-installer (recommended)

Install and manage it from the LVIM package manager — open the **Plugins** tab and install / update / pin it:

```vim
:LvimInstaller plugins
```

lvim-installer installs plugins through Neovim's built-in `vim.pack`, so no external plugin manager is needed.

### Native (vim.pack)

```lua
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-utils" },
    { src = "https://github.com/lvim-tech/lvim-cycle" },
})
require("lvim-cycle").setup({})
```

## Setup

Call `setup()` optionally with a config table. The full default config:

```lua
require("lvim-cycle").setup({
    map_default_keys = true, -- <C-a>/<C-x> (normal + visual), g<C-a>/g<C-x> (visual sequential)
    flash = true, -- briefly tint the changed span (LvimCycleFlash)
    -- Augend groups. Group resolution per buffer: vim.b.lvim_cycle_group (a key of this
    -- table) → the buffer's filetype → "default". Order inside a list matters: when two
    -- augends propose equally-placed matches, the EARLIER one wins.
    groups = {
        default = {
            "int",
            "float",
            "date",
            "semver",
            "hexcolor",
            { elements = { "true", "false" } },
            { elements = { "on", "off" } },
            { elements = { "&&", "||" }, word = false },
        },
    },
})
```

A user-supplied group list **replaces** the default list wholesale (no index-merge leftovers). Every spec is validated in `setup()` — a broken one fails immediately with a `groups.<name>[<index>]: …` message.

## Usage

With `map_default_keys = true`:

| Mode   | Keys              | Action                                                          |
| ------ | ----------------- | --------------------------------------------------------------- |
| Normal | `<C-a>` / `<C-x>` | Increment / decrement the value under (or after) the cursor     |
| Visual | `<C-a>` / `<C-x>` | Increment / decrement the first match on every selected line    |
| Visual | `g<C-a>` / `g<C-x>` | Sequential: the k-th matched line gets k × count              |

All maps take a count (`5<C-a>` adds 5; `2g<C-a>` renumbers in steps of 2). Normal-mode operations dot-repeat with their count. The cursor lands on the end of the new text — or the end of the changed *field* for dates, semver and hex-color channels.

Sequential example — select these lines and press `g<C-a>`:

```text
0. first        1. first
0. second   →   2. second
0. third        3. third
```

## Augend specs

An entry in a group list is one of:

- **A built-in name**: `"int"`, `"float"`, `"date"`, `"semver"`, `"hexcolor"`, `"markdown_header"`
- **A word group**:

  ```lua
  local spec = {
      elements = { "let", "const", "var" }, -- the cycle, in order (>= 2 entries)
      cyclic = true, -- wrap around the ends (false = clamp)
      word = true, -- require word boundaries (false for operators like "&&")
      preserve_case = true, -- match case-insensitively, transfer UPPER/Title casing
  }
  ```

- **A built-in with options**:

  ```lua
  local specs = {
      { kind = "date", patterns = { "%d.%m.%Y", "%Y-%m-%d" } }, -- tokens: %Y %m %d %H %M %S
      { kind = "hexcolor", all_channels = true }, -- always step r, g and b together
      { kind = "constant", elements = { "GET", "POST", "PUT", "DELETE" } },
  }
  ```

- **A raw custom augend** — two functions and full control:

  ```lua
  local checkbox = {
      -- the best match at/after byte column `col` (1-based, inclusive), or nil
      find = function(line, col)
          local s, e = line:find("%[[ x]%]") -- a markdown checkbox
          if not s then
              return nil
          end
          return { s = s, e = e, text = line:sub(s, e) }
      end,
      -- new text (nil / unchanged = no-op) and optional 1-based cursor position within it
      add = function(text, delta, cur)
          return text == "[ ]" and "[x]" or "[ ]"
      end,
  }
  ```

### Per-filetype groups and the buffer override

```lua
require("lvim-cycle").setup({
    groups = {
        markdown = { "markdown_header", "int", "date" },
        css = { "hexcolor", "int", "float" },
    },
})
```

A buffer with one of these filetypes uses its group instead of `default`. Any buffer can also force a named group:

```lua
vim.b.lvim_cycle_group = "css"
```

## API

| Function                        | Description                                                     |
| ------------------------------- | --------------------------------------------------------------- |
| `setup({opts})`                 | Configure and start (validates every group spec)                |
| `increment({count})`            | Increment at the cursor (programmatic; no dot-repeat)           |
| `decrement({count})`            | Decrement at the cursor                                         |

`<Plug>` mappings (for `map_default_keys = false`):

```lua
vim.keymap.set("n", "+", "<Plug>(lvim-cycle-increment)")
vim.keymap.set("n", "-", "<Plug>(lvim-cycle-decrement)")
vim.keymap.set("x", "+", "<Plug>(lvim-cycle-increment)")
vim.keymap.set("x", "-", "<Plug>(lvim-cycle-decrement)")
vim.keymap.set("x", "g+", "<Plug>(lvim-cycle-increment-sequential)")
vim.keymap.set("x", "g-", "<Plug>(lvim-cycle-decrement-sequential)")
```

## Highlights

| Group            | Description                                                                     |
| ---------------- | ------------------------------------------------------------------------------- |
| `LvimCycleFlash` | The changed-span tint (~120 ms). Self-themed: `blend(yellow, bg, 0.3)` from the lvim-utils palette, re-derived on colorscheme change; links to `IncSearch` without lvim-utils |

## Health

```vim
:checkhealth lvim-cycle
```

Reports invalid group specs (pin-pointed), default keys shadowed by later mappings, the lvim-utils dependency state, the flash highlight, and a per-buffer group override.

## License

BSD 3-Clause — see [LICENSE](LICENSE).
