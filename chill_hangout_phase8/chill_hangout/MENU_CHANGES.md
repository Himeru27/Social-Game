# Main menu overhaul (Vibe n' Chat)

Changed: scripts/ui/main_menu.gd, scripts/ui/server_browser.gd, autoload/scene_manager.gd, tools/client_smoke.gd
New:     scripts/ui/menu_style.gd, scripts/ui/menu_backdrop.gd
Removed: scenes/server_browser/server_browser.tscn (the browser now lives inside the main menu)

- PLAY orbits the camera 180 degrees behind the character, then shows the server screen
  (same slanted white/orange style). BACK reverses it.
- Leaving a room (SceneManager.go("server_browser")) now opens the main menu straight on the server screen.
- Dark panel and red/white stripes removed. Bright sky, clouds, grass + rock terrain, sunlit trees.
- Title: "Vibe n'" white, "Chat" orange. Hover = orange. About screen recolored to orange.
