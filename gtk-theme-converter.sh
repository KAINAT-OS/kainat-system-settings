#!/bin/bash
set -euo pipefail

# Kainat OS GTK → Godot Theme Converter
# Reads ~/.config/gtk-4.0/gtk.css, produces /tmp/godot-gtk-theme.css
# Logs to /var/log/kainat-gtk-theme.log

readonly GTK_CSS="${HOME}/.config/gtk-4.0/gtk.css"
readonly OUTPUT_CSS="/tmp/godot-gtk-theme.css"
readonly LOG_FILE="/var/log/kainat-gtk-theme.log"
readonly LOCK_FILE="/tmp/gtk-theme-converter.lock"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}

cleanup() {
    rm -f "$LOCK_FILE"
    log "Converter exited."
}
trap cleanup EXIT INT TERM

# Atomic locking
exec 200>"$LOCK_FILE"
flock -n 200 || { log "Another instance running, exiting."; exit 0; }

# Fallback colors (Kainat OS default – Breeze Dark)
declare -A COLORS=(
    [theme_bg_color_breeze]="#202626"
    [theme_fg_color_breeze]="#3de9e9"
    [theme_selected_bg_color_breeze]="#3de9e9"
    [theme_selected_fg_color_breeze]="#000000"
    [theme_button_decoration_focus_breeze]="#3de9e9"
    [theme_view_hover_decoration_color_breeze]="#3de9e9"
    [theme_unfocused_bg_color_breeze]="#202626"
    [theme_unfocused_fg_color_breeze]="#3de9e9"
    [tooltip_background_breeze]="#292c30"
    [tooltip_text_breeze]="#fcfcfc"
)

# Resolve @import 'colors.css' if present
resolve_import() {
    local css_dir
    css_dir="$(dirname "$GTK_CSS")"
    local import_file="${css_dir}/colors.css"
    if [[ -f "$import_file" ]]; then
        cat "$import_file"
    else
        echo ""
    fi
}

# Parse all @define-color lines from combined input
parse_colors() {
    local combined
    combined="$(cat "$GTK_CSS" 2>/dev/null || echo "")"
    combined+=$'\n'"$(resolve_import)"
    while IFS= read -r line; do
        if [[ "$line" =~ @define-color[[:space:]]+([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
            local name="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            # Remove trailing semicolon and trim whitespace
            value="${value%;}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            COLORS["$name"]="$value"
        fi
    done <<< "$combined"
}

# Map GTK roles to Godot simplified CSS selectors
generate_css() {
    local bg="${COLORS[theme_bg_color_breeze]:-${COLORS[theme_bg_color]:-#202626}}"
    local fg="${COLORS[theme_fg_color_breeze]:-${COLORS[theme_fg_color]:-#3de9e9}}"
    local selected_bg="${COLORS[theme_selected_bg_color_breeze]:-${COLORS[theme_selected_bg_color]:-$fg}}"
    local selected_fg="${COLORS[theme_selected_fg_color_breeze]:-${COLORS[theme_selected_fg_color]:-#000000}}"
    local hover_bg="${COLORS[theme_view_hover_decoration_color_breeze]:-${COLORS[theme_view_hover_decoration_color]:-$fg}}"
    local focus_bg="${COLORS[theme_button_decoration_focus_breeze]:-${COLORS[theme_button_decoration_focus]:-$fg}}"
    local unfocused_bg="${COLORS[theme_unfocused_bg_color_breeze]:-${COLORS[theme_unfocused_bg_color]:-$bg}}"
    local unfocused_fg="${COLORS[theme_unfocused_fg_color_breeze]:-${COLORS[theme_unfocused_fg_color]:-$fg}}"
    local tooltip_bg="${COLORS[tooltip_background_breeze]:-${COLORS[tooltip_background]:-#292c30}}"
    local tooltip_fg="${COLORS[tooltip_text_breeze]:-${COLORS[tooltip_text]:-#fcfcfc}}"

    cat > "$OUTPUT_CSS.tmp" <<EOF
/* Auto-generated from GTK theme by Kainat OS */
Control, Panel {
    background: $bg;
}
Label, Button {
    color: $fg;
}
ItemList, Tree {
    background: $selected_bg;
    color: $selected_fg;
}
Button:hover {
    background: $hover_bg;
}
Button:focus, Button:pressed {
    background: $focus_bg;
}
LineEdit, TextEdit {
    background: $bg;
    color: $fg;
}
TooltipPanel {
    background: $tooltip_bg;
}
TooltipLabel {
    color: $tooltip_fg;
}
*:disabled {
    color: ${COLORS[insensitive_fg_color_breeze]:-#286565};
}
EOF
    mv "$OUTPUT_CSS.tmp" "$OUTPUT_CSS"
    log "Generated $OUTPUT_CSS"
}

main() {
    log "Starting GTK theme conversion"
    if [[ ! -f "$GTK_CSS" ]]; then
        log "GTK CSS not found at $GTK_CSS – using fallback colors"
    else
        parse_colors
        log "Parsed ${#COLORS[@]} color definitions"
    fi
    generate_css
    log "Conversion completed successfully"
}

main