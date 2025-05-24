# Shh!(ml) - An intelligent /yell spam filter for Final Fantasy XI using a machine learning model

Shh!(ml) is an addon for Windower 4 that detects and filters spam messages in Final Fantasy XI /yell. Particularly useful if you play on Asura.

## Features

- Machine learning-based spam detection
- Configurable spam threshold


## Todo

- Add commands to allow the threashold to be changed within game
- Add configurable whitelist and blacklist (currently automatic)
- Add categories of spam, such as "sellers", "dynamis", "omen" for selective filtering
    - Presently, anything that's trying to sell you something agressively is blocked

## Files

- [`shhml.lua`](shhml.lua) - Main addon file
- [`spam_detector.lua`](spam_detector.lua) - Spam detection logic
- [`spam_model.lua`](spam_model.lua) - Machine learning model data
- [`dkjson.lua`](dkjson.lua) - JSON library

## Installation

1. Place files in a folder in your Windower addons directory /addons/shhml
2. Load the addon with `//lua load shhml`
3. Enjoy peace, while still seeing relevant (non-spammy/rmt'ish) yells.

## Usage

The spam filter model will be updated frequently.