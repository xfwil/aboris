# Aboris ReplicatedStorage Dumper

An aggressive, lightweight asset structure extraction framework designed to dump Roblox `ReplicatedStorage` instances into raw local directories and `.lua`/`.luau` source code containers without triggering typical keyword detections such as `saveinstance`.

## Features

- **Pure File Stream Generation**: Operates entirely through execution environment storage layers via string generation loops.
- **Rojo Structure Standard Integration**: Nested elements inside executable containers are converted seamlessly to standard layout targets (`init.lua`).
- **Dynamic Path Length Protection**: Automatically monitors Windows `MAX_PATH` character limits (260-character threshold) dynamically. If nested sub-folders grow too deep or long, the script automatically switches to an optimized flat-file naming scheme (`Folder.SubFolder.Script.lua`) for sisa branches to prevent OS write crashes while maintaining structural accuracy.
- **Statis CLI Progress Bar**: Completely removes spam output lines from the console window. Features a single, dynamically updating progress bar tracking exact execution percentages (`[████████░░░░] 45%`) along with the asset currently being processed.

## Installation & Usage

Run the following initialization string directly within your script executor:

```lua
getgenv().Params = {
    Folder = "Grow a Garden" -- Specify target output folder name here
}

local URL = "https://raw.githubusercontent.com/xfwil/aboris/refs/heads/main/main.lua"
loadstring(game:HttpGet(URL))()
```
