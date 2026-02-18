# Lua Bundler

Lightweight, single-file library designed to bundle Lua projects into a single executable file, making distribution and deployment straightforward.

## Usage

To bundle your Lua project, you can use one of the following methods:

### Using Lua Code

Insert the following snippet in your Lua project:

```lua
local bundler = loadfile('path/to/bundler.lua')
arg[1] = '.'                -- Current working directory path
arg[2] = 'example/main.lua' -- Path to the application's main file (entry point)
arg[3] = 'out.lua'          -- Output file for the bundled application
bundler()
```

### Using the Terminal

You can also bundle your project directly from the terminal with the following command:

```bash
lua path-to-bundler-dir/bundler.lua project/workdir/path entrypoint/path.lua output/file/path.lua
```

## Comments Handling

- Comments starting with **`--`** will be **removed** from the final bundle.
- Comments starting with **`---`** will be **preserved** in the output.

This differentiation allows you to maintain important notes or documentation within your code while ensuring the bundled output remains clean and concise.
