# Lua Bundler

- A single-file Lua library that bundles a Lua project into one file.

## Usage

```lua
bundler:bundle(
  '/home/user/projects/my_lib',  -- Current work directory absolute path
  './src/main.lua',               -- Application main file/entry point
  './dist/out.lua'                -- Output file
)
```
